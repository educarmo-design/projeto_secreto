// extract-metric-photo — F10 (Pipeline Gemini / "tratamento das fotos"),
// Metade 1 (Tubulação Zero Storage) + extratores. Ver Documento Mestre v5.0
// §3.1/§6 e Adendo v5.1 A.1/A.2/A.3/A.4/A.5/A.8.
//
// Passo 1 (glicosímetro): tubulação Zero Storage ponta a ponta + leitura de
// visor. Passo 2 (este incremento, A.8.2): extrator de prato de comida —
// "IA traduz, backend calcula" (A.2). Os dois tipos de captura compartilham
// a MESMA tubulação (auth, leitura da imagem em RAM, chamada ao Gemini,
// destruição da mídia); só o prompt e o pós-processamento divergem por
// `X-Tipo-Aparelho`, exatamente como A.8 pede ("a tubulação é construída
// uma vez; os extratores são incrementais").
//
// É a contraparte servidora que faltava para o cliente que JÁ existe: o
// `CameraCaptureController` (Flutter) força a câmera nativa, segura os bytes
// só na RAM do aparelho, faz POST octet-stream para cá com o header
// `X-Tipo-Aparelho`, e apaga o arquivo temporário assim que a resposta chega.
// `AppConfig.metricPhotoExtractionEndpoint` já aponta para esta função.
//
// ─────────────────────────────────────────────────────────────────────────
// ZERO STORAGE (a regra inegociável §0.6 / A.1)
// ─────────────────────────────────────────────────────────────────────────
// A imagem entra como bytes crus no corpo da requisição, vive numa única
// `Uint8Array` na RAM deste processo, é convertida para base64 só para caber
// no corpo JSON que o Gemini exige, e as duas referências são descartadas (a
// `Uint8Array` é ainda sobrescrita com zeros) no `finally`, aconteça o que
// acontecer. Esta função:
//   • NUNCA chama Supabase Storage nem `Deno.writeFile`/`Deno.writeTextFile`;
//   • NÃO tem a service_role — usa a anon key com o JWT do próprio usuário
//     (menor privilégio: valida sessão via `auth.getUser`, e — só no Passo 2
//     — lê o catálogo público `alimentos_referencia` sob a RLS do usuário,
//     nunca escreve nada);
//   • não guarda a imagem em lugar nenhum além da variável local do request.
// Nada da foto sobrevive à chamada além do JSON extraído.
//
// ─────────────────────────────────────────────────────────────────────────
// "IA traduz, backend calcula/decide" (A.2/A.5)
// ─────────────────────────────────────────────────────────────────────────
// Glicosímetro: o Gemini só LÊ os dígitos do visor e diz o quanto está
// confiante — quem decide se o número entra ou é rejeitado é este servidor
// (`avaliarLeitura`), por regra determinística. Em saúde, NÃO gravar é
// melhor que gravar errado.
//
// Prato de comida: o Gemini é PROIBIDO de calcular caloria/grama — só
// identifica nome do alimento + medida caseira (colher, concha, unidade...)
// + confiança. Quem multiplica é este servidor (`calcularPrato`), cruzando
// contra `alimentos_referencia`/`alimentos_medidas_caseiras` por uma regra
// de três determinística. Zero alucinação matemática do LLM: o número final
// é 100% reproduzível a partir da tabela do banco.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-tipo-aparelho, x-image-mime',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// A.4: a resolução de envio é função do tipo de captura. Visores/dígitos
// exigem nitidez alta; o teto abaixo só protege a RAM do servidor e o
// billing do Gemini contra um corpo absurdo — 12 MB acomoda com folga uma
// foto de câmera de celular em alta qualidade. A REDUÇÃO em si (baixa
// resolução para comida, ~512px) acontece no DEVICE, antes do upload (ver
// `CameraCaptureController._resolutionPresetPara`, Flutter) — aqui o
// servidor só aceita o que chegar, dentro do teto.
const TAMANHO_MAX_BYTES = 12 * 1024 * 1024;

// Abaixo disso, tratamos como ilegível e pedimos outra foto (A.5). O Gemini
// devolve confiança em 0..1.
const CONFIANCA_MINIMA = 0.7;

// Faixa fisiologicamente plausível para glicemia capilar em mg/dL. Um número
// fora daqui é quase certamente erro de leitura de dígito (ex.: "110" lido
// como "1100", ou um mmol/L de ~5,5 confundido com mg/dL) — melhor rejeitar
// do que gravar. Glicosímetros domésticos comuns saturam em ~600 ("HI") e
// ~20 ("LO"); ficamos nessa janela de propósito conservador.
const GLICOSE_MIN_MG_DL = 20;
const GLICOSE_MAX_MG_DL = 600;

// Tetos de sanidade para o extrator de prato (não são regra clínica — só
// evitam que uma resposta absurda do modelo (ex.: "50 colheres de sopa")
// vire um cálculo grotesco). Item sem quantidade utilizável assume 1.
const QUANTIDADE_MAXIMA_ITEM_PRATO = 20;
const MAX_ITENS_PRATO = 15;

// BUG CORRIGIDO (23/jul/2026): 'gemini-2.5-flash' passou a devolver 404 —
// mensagem real do Google: "This model models/gemini-2.5-flash is no
// longer available to new users" (confirmado chamando ListModels contra a
// própria chave do projeto: o modelo ainda EXISTE e aparece listado, só
// não aceita mais tráfego de contas/chaves novas — não é um erro de
// digitação nem de formato de endpoint). 'gemini-1.5-flash' (sugestão
// inicial) também foi testado e já nem aparece mais no catálogo — já
// descontinuado por completo.
//
// 'gemini-flash-latest' é um ALIAS que o próprio Google mantém apontado
// para o modelo flash corrente — testado e confirmado funcionando (ver
// RELATÓRIO DE FIM DE TAREFA). Usar o alias em vez de uma versão fixa é
// deliberado: é o que evita esta 3ª rodada do mesmo bug na próxima vez que
// o Google aposentar uma versão numerada.
//
// Configurável via a variável de ambiente opcional GEMINI_MODEL_NAME — se
// o Google trocar de novo (ou aposentar o próprio alias), dá para corrigir
// com `supabase secrets set` sem novo deploy de código.
const MODELO_GEMINI_PADRAO = 'gemini-flash-latest';
const GEMINI_ENDPOINT_BASE =
  'https://generativelanguage.googleapis.com/v1beta/models';

// Nomes que o cliente manda em `X-Tipo-Aparelho` (é `TipoAparelho.name` do
// enum Dart). glicosimetro (Passo 1) e pratoRefeicao (Passo 2) estão
// implementados; os demais respondem 422 "ainda não implementado" — honesto
// e incremental (A.8), não um 500 confuso.
const TIPO_GLICOSIMETRO = 'glicosimetro';
const TIPO_PRATO_REFEICAO = 'pratoRefeicao';
const TIPOS_CONHECIDOS = [
  TIPO_GLICOSIMETRO,
  'pressaoArterial',
  'balanca',
  TIPO_PRATO_REFEICAO,
] as const;
const TIPOS_IMPLEMENTADOS = new Set([TIPO_GLICOSIMETRO, TIPO_PRATO_REFEICAO]);

// Os prompts ficam em inglês de propósito: o Gemini segue instrução de "só
// JSON, nada além" de forma mensuravelmente mais confiável em inglês (mesma
// escolha já registrada em GeminiGatewayService.systemPromptVisorPrato). São
// a fonte de verdade auditável do contrato de cada extrator.
const SYSTEM_PROMPT_GLICOSIMETRO = `You are a strict OCR engine that reads the digital display of a home blood glucose meter (glucometer) from a single photograph. You do NOT diagnose, interpret, or give advice. You only read the number on the screen.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "legivel": boolean,               // true only if you can read the glucose number with confidence
  "valor_mg_dl": number | null,     // the glucose reading in mg/dL as shown; null if not legible
  "confianca": number,              // 0.0 to 1.0, how sure you are of every digit
  "possivel_foto_de_tela": boolean, // true if this looks like a photo OF ANOTHER SCREEN (moiré, pixel grid, glare of a monitor)
  "motivo": string | null           // short reason when not legible (e.g. "foto borrada", "reflexo no visor", "visor parcial", "nao e um glicosimetro"); null when legible
}

Rules:
- Brazilian home glucometers display mg/dL. Report the integer as shown in "valor_mg_dl".
- If the display is blurry, reflective, partially cut off, shows "HI"/"LO"/an error code, or is not a glucometer at all: set "legivel" to false, "valor_mg_dl" to null, a low "confianca", and fill "motivo".
- NEVER guess a digit you cannot clearly see. When unsure, lower "confianca" — do not fabricate a number.
- If you can read the digits, report them even if the photo appears to be of a screen — but still set "possivel_foto_de_tela" accordingly.
- Do not include any field other than the five above.`;

// A.2 — a regra que mais importa neste prompt é a proibição explícita de
// calcular qualquer número nutricional. O Gemini identifica; o backend
// calcula (`calcularPrato`, mais abaixo).
const SYSTEM_PROMPT_PRATO_REFEICAO = `You are a strict food-identification engine analyzing a single photograph of a plate of food. You do NOT calculate calories, grams, or any nutrition number — that is done afterwards by a separate deterministic system using a reference table. Your only job is to identify what food items are visible and estimate their portion using HOME MEASURES.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "itens": [
    {
      "nome": string,        // the food name in Brazilian Portuguese, e.g. "arroz", "feijao", "bife", "ovo frito", "alface"
      "medida": string,      // a HOME MEASURE in Brazilian Portuguese, e.g. "colher de sopa", "concha media", "unidade", "fatia", "xicara", "file pequeno" — NEVER grams, NEVER milliliters
      "quantidade": number,  // how many of that measure, e.g. 2 for "2 colheres de sopa"
      "confianca": number    // 0.0 to 1.0, how sure you are of this specific item's identification and portion estimate
    }
  ],
  "possivel_foto_de_tela": boolean // true if this looks like a photo OF ANOTHER SCREEN (moire, pixel grid, glare of a monitor) instead of a real plate
}

Rules:
- You are FORBIDDEN from including any calorie, gram, kcal, or macro number anywhere in your response. Only identify food + home-measure portion.
- Estimate portion conservatively from visual size, using measures a Brazilian home cook would use (colher de sopa, colher de servir, concha, unidade, fatia, xicara, pires) — never metric weight or volume.
- One entry per distinct food item visible on the plate.
- If the plate is empty, unclear, or you cannot identify any food with reasonable confidence, return "itens": [] — do not invent an item.
- Do not include any field other than the ones described above.`;

// ─────────────────────────────────────────────────────────────────────────
// Tipos — glicosímetro (Passo 1)
// ─────────────────────────────────────────────────────────────────────────

/// O que o extrator do Gemini devolve, depois de parseado e saneado. Espelha
/// os cinco campos do prompt acima.
export interface ExtracaoGlicose {
  legivel: boolean;
  valorMgDl: number | null;
  confianca: number;
  possivelFotoDeTela: boolean;
  motivo: string | null;
}

/// Resultado da regra de decisão determinística (`avaliarLeitura`).
export interface AvaliacaoLeitura {
  aceita: boolean;
  /// Presente só quando `aceita` — o número validado, pronto para o cliente.
  glicoseMgDl?: number;
  confianca: number;
  possivelFotoDeTela: boolean;
  /// Presente só quando NÃO `aceita` — código curto do porquê da rejeição.
  motivo?: string;
}

// ─────────────────────────────────────────────────────────────────────────
// Tipos — prato de comida (Passo 2)
// ─────────────────────────────────────────────────────────────────────────

/// Um item que o Gemini identificou na foto — nunca contém número
/// nutricional, só o que os OLHOS veem: nome, medida caseira, quantidade.
export interface ExtracaoItemPrato {
  nome: string;
  medida: string;
  quantidade: number;
  confianca: number;
}

export interface ExtracaoPrato {
  itens: ExtracaoItemPrato[];
  possivelFotoDeTela: boolean;
}

/// Uma linha de `alimentos_medidas_caseiras` já tipada.
export interface MedidaCaseiraCatalogo {
  medida: string;
  gramas: number;
}

/// Uma linha de `alimentos_referencia` com suas medidas aninhadas — o
/// catálogo inteiro que `calcularPrato` consulta para transformar "2 colheres
/// de arroz" num número de calorias.
export interface AlimentoCatalogo {
  id: string;
  nomeTaco: string;
  aliases: string[];
  caloriasKcal100g: number;
  proteinasG100g: number;
  carboidratosG100g: number;
  gordurasG100g: number;
  medidas: MedidaCaseiraCatalogo[];
}

/// Item que o backend conseguiu casar contra o catálogo E calcular — os
/// únicos números nutricionais que este sistema produz, e todos vêm daqui,
/// nunca do Gemini (A.2).
export interface ItemPratoCalculado {
  /// Nome exatamente como o Gemini identificou (para o cliente eventualmente
  /// mostrar "você disse X, reconhecemos como Y" — Passo 3/tela bonita).
  nomeIdentificado: string;
  /// Nome canônico do `alimentos_referencia` que casou.
  alimentoCasado: string;
  medida: string;
  quantidade: number;
  gramasEstimados: number;
  calorias: number;
  proteinasG: number;
  carboidratosG: number;
  gordurasG: number;
  confianca: number;
}

/// Item que o Gemini identificou mas que o backend NÃO conseguiu calcular —
/// alimento fora do catálogo, ou medida caseira sem conversão cadastrada
/// para aquele alimento. Nunca é silenciosamente descartado: fica visível
/// para o usuário/telemetria decidir o que fazer (Passo 3 adiciona a busca
/// manual; aqui só registramos o motivo).
export interface ItemPratoNaoReconhecido {
  nome: string;
  medida: string;
  motivo: 'alimento_nao_encontrado' | 'medida_nao_encontrada';
}

export interface CalculoPrato {
  itens: ItemPratoCalculado[];
  itensNaoReconhecidos: ItemPratoNaoReconhecido[];
  totais: {
    calorias: number;
    proteinasG: number;
    carboidratosG: number;
    gordurasG: number;
  };
}

/// Carrega o catálogo nutricional — injetável para teste (catálogo fixo em
/// memória, sem tocar o banco), mesma filosofia do `chamarGemini` falso.
export interface CatalogoAlimentosLike {
  carregar(): Promise<AlimentoCatalogo[]>;
}

// ─────────────────────────────────────────────────────────────────────────
// Contratos compartilhados / injeção de dependência
// ─────────────────────────────────────────────────────────────────────────

/// Assina a chamada real ao Gemini, injetável para teste — assim o
/// index_test.ts exercita todo o handler sem tocar a rede nem precisar de
/// GEMINI_API_KEY (mesma filosofia do `supabaseAdmin` falso das outras
/// funções). Recebe a imagem já em base64 (nunca a Uint8Array — quem a possui
/// e a destrói é só o handler) e o prompt/pergunta específicos do extrator
/// que está chamando, e devolve o TEXTO cru do modelo.
export type ChamadorGemini = (params: {
  base64: string;
  mimeType: string;
  systemPrompt: string;
  userText: string;
}) => Promise<string>;

/// Contrato mínimo de autenticação — só o que o handler usa. Injetável para
/// teste (auth falsa em memória), como nas outras Edge Functions.
export interface AutenticadorLike {
  auth: {
    getUser(jwt: string): Promise<{
      data: { user: { id: string } | null };
      error: { message: string } | null;
    }>;
  };
}

interface HandlerDeps {
  autenticador?: AutenticadorLike;
  chamarGemini?: ChamadorGemini;
  catalogoAlimentos?: CatalogoAlimentosLike;
}

class ErroHttp extends Error {
  constructor(readonly status: number, mensagem: string) {
    super(mensagem);
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Parsing e decisão — glicosímetro (puros — sem I/O, 100% testáveis)
// ─────────────────────────────────────────────────────────────────────────

/// Extrai o JSON da resposta do Gemini de forma robusta (A.5 "tratamento de
/// erro robusto de parsing; fallback se vier texto sujo"). Mesmo pedindo
/// `responseMimeType: application/json`, tratamos a saída como não-confiável:
/// removemos cercas de markdown se aparecerem e, se ainda assim não for um
/// JSON válido com os campos esperados, devolvemos uma leitura ILEGÍVEL (nunca
/// lançamos para cima nem inventamos número).
export function parseRespostaGemini(textoCru: string): ExtracaoGlicose {
  const ilegivel = (motivo: string): ExtracaoGlicose => ({
    legivel: false,
    valorMgDl: null,
    confianca: 0,
    possivelFotoDeTela: false,
    motivo,
  });

  const bruto = extrairObjetoJson(textoCru);
  if (!bruto) return ilegivel('json_invalido');

  const valor = bruto['valor_mg_dl'];
  const confiancaBruta = bruto['confianca'];
  return {
    legivel: bruto['legivel'] === true,
    valorMgDl: typeof valor === 'number' && Number.isFinite(valor) ? valor : null,
    confianca: normalizarConfianca(confiancaBruta),
    possivelFotoDeTela: bruto['possivel_foto_de_tela'] === true,
    motivo: typeof bruto['motivo'] === 'string' ? bruto['motivo'] : null,
  };
}

/// A palavra final é do servidor, não do modelo (A.2/A.5). Uma leitura só é
/// aceita se: o modelo se declarou capaz de ler, a confiança bate o piso, há
/// um número, e o número é fisiologicamente plausível. Qualquer falha vira
/// rejeição com motivo — o cliente traduz isso em "tente outra foto".
///
/// NOTA sobre `possivel_foto_de_tela` (A.5 antifraude vs. Critério de Aceite
/// #3 do Passo 1): o Adendo pede BARRAR foto de tela para impedir farm de
/// pontos. Mas o critério de aceite mandava testar justamente fotografando
/// uma imagem de glicosímetro na tela do computador. A flag é PROPAGADA (fica
/// registrada) mas NÃO bloqueia — bloqueio duro é débito explícito para
/// quando houver device real + teste de campo (ver relatório).
export function avaliarLeitura(extracao: ExtracaoGlicose): AvaliacaoLeitura {
  const base = {
    confianca: extracao.confianca,
    possivelFotoDeTela: extracao.possivelFotoDeTela,
  };

  if (!extracao.legivel) {
    return { aceita: false, motivo: extracao.motivo ?? 'ilegivel', ...base };
  }
  if (extracao.confianca < CONFIANCA_MINIMA) {
    return { aceita: false, motivo: 'confianca_baixa', ...base };
  }
  if (extracao.valorMgDl === null) {
    return { aceita: false, motivo: 'sem_numero', ...base };
  }
  if (
    extracao.valorMgDl < GLICOSE_MIN_MG_DL ||
    extracao.valorMgDl > GLICOSE_MAX_MG_DL
  ) {
    return { aceita: false, motivo: 'fora_da_faixa', ...base };
  }
  // Arredonda: glicosímetro mostra inteiro; um "117.0" do modelo não deve
  // vazar casa decimal para o cliente.
  return { aceita: true, glicoseMgDl: Math.round(extracao.valorMgDl), ...base };
}

// ─────────────────────────────────────────────────────────────────────────
// Parsing e cálculo — prato de comida (puros — sem I/O, 100% testáveis)
// ─────────────────────────────────────────────────────────────────────────

/// Mesmo tratamento robusto de A.5 aplicado ao extrator de prato: JSON sujo,
/// truncado, ou fora do formato nunca lança — vira "nenhum item identificado"
/// (uma foto de prato vazio é um resultado LEGÍTIMO, não um erro; ver A.6 —
/// quem decide o que fazer com poucos/nenhum item é o usuário, na tela de
/// confirmação, não este parser).
export function parseRespostaGeminiPrato(textoCru: string): ExtracaoPrato {
  const vazio: ExtracaoPrato = { itens: [], possivelFotoDeTela: false };

  const bruto = extrairObjetoJson(textoCru);
  if (!bruto) return vazio;

  const itensBrutos = Array.isArray(bruto['itens']) ? bruto['itens'] : [];
  const itens: ExtracaoItemPrato[] = [];
  for (const itemBruto of itensBrutos) {
    if (itens.length >= MAX_ITENS_PRATO) break;
    if (typeof itemBruto !== 'object' || itemBruto === null) continue;
    const item = itemBruto as Record<string, unknown>;

    const nome = typeof item['nome'] === 'string' ? item['nome'].trim() : '';
    const medida = typeof item['medida'] === 'string' ? item['medida'].trim() : '';
    // Sem os dois campos mínimos (o QUE e EM QUE MEDIDA), o item é
    // descartado — nunca inventamos um nome ou uma medida que o modelo não
    // disse.
    if (!nome || !medida) continue;

    const quantidadeBruta = item['quantidade'];
    const quantidade =
      typeof quantidadeBruta === 'number' &&
      Number.isFinite(quantidadeBruta) &&
      quantidadeBruta > 0
        ? Math.min(quantidadeBruta, QUANTIDADE_MAXIMA_ITEM_PRATO)
        : 1; // ausência de quantidade não derruba o item: assume 1x a medida citada.

    itens.push({ nome, medida, quantidade, confianca: normalizarConfianca(item['confianca']) });
  }

  return { itens, possivelFotoDeTela: bruto['possivel_foto_de_tela'] === true };
}

/// Normaliza acento/caixa para casar texto livre do Gemini contra o
/// catálogo — "Arroz Branco", "arroz branco" e "arroz" devem casar com a
/// mesma linha. Puramente léxico: nunca usa IA para decidir o casamento.
export function normalizarTexto(texto: string): string {
  return texto
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
}

/// Casa o nome livre do Gemini contra `alimentos_referencia`: primeiro tenta
/// igualdade exata (nome canônico ou algum alias), depois substring nos dois
/// sentidos. Nunca "quase-casa" por similaridade fonética/fuzzy — um
/// alimento não encontrado vira `alimento_nao_encontrado`, nunca um chute.
export function encontrarAlimento(
  catalogo: AlimentoCatalogo[],
  nomeBuscado: string,
): AlimentoCatalogo | null {
  const alvo = normalizarTexto(nomeBuscado);
  if (!alvo) return null;

  const exato = catalogo.find(
    (a) =>
      normalizarTexto(a.nomeTaco) === alvo ||
      a.aliases.some((alias) => normalizarTexto(alias) === alvo),
  );
  if (exato) return exato;

  return (
    catalogo.find(
      (a) =>
        normalizarTexto(a.nomeTaco).includes(alvo) ||
        alvo.includes(normalizarTexto(a.nomeTaco)) ||
        a.aliases.some(
          (alias) => normalizarTexto(alias).includes(alvo) || alvo.includes(normalizarTexto(alias)),
        ),
    ) ?? null
  );
}

/// Mesma estratégia de `encontrarAlimento`, escopada às medidas cadastradas
/// PARA aquele alimento específico (a mesma "colher de sopa" pesa diferente
/// para arroz e para feijão — por isso a busca é sempre `alimento.medidas`,
/// nunca uma tabela de conversão global).
export function encontrarMedida(
  alimento: AlimentoCatalogo,
  medidaBuscada: string,
): MedidaCaseiraCatalogo | null {
  const alvo = normalizarTexto(medidaBuscada);
  if (!alvo) return null;

  const exata = alimento.medidas.find((m) => normalizarTexto(m.medida) === alvo);
  if (exata) return exata;

  return (
    alimento.medidas.find(
      (m) => normalizarTexto(m.medida).includes(alvo) || alvo.includes(normalizarTexto(m.medida)),
    ) ?? null
  );
}

function arredondar(valor: number, casas: number): number {
  const fator = 10 ** casas;
  return Math.round(valor * fator) / fator;
}

/// O CÁLCULO — a única função deste arquivo que produz um número
/// nutricional, e o único lugar do sistema que faz essa conta (A.2: "o
/// Gemini NÃO calcula, apenas identifica"). Regra de três pura:
/// `gramas = medida.gramas * quantidade`, depois `macro = (macro_por_100g /
/// 100) * gramas` — determinístico, reproduzível, auditável, sem LLM.
export function calcularPrato(
  itensExtraidos: ExtracaoItemPrato[],
  catalogo: AlimentoCatalogo[],
): CalculoPrato {
  const itens: ItemPratoCalculado[] = [];
  const itensNaoReconhecidos: ItemPratoNaoReconhecido[] = [];

  for (const item of itensExtraidos) {
    const alimento = encontrarAlimento(catalogo, item.nome);
    if (!alimento) {
      itensNaoReconhecidos.push({
        nome: item.nome,
        medida: item.medida,
        motivo: 'alimento_nao_encontrado',
      });
      continue;
    }

    const medida = encontrarMedida(alimento, item.medida);
    if (!medida) {
      itensNaoReconhecidos.push({
        nome: item.nome,
        medida: item.medida,
        motivo: 'medida_nao_encontrada',
      });
      continue;
    }

    const gramas = medida.gramas * item.quantidade;
    itens.push({
      nomeIdentificado: item.nome,
      alimentoCasado: alimento.nomeTaco,
      medida: item.medida,
      quantidade: item.quantidade,
      gramasEstimados: arredondar(gramas, 0),
      calorias: arredondar((alimento.caloriasKcal100g / 100) * gramas, 0),
      proteinasG: arredondar((alimento.proteinasG100g / 100) * gramas, 1),
      carboidratosG: arredondar((alimento.carboidratosG100g / 100) * gramas, 1),
      gordurasG: arredondar((alimento.gordurasG100g / 100) * gramas, 1),
      confianca: item.confianca,
    });
  }

  const somaBruta = itens.reduce(
    (acc, i) => ({
      calorias: acc.calorias + i.calorias,
      proteinasG: acc.proteinasG + i.proteinasG,
      carboidratosG: acc.carboidratosG + i.carboidratosG,
      gordurasG: acc.gordurasG + i.gordurasG,
    }),
    { calorias: 0, proteinasG: 0, carboidratosG: 0, gordurasG: 0 },
  );

  return {
    itens,
    itensNaoReconhecidos,
    totais: {
      calorias: arredondar(somaBruta.calorias, 0),
      proteinasG: arredondar(somaBruta.proteinasG, 1),
      carboidratosG: arredondar(somaBruta.carboidratosG, 1),
      gordurasG: arredondar(somaBruta.gordurasG, 1),
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Utilidades de parsing compartilhadas
// ─────────────────────────────────────────────────────────────────────────

/// Núcleo comum dos dois parsers acima: remove cercas de markdown se o
/// modelo desobedecer e devolve o objeto JSON, ou `null` se a saída não for
/// um objeto parseável — nunca lança.
function extrairObjetoJson(textoCru: string): Record<string, unknown> | null {
  let texto = textoCru.trim();
  const cerca = texto.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (cerca) texto = cerca[1].trim();

  try {
    const parsed = JSON.parse(texto);
    if (typeof parsed !== 'object' || parsed === null) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

function normalizarConfianca(valor: unknown): number {
  return typeof valor === 'number' && Number.isFinite(valor) ? Math.min(1, Math.max(0, valor)) : 0;
}

// ─────────────────────────────────────────────────────────────────────────
// base64 sem dependência nova (mantém deno.json igual ao das irmãs)
// ─────────────────────────────────────────────────────────────────────────

/// Codifica em base64 em blocos, para não estourar o limite de argumentos de
/// `String.fromCharCode`/`btoa` com imagens grandes (alta resolução, A.4).
function bytesParaBase64(bytes: Uint8Array): string {
  let binario = '';
  const bloco = 0x8000; // 32 KB por passada
  for (let i = 0; i < bytes.length; i += bloco) {
    binario += String.fromCharCode(...bytes.subarray(i, i + bloco));
  }
  return btoa(binario);
}

// ─────────────────────────────────────────────────────────────────────────
// Chamada real ao Gemini (a única I/O de rede; substituída por fake no teste)
// ─────────────────────────────────────────────────────────────────────────

// Exportada só para o teste de regressão do bug de 22/jul (modelo no
// endpoint + no texto do erro) — que stuba `fetch` global. Nenhum outro
// chamador deveria usar isto fora do próprio handler.
export function criarChamadorGeminiReal(apiKey: string, modelo: string): ChamadorGemini {
  return async ({ base64, mimeType, systemPrompt, userText }) => {
    const url = `${GEMINI_ENDPOINT_BASE}/${modelo}:generateContent?key=${apiKey}`;
    const corpo = {
      systemInstruction: {
        parts: [{ text: systemPrompt }],
      },
      contents: [
        {
          role: 'user',
          parts: [
            { inlineData: { mimeType, data: base64 } },
            { text: userText },
          ],
        },
      ],
      generationConfig: {
        // Determinístico: a mesma foto deve dar sempre a mesma identificação.
        temperature: 0,
        // Força saída JSON (A.5 "saída rígida").
        responseMimeType: 'application/json',
      },
    };

    const resposta = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(corpo),
    });

    if (!resposta.ok) {
      const detalhe = await resposta.text().catch(() => '');
      // Inclui o nome do modelo na mensagem: um 404 aqui quase sempre
      // significa "esse nome de modelo não existe mais para esta chave",
      // não um erro de rede — o log já diz de cara qual modelo falhou, sem
      // precisar ler o corpo da resposta pra descobrir.
      throw new ErroHttp(
        502,
        `Gemini (modelo "${modelo}") respondeu ${resposta.status}: ${detalhe.slice(0, 300)}`,
      );
    }

    const json = (await resposta.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const texto = json.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof texto !== 'string' || texto.length === 0) {
      // Sem texto = tratamos como ilegível/vazio nos parsers acima.
      return '{}';
    }
    return texto;
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Catálogo nutricional (a única leitura de banco desta função — Passo 2)
// ─────────────────────────────────────────────────────────────────────────

interface LinhaAlimentoBruta {
  id: string;
  nome_taco: string;
  aliases: string[] | null;
  calorias_kcal_100g: number | string;
  proteinas_g_100g: number | string;
  carboidratos_g_100g: number | string;
  gorduras_g_100g: number | string;
  alimentos_medidas_caseiras: Array<{ medida: string; gramas: number | string }> | null;
}

/// Lê `alimentos_referencia` (com suas `alimentos_medidas_caseiras`
/// aninhadas via join do PostgREST) usando o JWT do PRÓPRIO usuário — não a
/// service_role — para que a policy `to authenticated` da migration baste.
/// Dado público do produto (nenhuma linha pertence a um usuário), então uma
/// única leitura completa da tabela é suficiente; não há filtro por
/// usuário_id aqui.
function criarCatalogoAlimentosReal(
  supabaseUrl: string,
  anonKey: string,
  jwt: string,
): CatalogoAlimentosLike {
  return {
    async carregar() {
      const client = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
      });
      const { data, error } = await client
        .from('alimentos_referencia')
        .select(
          'id, nome_taco, aliases, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g, alimentos_medidas_caseiras(medida, gramas)',
        );
      if (error) {
        throw new ErroHttp(500, `Erro ao carregar alimentos_referencia: ${error.message}`);
      }

      return ((data ?? []) as unknown as LinhaAlimentoBruta[]).map((linha) => ({
        id: linha.id,
        nomeTaco: linha.nome_taco,
        aliases: linha.aliases ?? [],
        caloriasKcal100g: Number(linha.calorias_kcal_100g),
        proteinasG100g: Number(linha.proteinas_g_100g),
        carboidratosG100g: Number(linha.carboidratos_g_100g),
        gordurasG100g: Number(linha.gorduras_g_100g),
        medidas: (linha.alimentos_medidas_caseiras ?? []).map((m) => ({
          medida: m.medida,
          gramas: Number(m.gramas),
        })),
      }));
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Handler HTTP
// ─────────────────────────────────────────────────────────────────────────
export function createHandler(deps: HandlerDeps = {}) {
  return async function handleRequest(req: Request): Promise<Response> {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: CORS_HEADERS });
    }
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Método não suportado — use POST.' }, 405);
    }

    // 1) Autenticação. verify_jwt=true (config.toml) já barra quem não tem JWT
    //    válido antes de chegar aqui; revalidamos assim mesmo — defesa em
    //    profundidade e para ter o id do usuário disponível.
    const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!jwt) {
      return jsonResponse({ error: 'Token de autenticação ausente.' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');

    let autenticador: AutenticadorLike;
    if (deps.autenticador) {
      autenticador = deps.autenticador;
    } else {
      if (!supabaseUrl || !anonKey) {
        console.error('extract-metric-photo: SUPABASE_URL/ANON_KEY ausentes.');
        return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
      }
      // Só para validar o JWT. Sem service_role: esta função não escreve em
      // nenhuma tabela — menor privilégio possível.
      autenticador = createClient(supabaseUrl, anonKey) as unknown as AutenticadorLike;
    }

    const { data: userData, error: erroAuth } = await autenticador.auth.getUser(jwt);
    if (erroAuth || !userData.user) {
      return jsonResponse({ error: 'Sessão inválida ou expirada.' }, 401);
    }

    // 2) Tipo de captura.
    const tipo = req.headers.get('X-Tipo-Aparelho');
    if (!tipo || !TIPOS_CONHECIDOS.includes(tipo as (typeof TIPOS_CONHECIDOS)[number])) {
      return jsonResponse({ error: 'X-Tipo-Aparelho ausente ou desconhecido.' }, 400);
    }
    if (!TIPOS_IMPLEMENTADOS.has(tipo)) {
      return jsonResponse(
        {
          error: 'extrator_nao_implementado',
          message: `O extrator de "${tipo}" ainda não foi implementado (F10 cobre glicosímetro e prato de comida até aqui — A.8).`,
        },
        422,
      );
    }

    // 3) Lê a imagem para a RAM. A partir daqui a `Uint8Array` é a ÚNICA cópia
    //    da foto neste servidor, e o `finally` garante que ela morre aqui.
    let bytes: Uint8Array | null = null;
    let base64: string | null = null;
    try {
      const buffer = await req.arrayBuffer();
      bytes = new Uint8Array(buffer);

      if (bytes.length === 0) {
        return jsonResponse({ error: 'Corpo vazio — nenhuma imagem recebida.' }, 400);
      }
      if (bytes.length > TAMANHO_MAX_BYTES) {
        return jsonResponse({ error: 'Imagem grande demais.' }, 413);
      }

      // O cliente manda octet-stream; a câmera do celular produz JPEG. Aceita
      // um mime explícito via header se algum dia mandar PNG.
      const mimeHeader = req.headers.get('X-Image-Mime') ?? req.headers.get('Content-Type') ?? '';
      const mimeType = mimeHeader.startsWith('image/') ? mimeHeader : 'image/jpeg';

      base64 = bytesParaBase64(bytes);

      const chamarGemini =
        deps.chamarGemini ??
        (() => {
          const apiKey = Deno.env.get('GEMINI_API_KEY');
          if (!apiKey) {
            throw new ErroHttp(500, 'GEMINI_API_KEY não configurada no servidor.');
          }
          const modelo = Deno.env.get('GEMINI_MODEL_NAME') || MODELO_GEMINI_PADRAO;
          return criarChamadorGeminiReal(apiKey, modelo);
        })();

      if (tipo === TIPO_GLICOSIMETRO) {
        return await processarGlicosimetro({ base64, mimeType, chamarGemini });
      }

      // tipo === TIPO_PRATO_REFEICAO (única outra opção implementada aqui).
      let catalogoAlimentos: CatalogoAlimentosLike;
      if (deps.catalogoAlimentos) {
        catalogoAlimentos = deps.catalogoAlimentos;
      } else {
        if (!supabaseUrl || !anonKey) {
          console.error('extract-metric-photo: SUPABASE_URL/ANON_KEY ausentes.');
          return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
        }
        catalogoAlimentos = criarCatalogoAlimentosReal(supabaseUrl, anonKey, jwt);
      }

      return await processarPratoRefeicao({
        base64,
        mimeType,
        chamarGemini,
        catalogoAlimentos,
      });
    } catch (erro) {
      if (erro instanceof ErroHttp) {
        // 502 do Gemini / 500 de config ou banco: mensagem genérica ao
        // cliente, detalhe só no log do servidor.
        console.error('extract-metric-photo:', erro.message);
        return jsonResponse(
          { error: erro.status === 502 ? 'Falha ao analisar a imagem.' : 'Erro interno.' },
          erro.status,
        );
      }
      console.error('extract-metric-photo (inesperado):', mensagemDeErro(erro));
      return jsonResponse({ error: 'Erro ao processar a imagem.' }, 500);
    } finally {
      // ZERO STORAGE: destrói a mídia da RAM imediatamente, dando certo ou
      // errado. Sobrescreve os bytes com zero (não só solta a referência) e
      // descarta o base64 — nada da foto sai desta função além do JSON
      // extraído/calculado.
      if (bytes) bytes.fill(0);
      bytes = null;
      base64 = null;
    }
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Extratores (cada um: chama o Gemini certo, decide/calcula, responde)
// ─────────────────────────────────────────────────────────────────────────

async function processarGlicosimetro(params: {
  base64: string;
  mimeType: string;
  chamarGemini: ChamadorGemini;
}): Promise<Response> {
  const textoCru = await params.chamarGemini({
    base64: params.base64,
    mimeType: params.mimeType,
    systemPrompt: SYSTEM_PROMPT_GLICOSIMETRO,
    userText: 'Read the glucose value on this glucometer display.',
  });
  const extracao = parseRespostaGemini(textoCru);

  // Backend decide (determinístico). Rejeição vira 422 "tente de novo".
  const avaliacao = avaliarLeitura(extracao);
  if (!avaliacao.aceita) {
    return jsonResponse(
      {
        error: 'leitura_ilegivel',
        motivo: avaliacao.motivo,
        message:
          'Não consegui ler o visor com segurança. Tente outra foto, sem reflexo e com o número nítido.',
      },
      422,
    );
  }

  // `glicose_jejum` é a chave que o cliente
  // (HealthPayloadModel.fromAiExtraction) já sabe parsear.
  return jsonResponse(
    {
      glicose_jejum: avaliacao.glicoseMgDl,
      confianca: avaliacao.confianca,
      tipo_captura: TIPO_GLICOSIMETRO,
      possivel_foto_de_tela: avaliacao.possivelFotoDeTela,
    },
    200,
  );
}

async function processarPratoRefeicao(params: {
  base64: string;
  mimeType: string;
  chamarGemini: ChamadorGemini;
  catalogoAlimentos: CatalogoAlimentosLike;
}): Promise<Response> {
  // Gemini (identificação) e catálogo (banco) não dependem um do outro —
  // rodam em paralelo para não somar as duas latências.
  const [textoCru, catalogo] = await Promise.all([
    params.chamarGemini({
      base64: params.base64,
      mimeType: params.mimeType,
      systemPrompt: SYSTEM_PROMPT_PRATO_REFEICAO,
      userText: 'Identify the food items and their home-measure portions on this plate.',
    }),
    params.catalogoAlimentos.carregar(),
  ]);

  const extracao = parseRespostaGeminiPrato(textoCru);
  // O CÁLCULO é inteiramente do backend — o Gemini nunca viu `catalogo`.
  const calculo = calcularPrato(extracao.itens, catalogo);

  return jsonResponse(
    {
      tipo_captura: TIPO_PRATO_REFEICAO,
      itens: calculo.itens.map((item) => ({
        nome: item.alimentoCasado,
        nome_identificado: item.nomeIdentificado,
        medida: item.medida,
        quantidade: item.quantidade,
        gramas_estimados: item.gramasEstimados,
        calorias: item.calorias,
        proteinas_g: item.proteinasG,
        carboidratos_g: item.carboidratosG,
        gorduras_g: item.gordurasG,
        confianca: item.confianca,
      })),
      itens_nao_reconhecidos: calculo.itensNaoReconhecidos.map((item) => ({
        nome: item.nome,
        medida: item.medida,
        motivo: item.motivo,
      })),
      totais: {
        calorias: calculo.totais.calorias,
        proteinas_g: calculo.totais.proteinasG,
        carboidratos_g: calculo.totais.carboidratosG,
        gorduras_g: calculo.totais.gordurasG,
      },
      possivel_foto_de_tela: extracao.possivelFotoDeTela,
    },
    200,
  );
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function mensagemDeErro(erro: unknown): string {
  return erro instanceof Error ? erro.message : 'Erro desconhecido.';
}

if (import.meta.main) {
  Deno.serve(createHandler());
}
