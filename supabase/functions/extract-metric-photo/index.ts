// extract-metric-photo — F10 (Pipeline Gemini / "tratamento das fotos"),
// Metade 1 (Tubulação Zero Storage) + extratores. Ver Documento Mestre v5.0
// §3.1/§6 e Adendo v5.1 A.1/A.2/A.3/A.4/A.5/A.8/C.3.
//
// Passo 1 (glicosímetro): tubulação Zero Storage ponta a ponta + leitura de
// visor. Passo 2: extrator de prato de comida — "IA traduz, backend
// calcula" (A.2). Passo 3 (este incremento): balança/pressão arterial
// (mesmo padrão de OCR estrito do glicosímetro) e rótulo nutricional
// (transcrição de vários campos já impressos, não estimativa). Todos os
// tipos de captura compartilham a MESMA tubulação (auth, leitura da imagem
// em RAM, chamada ao Gemini, destruição da mídia); só o prompt e o
// pós-processamento divergem por `X-Tipo-Aparelho`, exatamente como A.8
// pede ("a tubulação é construída uma vez; os extratores são
// incrementais"). O MODELO Gemini usado também varia por tipo — ver "Model
// Routing" mais abaixo (C.3): OCR simples usa um modelo mais leve/barato
// que extração estruturada.
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
//
// RELATÓRIO 20260831_0001 — ACHADO durante a correção do bug de escala do
// registro descritivo: este teto de 20 é certo pra CONTAGEM de medida
// caseira ("20 colheres de sopa" já é absurdo), mas `quantidade` também é
// o campo usado pra UNIDADE BRUTA (peso/volume SI — "300 gramas", "quantidade":
// 300) quando o usuário escreve o peso explicitamente (ver
// `FATORES_UNIDADE_BRUTA` abaixo). Aplicar o MESMO teto de 20 nos dois
// casos capava silenciosamente "300 gramas" pra "20 gramas" — o próprio
// vazamento matemático relatado (a quantidade que o usuário disse nunca
// chegava inteira no cálculo). `parseRespostaGeminiPrato` agora usa este
// teto só para medida caseira; unidade bruta usa
// `QUANTIDADE_MAXIMA_UNIDADE_BRUTA_GRAMAS_OU_ML`, bem mais alto (grama e
// mililitro são a MENOR unidade que existe — um teto de 20 não faz
// sentido nenhum pra eles).
const QUANTIDADE_MAXIMA_ITEM_PRATO = 20;
// 5kg/5L por item — generoso o bastante pra qualquer prato real (mesmo um
// "1kg de churrasco" family-size), ainda protege contra um número
// absurdo/alucinado (ex.: "999999 gramas").
const QUANTIDADE_MAXIMA_UNIDADE_BRUTA_GRAMAS_OU_ML = 5000;
const MAX_ITENS_PRATO = 15;

/// Unidades BRUTAS de peso/volume (SI) que o usuário pode escrever
/// explicitamente no registro descritivo/áudio ("300 gramas de arroz",
/// "200ml de suco") — os prompts `SYSTEM_PROMPT_PRATO_REFEICAO_TEXTO`/
/// `_AUDIO` permitem ao Gemini devolver isso em `medida` só quando o
/// usuário disse o peso/volume explicitamente (confirmado chamando o
/// Gemini de verdade nesta investigação: "300 gramas de X" sempre volta
/// `medida: "gramas"`, `quantidade: 300`). Diferente de uma medida caseira
/// (que É específica de um alimento — "concha" de feijão ≠ "concha" de
/// arroz), uma unidade bruta é universal: 300 gramas são 300 gramas pra
/// QUALQUER alimento, nunca deveria passar pela tabela de medidas caseiras
/// por alimento. Usado tanto por `parseRespostaGeminiPrato` (escolher o
/// teto de sanidade certo) quanto por `encontrarMedida` (resolver a
/// conversão em si) — fonte única, nunca duplicada entre os dois.
/// Valor = gramas por UNIDADE da medida (mesma convenção de
/// `MedidaCaseiraCatalogo.gramas`) — quem multiplica pela quantidade é
/// sempre `calcularItem`, nunca aqui.
const FATORES_UNIDADE_BRUTA: Record<string, number> = {
  grama: 1,
  g: 1,
  quilograma: 1000,
  quilo: 1000,
  kg: 1000,
  mililitro: 1,
  ml: 1,
  litro: 1000,
  l: 1000,
};

// Faixa fisiologicamente plausível de peso corporal adulto em kg. Mesmo
// espírito de GLICOSE_MIN_MG_DL/MAX — um "705" lido por engano em vez de
// "70.5" precisa ser rejeitado, não gravado.
const PESO_MIN_KG = 20;
const PESO_MAX_KG = 300;

// Faixas fisiologicamente plausíveis para o extrator de pressão arterial —
// mesmo espírito de GLICOSE_MIN_MG_DL/MAX. Sistólica sempre maior que
// diastólica é checagem de consistência, não só faixa isolada.
const SISTOLICA_MIN_MMHG = 60;
const SISTOLICA_MAX_MMHG = 260;
const DIASTOLICA_MIN_MMHG = 30;
const DIASTOLICA_MAX_MMHG = 150;
const PULSO_MIN_BPM = 30;
const PULSO_MAX_BPM = 220;

// Tetos de sanidade para o extrator de rótulo (não são regra clínica — só
// evitam um valor absurdo do modelo). "ingredientes_principais" cru nunca
// vem sem limite do Gemini — capado aqui mesmo assim, defesa em
// profundidade (mesmo padrão de MAX_ITENS_PRATO).
const CALORIAS_MAX_ROTULO_KCAL = 2000;
const MAX_INGREDIENTES_ROTULO = 10;

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
// deliberado: é o que evita repetir esse bug na próxima vez que o Google
// aposentar uma versão numerada.
const GEMINI_ENDPOINT_BASE =
  'https://generativelanguage.googleapis.com/v1beta/models';

// ─────────────────────────────────────────────────────────────────────────
// Model Routing por complexidade (Adendo v5.1 A.4/C.3)
// ─────────────────────────────────────────────────────────────────────────
// Cada tipo_captura usa o modelo Gemini proporcional à dificuldade real da
// tarefa: OCR de um único valor isolado (glicosímetro/balança/pressão) não
// precisa do mesmo raciocínio visual que estruturar uma tabela nutricional
// inteira (prato/rótulo) — e um futuro exame laboratorial de várias
// páginas (HEAVY, ver abaixo) precisa de ainda mais.
//
// DESVIO REGISTRADO (ver RELATÓRIO): a tarefa pedia os nomes fixos
// 'gemini-3.5-flash-lite'/'gemini-3.5-flash'/'gemini-3.5-pro' como padrão
// de cada nível. Antes de hardcodar qualquer nome de modelo neste arquivo
// DE NOVO (é a mesma classe de bug do parágrafo acima, 2ª vez que uma
// suposição sobre nome de modelo precisa ser verificada contra a API real
// antes de virar código), testei os três contra a própria chave do
// projeto: 'gemini-3.5-flash-lite' e 'gemini-3.5-flash' respondem 200 (o
// segundo com um 503 passageiro de alta demanda no momento do teste — não
// é problema de nome), mas 'gemini-3.5-pro' devolve 404 HOJE — não existe
// para esta chave. Os ALIASES abaixo ('-latest', mesmo padrão já em uso
// neste arquivo desde o bug de 23/jul) são os padrões reais — testados e
// confirmados funcionando os três (`gemini-flash-lite-latest`,
// `gemini-flash-latest`, `gemini-pro-latest`). Continuam 100%
// configuráveis por env var: se um dia `gemini-3.5-flash` (ou qualquer
// outro nome fixo) for realmente o que se quer travar, basta
// `supabase secrets set GEMINI_MODEL_CORE=gemini-3.5-flash` sem tocar em
// código.
type NivelModelo = 'lite' | 'core' | 'heavy';

const MODELO_LITE_PADRAO = 'gemini-flash-lite-latest';
const MODELO_CORE_PADRAO = 'gemini-flash-latest';
// HEAVY: terreno preparado (tipo + resolução existem), mas nenhum
// tipo_captura usa 'heavy' ainda — reservado para o extrator de exame
// (PDF/foto de laudo laboratorial, item futuro do F10/A.8), fora do escopo
// desta tarefa.
const MODELO_HEAVY_PADRAO = 'gemini-pro-latest';

function resolverModelo(nivel: NivelModelo): string {
  switch (nivel) {
    case 'lite':
      return Deno.env.get('GEMINI_MODEL_LITE') || MODELO_LITE_PADRAO;
    case 'core':
      return Deno.env.get('GEMINI_MODEL_CORE') || MODELO_CORE_PADRAO;
    case 'heavy':
      return Deno.env.get('GEMINI_MODEL_HEAVY') || MODELO_HEAVY_PADRAO;
  }
}

// Busca semântica (Missão F45/Adendo v5.1 A.3) — fallback só para itens que
// `encontrarAlimento` (exato/substring) não achou. Mesmo modelo/dimensão de
// scripts/seed_food_embeddings.ts e supabase/functions/search-food/index.ts
// — os três precisam concordar, ou os vetores não ficam comparáveis entre
// si (ver nota em `resolverComBuscaSemantica`).
// N20 (Regra 16/20, Parte 0): nome do modelo vem da secret
// EMBEDDING_MODEL_NAME (mesma secret lida por search-food/index.ts e por
// scripts/seed_food_embeddings.ts) — deixar hardcoded aqui era exatamente o
// tipo de divergência que já causou um incidente (modelo trocado 4× entre
// 30/jul e 01/ago sem as três pontas ficarem sincronizadas). Fallback
// 'gemini-embedding-001' só para ambiente local sem a secret configurada.
const MODELO_EMBEDDING = Deno.env.get('EMBEDDING_MODEL_NAME') || 'gemini-embedding-001';
const GEMINI_EMBED_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODELO_EMBEDDING}:embedContent`;
const DIMENSOES_EMBEDDING = 768;

/** `Number(env) || fallback` trataria "0" configurado como ausente — helper explícito em vez disso. */
function envFloat(nome: string, valorPadrao: number): number {
  const bruto = Deno.env.get(nome);
  if (bruto === undefined || bruto === '') return valorPadrao;
  const numero = Number(bruto);
  return Number.isFinite(numero) ? numero : valorPadrao;
}

// AJUSTADO (31/jul/2026) após falhas em campo: "carne bovina em cubos"
// (0.58) não passava em 0.68. Redução para 0.55 permite maior cobertura
// (gírias brasileiras, preparações) sem comprometer excessivamente
// especificidade. Falsos positivos (sushi->pescada) ainda ficam abaixo
// (0.626<0.55 é falso). MESMO PADRÃO de search-food/index.ts — N20 tornou
// os dois configuráveis via secret em vez de constante fixa, mas o valor
// vigente (0.55) não muda: é o mesmo risco aceito e documentado como R20
// no Mestre v7.0.
const BUSCA_SEMANTICA_THRESHOLD = envFloat('BUSCA_SEMANTICA_THRESHOLD', 0.55);

// ⚠️ REMOVIDO: Pesos típicos agora vêm do PostgreSQL
// Anteriormente: PESO_TIPICO_GRAMAS, ALIMENTOS_LIQUIDOS, TAMANHO_COPOS_ML
// Esses dados foram centralizados na migração 20260802120000_categorias_alimentos_pesos_padrao.sql
// como colunas na tabela `alimentos_referencia`:
//   - categoria_consumo: 'liquido_frio', 'liquido_quente', 'unidade', 'fatia', 'peso_livre'
//   - unidade_medida_padrao: 'g' ou 'ml'
//   - medida_padrao_nome: rótulo (ex: "Copo Pequeno", "Unidade")
//   - medida_padrao_qtd: valor numérico (5 para azeitona, 200 para xícara, etc.)
//
// Benefícios de mover para o DB:
// 1. Single Source of Truth — o catálogo do backend coincide com o da UI
// 2. Maior ciclo de vida — o fundador audita e atualiza via migration, não via PR
// 3. Sem hardcode — cada alimento tem sua própria categoria/peso, sem dicionários genéricos
// 4. Graceful Degradation — null em categoria_consumo → UI cai para input livre de gramas

// Nomes que o cliente manda em `X-Tipo-Aparelho` (é `TipoAparelho.name` do
// enum Dart em `camera_capture_controller.dart` — glicosimetro/
// pressaoArterial/balanca/pratoRefeicao já existem lá). `TIPO_ROTULO` é
// NOVO: o enum Dart ainda não tem esse caso (ver RELATÓRIO) — o servidor
// já aceita o tipo, mas nenhuma tela do app ainda manda essa captura.
const TIPO_GLICOSIMETRO = 'glicosimetro';
const TIPO_PRESSAO_ARTERIAL = 'pressaoArterial';
const TIPO_BALANCA = 'balanca';
const TIPO_PRATO_REFEICAO = 'pratoRefeicao';
const TIPO_ROTULO = 'rotulo';
// RELATÓRIO 20260824_0003 — Registro de Refeição, 4 métodos (Documento
// Mestre): além da foto (TIPO_PRATO_REFEICAO, já existia), o usuário agora
// pode DESCREVER a refeição em texto livre ou FALAR ela — os três produzem
// exatamente o mesmo contrato de saída (`itens: [{nome, medida,
// quantidade, confianca}]`), processado pela MESMA `processarPratoRefeicao`
// (ver `fonte` no seu params) — só o prompt/entrada pro Gemini muda.
const TIPO_PRATO_REFEICAO_TEXTO = 'pratoRefeicaoTexto';
const TIPO_PRATO_REFEICAO_AUDIO = 'pratoRefeicaoAudio';
const TIPOS_CONHECIDOS = [
  TIPO_GLICOSIMETRO,
  TIPO_PRESSAO_ARTERIAL,
  TIPO_BALANCA,
  TIPO_PRATO_REFEICAO,
  TIPO_ROTULO,
  TIPO_PRATO_REFEICAO_TEXTO,
  TIPO_PRATO_REFEICAO_AUDIO,
] as const;
// Todos os tipos conhecidos têm extrator implementado agora — não sobra
// nenhum caso "conhecido mas ainda não implementado" (o 422
// `extrator_nao_implementado` abaixo continua existindo para um tipo
// futuro que venha a ser adicionado a TIPOS_CONHECIDOS antes do extrator
// correspondente, mesmo espírito incremental de A.8).
const TIPOS_IMPLEMENTADOS = new Set([
  TIPO_GLICOSIMETRO,
  TIPO_PRESSAO_ARTERIAL,
  TIPO_BALANCA,
  TIPO_PRATO_REFEICAO,
  TIPO_ROTULO,
  TIPO_PRATO_REFEICAO_TEXTO,
  TIPO_PRATO_REFEICAO_AUDIO,
]);

/// Nível de modelo por tipo de captura (ver Model Routing acima) — OCR de
/// um único valor isolado usa LITE; extração estruturada com vários campos
/// usa CORE. Tipo sem entrada aqui cai em 'core' por padrão (mais seguro
/// que 'lite' para um extrator futuro ainda não classificado).
// RELATÓRIO 20260824_0003 — texto/áudio do prato entram em LITE (não
// CORE): interpretar uma frase já escrita/falada em itens de comida é uma
// tarefa de linguagem simples, sem o raciocínio de cena visual (oclusão,
// porção por tamanho aparente) que originalmente justificou CORE pra
// foto — mesma lógica já usada pra OCR simples (glicosímetro/balança/
// pressão).
//
// RELATÓRIO 20260825_0005 — foto do prato TAMBÉM migrou pra LITE. Achado
// em investigação ao vivo (RELATÓRIO 20260825_0004, chamando o Gemini de
// verdade): o CORE (`gemini-flash-latest`) tem disponibilidade instável
// no free tier — variou de 200 OK em <2s até 503 "high demand" levando
// 45-59s só pra devolver o ERRO, e uma vez levou a própria Edge Function
// a ser matada pela Supabase por estourar o teto de execução da
// plataforma (`WORKER_RESOURCE_LIMIT`, ~150s). O LITE
// (`gemini-flash-lite-latest`), testado em paralelo com uma imagem real,
// respondeu certo em <2s em TODAS as chamadas do dia, sem uma falha
// sequer. Decisão do fundador: aceitar a troca de "mais raciocínio de
// cena" por "disponibilidade confiável" — reconhecer os alimentos de um
// prato não exige o mesmo nível de reasoning que o OCR de rótulo
// nutricional (`TIPO_ROTULO`, que continua em CORE — não fez parte desta
// decisão, dígitos de macro errados importam mais que "esqueceu uma
// azeitona no prato"). Fixar numa versão mais antiga do Flash pra fugir
// da fila foi investigado e descartado: a Google desativa versões
// antigas (`gemini-2.5-flash`/`gemini-2.0-flash` já devolvem 404 "no
// longer available"), então todo mundo no free tier acaba forçado pro
// MESMO modelo "-latest" mais recente — não tem versão "menos
// concorrida" pra escolher.
const NIVEL_POR_TIPO: Record<string, NivelModelo> = {
  [TIPO_GLICOSIMETRO]: 'lite',
  [TIPO_BALANCA]: 'lite',
  [TIPO_PRESSAO_ARTERIAL]: 'lite',
  [TIPO_PRATO_REFEICAO]: 'lite',
  [TIPO_ROTULO]: 'core',
  [TIPO_PRATO_REFEICAO_TEXTO]: 'lite',
  [TIPO_PRATO_REFEICAO_AUDIO]: 'lite',
};

/// Resolve o modelo real para um `tipo_captura` — exportada para teste
/// direto do roteador, sem precisar montar uma requisição HTTP completa.
export function resolverModeloParaTipo(tipo: string): string {
  const nivel = NIVEL_POR_TIPO[tipo] ?? 'core';
  return resolverModelo(nivel);
}

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

// RELATÓRIO 20260824_0003 — Método 1 (descritivo): mesmo contrato de saída
// de SYSTEM_PROMPT_PRATO_REFEICAO acima (itens/nome/medida/quantidade/
// confianca), processado pela MESMA `processarPratoRefeicao` — só a
// ENTRADA muda (texto digitado em vez de foto), então as regras trocam
// "estimar da imagem" por "usar exatamente o que a pessoa escreveu".
const SYSTEM_PROMPT_PRATO_REFEICAO_TEXTO = `You are a strict food-identification engine parsing a MEAL DESCRIPTION WRITTEN IN TEXT (Brazilian Portuguese) by a user — not a photo. You do NOT calculate calories, grams, or any nutrition number — that is done afterwards by a separate deterministic system using a reference table. Your only job is to break the description into individual food items with their home-measure portions, exactly as the user wrote them.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "itens": [
    {
      "nome": string,        // the food name in Brazilian Portuguese, e.g. "arroz", "feijao", "bife", "alface", "tomate"
      "medida": string,      // the HOME MEASURE exactly as stated or clearly implied, e.g. "colher de sopa", "folha", "rodela", "unidade pequena" — NEVER grams, NEVER milliliters, unless the user explicitly wrote a gram/ml value themselves
      "quantidade": number,  // how many of that measure, e.g. 2 for "2 colheres de arroz"; assume 1 if the user didn't state a number
      "confianca": number    // 0.0 to 1.0 — lower only when the description is genuinely ambiguous, not just because it's text instead of a photo
    }
  ]
}

Rules:
- You are FORBIDDEN from including any calorie, gram, kcal, or macro number anywhere in your response. Only identify food + home-measure portion.
- One entry per distinct food item mentioned — split compound descriptions ("arroz com feijão") into separate items.
- NEVER invent a food item the user did not mention. If the text has nothing food-related, return "itens": [].
- Do not include any field other than the ones described above.`;

// RELATÓRIO 20260824_0003 — Método 2 (áudio): mesmo contrato de saída,
// entrada é um ÁUDIO CURTO (não foto, não texto) — o Gemini ouve e já
// extrai os itens numa chamada só (decisão do fundador: mais barato em
// cota do que transcrever e interpretar em duas chamadas separadas). O
// ÁUDIO EM SI NUNCA É ARMAZENADO (Zero Storage, mesmo princípio do F10
// Passo 1/glicosímetro) — processado em memória e descartado pelo
// `finally` do handler, igual a uma foto.
const SYSTEM_PROMPT_PRATO_REFEICAO_AUDIO = `You are a strict food-identification engine listening to a SHORT AUDIO RECORDING (Brazilian Portuguese) where a user describes, out loud, a meal they ate. You do NOT calculate calories, grams, or any nutrition number — that is done afterwards by a separate deterministic system using a reference table. Your only job is to identify what food items were mentioned and their home-measure portions.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "itens": [
    {
      "nome": string,        // the food name in Brazilian Portuguese, e.g. "arroz", "feijao", "bife", "alface", "tomate"
      "medida": string,      // the HOME MEASURE as spoken or clearly implied, e.g. "colher de sopa", "folha", "rodela", "unidade pequena" — NEVER grams, NEVER milliliters, unless the speaker explicitly said a gram/ml value
      "quantidade": number,  // how many of that measure, e.g. 2 for "2 colheres de arroz"; assume 1 if not stated
      "confianca": number    // 0.0 to 1.0 — lower when the audio is unclear, noisy, or the wording is ambiguous
    }
  ]
}

Rules:
- You are FORBIDDEN from including any calorie, gram, kcal, or macro number anywhere in your response. Only identify food + home-measure portion.
- One entry per distinct food item mentioned — split compound mentions ("arroz com feijão") into separate items.
- NEVER invent a food item that was not spoken. If the audio is silent, unintelligible, or not about food, return "itens": [].
- Do not include any field other than the ones described above.`;

// Mesmo padrão estrito de OCR do glicosímetro acima — visor de balança
// doméstica, um único valor.
const SYSTEM_PROMPT_BALANCA = `You are a strict OCR engine that reads the digital display of a home body-weight scale (bathroom scale) from a single photograph. You do NOT diagnose, interpret, or give advice. You only read the number on the screen.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "legivel": boolean,
  "peso_kg": number | null,         // the weight in kilograms as shown; null if not legible
  "confianca": number,              // 0.0 to 1.0, how sure you are of every digit
  "possivel_foto_de_tela": boolean, // true if this looks like a photo OF ANOTHER SCREEN (moiré, pixel grid, glare of a monitor)
  "motivo": string | null           // short reason when not legible; null when legible
}

Rules:
- Brazilian home scales display kg by default. If the display clearly shows "lb" instead, convert to kg (1 lb = 0.453592 kg) and still report "peso_kg" in kilograms.
- If the display is blurry, reflective, partially cut off, shows an error code, or is not a body-weight scale at all: set "legivel" to false, "peso_kg" to null, a low "confianca", and fill "motivo".
- NEVER guess a digit you cannot clearly see. When unsure, lower "confianca" — do not fabricate a number.
- If you can read the digits, report them even if the photo appears to be of a screen — but still set "possivel_foto_de_tela" accordingly.
- Do not include any field other than the five above.`;

// Mesmo padrão estrito de OCR — visor de aparelho de pressão, até três
// valores (sistólica/diastólica sempre presentes; pulso só se o aparelho
// mostrar).
const SYSTEM_PROMPT_PRESSAO = `You are a strict OCR engine that reads the digital display of a home blood pressure monitor from a single photograph. You do NOT diagnose, interpret, or give advice. You only read the numbers on the screen.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "legivel": boolean,
  "sistolica_mmhg": number | null,  // systolic (top/highest number, often labeled SYS); null if not legible
  "diastolica_mmhg": number | null, // diastolic (bottom/lower number, DIA); null if not legible
  "pulso_bpm": number | null,       // pulse rate, if shown (heart icon or PUL); null if not shown or not legible
  "confianca": number,              // 0.0 to 1.0, how sure you are of every digit
  "possivel_foto_de_tela": boolean, // true if this looks like a photo OF ANOTHER SCREEN (moiré, pixel grid, glare of a monitor)
  "motivo": string | null           // short reason when not legible; null when legible
}

Rules:
- If the display is blurry, reflective, partially cut off, shows an error code, or is not a blood pressure monitor at all: set "legivel" to false, all three numbers to null, a low "confianca", and fill "motivo".
- NEVER guess a digit you cannot clearly see. When unsure, lower "confianca" — do not fabricate a number. If only the pulse is unclear but systolic/diastolic are clearly readable, still report systolic/diastolic and leave "pulso_bpm" null.
- If you can read the numbers, report them even if the photo appears to be of a screen — but still set "possivel_foto_de_tela" accordingly.
- Do not include any field other than the six above.`;

// Diferente dos três acima: aqui o Gemini não está lendo UM valor de
// visor, está transcrevendo VÁRIOS números já IMPRESSOS num rótulo — ainda
// assim é OCR puro (A.2), nunca cálculo/estimativa, porque cada número já
// está escrito no rótulo.
const SYSTEM_PROMPT_ROTULO = `You are a strict OCR engine that transcribes the printed Nutrition Facts label ("Tabela Nutricional" / "Informação Nutricional") of a packaged food product from a single photograph. You are NOT estimating or calculating anything — every number here is already printed on the label; you only read it.

Respond with RAW JSON ONLY — no markdown, no code fences, no text before or after the object. The object has exactly these fields:
{
  "legivel": boolean,
  "porcao_descricao": string | null,    // the serving size exactly as printed, e.g. "30 g (2 colheres de sopa)"; null if not legible
  "calorias_kcal": number | null,       // calories per serving as printed; null if not present/legible
  "proteinas_g": number | null,
  "carboidratos_g": number | null,
  "gorduras_g": number | null,
  "ingredientes_principais": string[],  // up to 10 main ingredients from the ingredients list, in the order printed, exactly as written (Brazilian Portuguese)
  "confianca": number,                  // 0.0 to 1.0, how sure you are of every number transcribed
  "possivel_foto_de_tela": boolean,     // true if this looks like a photo OF ANOTHER SCREEN (moiré, pixel grid, glare of a monitor)
  "motivo": string | null               // short reason when not legible; null when legible
}

Rules:
- Transcribe ONLY numbers that are actually printed on the label — never calculate, estimate, or infer a value that isn't shown.
- If a specific field (e.g. gorduras_g) is not present on this particular label, leave it null — do not guess.
- If the label is blurry, reflective, partially cut off, or this is not a nutrition facts label at all: set "legivel" to false, all numeric fields to null, "ingredientes_principais" to an empty array, a low "confianca", and fill "motivo".
- "ingredientes_principais" is capped at 10 items — list the first ones as printed, do not summarize or paraphrase them.
- If you can read the label, report it even if the photo appears to be of a screen — but still set "possivel_foto_de_tela" accordingly.
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
// Tipos — balança (Passo 3)
// ─────────────────────────────────────────────────────────────────────────

export interface ExtracaoBalanca {
  legivel: boolean;
  pesoKg: number | null;
  confianca: number;
  possivelFotoDeTela: boolean;
  motivo: string | null;
}

export interface AvaliacaoBalanca {
  aceita: boolean;
  pesoKg?: number;
  confianca: number;
  possivelFotoDeTela: boolean;
  motivo?: string;
}

// ─────────────────────────────────────────────────────────────────────────
// Tipos — pressão arterial (Passo 3)
// ─────────────────────────────────────────────────────────────────────────

export interface ExtracaoPressao {
  legivel: boolean;
  sistolicaMmhg: number | null;
  diastolicaMmhg: number | null;
  pulsoBpm: number | null;
  confianca: number;
  possivelFotoDeTela: boolean;
  motivo: string | null;
}

export interface AvaliacaoPressao {
  aceita: boolean;
  sistolicaMmhg?: number;
  diastolicaMmhg?: number;
  /// Ausente quando o aparelho não mostrou pulso ou o Gemini não conseguiu
  /// lê-lo — diferente de sistólica/diastólica, pulso nunca derruba a
  /// leitura inteira (ver `avaliarLeituraPressao`).
  pulsoBpm?: number;
  confianca: number;
  possivelFotoDeTela: boolean;
  motivo?: string;
}

// ─────────────────────────────────────────────────────────────────────────
// Tipos — rótulo nutricional (Passo 3)
// ─────────────────────────────────────────────────────────────────────────

export interface ExtracaoRotulo {
  legivel: boolean;
  porcaoDescricao: string | null;
  caloriasKcal: number | null;
  proteinasG: number | null;
  carboidratosG: number | null;
  gordurasG: number | null;
  ingredientesPrincipais: string[];
  confianca: number;
  possivelFotoDeTela: boolean;
  motivo: string | null;
}

export interface AvaliacaoRotulo {
  aceita: boolean;
  porcaoDescricao?: string | null;
  caloriasKcal?: number | null;
  proteinasG?: number | null;
  carboidratosG?: number | null;
  gordurasG?: number | null;
  ingredientesPrincipais?: string[];
  confianca: number;
  possivelFotoDeTela: boolean;
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
  /// Categoria de consumo (ex: 'liquido_frio', 'unidade', 'peso_livre')
  /// Se nulo, alimento ainda sem categorização — fallback: input livre
  categoriaConsumo?: string;
  /// Unidade padrão: 'g' para sólidos, 'ml' para líquidos
  unidadeMedidaPadrao?: string;
  /// Rótulo amigável (ex: 'Copo Pequeno', 'Fatia', 'Unidade')
  medidaPadraoNome?: string;
  /// Quantidade numérica (5 para azeitona, 200 para xícara, etc.)
  medidaPadraoQtd?: number;
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
  /// Presente só quando o casamento NÃO veio de `encontrarAlimento`
  /// (exato/substring) — veio da busca semântica (`resolverComBuscaSemantica`)
  /// depois que o casamento léxico não achou nada. Ausente (undefined) no
  /// caminho normal para não sujar a resposta com um campo irrelevante na
  /// grande maioria dos itens.
  origemCasamento?: 'semantico';
  /// Similaridade de cosseno (0..1) que a RPC `match_alimentos` devolveu —
  /// só presente junto com `origemCasamento: 'semantico'`.
  similaridade?: number;
  /// Indica se a quantidade/gramas é estimativa (alimento sem medidas
  /// cadastradas) — quando true, UI deve mostrar ⚠️ e permitir edição.
  quantidadeEstimada?: boolean;
  /// Valor estimado em gramas ou ml (para mostrar na UI: "40g (típico)")
  /// Presente apenas quando quantidadeEstimada é true.
  pesoTipicoGramas?: number;
  /// RELATÓRIO 20260823_0004 — ACHADO CORRIGIDO (investigação 20260823_0003):
  /// estes 4 campos vêm de `AlimentoCatalogo` (lidos de `alimentos_referencia`
  /// desde a migration 20260802120000) mas até esta correção NUNCA eram
  /// copiados pra cá nem pra resposta HTTP — a UI condicional de
  /// líquido/quente/unidade/fatia em `ConfirmacaoPratoPage` (Flutter) nunca
  /// conseguia renderizar, porque `categoriaConsumo` chegava sempre `null`
  /// no cliente. Presentes sempre que o alimento casado tem essa
  /// categorização no catálogo (não só quando quantidadeEstimada) — o
  /// cliente decide sozinho quando usar (Flutter mantém a mesma regra de
  /// hoje: só exibe a UI especializada quando quantidadeEstimada é true;
  /// mudar ISSO é uma decisão de produto separada, fora do escopo deste
  /// fix).
  categoriaConsumo?: string;
  unidadeMedidaPadrao?: string;
  medidaPadraoNome?: string;
  medidaPadraoQtd?: number;
}

/// Item que o Gemini identificou mas que o backend NÃO conseguiu calcular —
/// alimento fora do catálogo (mesmo depois da busca semântica, ver
/// `resolverComBuscaSemantica`), ou medida caseira sem conversão cadastrada
/// para aquele alimento. Nunca é silenciosamente descartado: fica visível
/// para o usuário/telemetria decidir o que fazer (Passo 3 adiciona a busca
/// manual; aqui só registramos o motivo). Carrega `quantidade`/`confianca`
/// (não só nome/medida) porque `resolverComBuscaSemantica` precisa deles
/// para completar a regra de três se achar um casamento semântico depois.
export interface ItemPratoNaoReconhecido {
  nome: string;
  medida: string;
  quantidade: number;
  confianca: number;
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

/// Gera o embedding de um texto de busca — assinatura própria de
/// `search-food/index.ts` (mesmo par assimétrico RETRIEVAL_QUERY),
/// injetável para teste. Recebe só o nome do alimento buscado.
export type ChamadorEmbedding = (texto: string) => Promise<number[]>;

/// Um resultado bruto da RPC `match_alimentos` — só o suficiente para achar
/// a linha correspondente em `catalogo` (que já tem as medidas) e saber o
/// quão confiável foi o casamento.
export interface MatchSemantico {
  id: string;
  similarity: number;
}

/// Consulta a RPC `match_alimentos` — injetável para teste (lista fixa em
/// memória, sem tocar o banco), mesma filosofia de `CatalogoAlimentosLike`.
export interface BuscaSemanticaLike {
  buscar(embedding: number[]): Promise<MatchSemantico[]>;
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
/// `base64`/`mimeType` opcionais desde o RELATÓRIO 20260824_0003 (registro
/// de refeição por texto/áudio, Documento Mestre — 4 métodos de captura):
/// entrada de TEXTO livre não tem dado binário nenhum pra mandar como
/// `inlineData`, só o prompt — os dois chamadores reais (foto, áudio)
/// continuam passando os dois normalmente, sem mudança de comportamento.
export type ChamadorGemini = (params: {
  base64?: string;
  mimeType?: string;
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
  chamarEmbedding?: ChamadorEmbedding;
  buscaSemantica?: BuscaSemanticaLike;
}

// Exportada para os testes de `criarChamadorGeminiReal`/
// `criarChamadorGeminiComFallback` conferirem `.status` diretamente
// (RELATÓRIO 20260824_0002).
export class ErroHttp extends Error {
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
// Parsing e decisão — balança (Passo 3, puros — sem I/O, 100% testáveis)
// ─────────────────────────────────────────────────────────────────────────

/// Mesmo tratamento robusto de A.5 de `parseRespostaGemini` — deliberadamente
/// uma função própria, não compartilhada com o glicosímetro (mesmo padrão já
/// estabelecido entre glicosímetro e prato: extratores parecidos, mas cada
/// um com seu parser/validador independente, para nunca acoplar a evolução
/// de um ao outro).
export function parseRespostaGeminiBalanca(textoCru: string): ExtracaoBalanca {
  const ilegivel = (motivo: string): ExtracaoBalanca => ({
    legivel: false,
    pesoKg: null,
    confianca: 0,
    possivelFotoDeTela: false,
    motivo,
  });

  const bruto = extrairObjetoJson(textoCru);
  if (!bruto) return ilegivel('json_invalido');

  const valor = bruto['peso_kg'];
  return {
    legivel: bruto['legivel'] === true,
    pesoKg: typeof valor === 'number' && Number.isFinite(valor) ? valor : null,
    confianca: normalizarConfianca(bruto['confianca']),
    possivelFotoDeTela: bruto['possivel_foto_de_tela'] === true,
    motivo: typeof bruto['motivo'] === 'string' ? bruto['motivo'] : null,
  };
}

export function avaliarLeituraBalanca(extracao: ExtracaoBalanca): AvaliacaoBalanca {
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
  if (extracao.pesoKg === null) {
    return { aceita: false, motivo: 'sem_numero', ...base };
  }
  if (extracao.pesoKg < PESO_MIN_KG || extracao.pesoKg > PESO_MAX_KG) {
    return { aceita: false, motivo: 'fora_da_faixa', ...base };
  }
  return { aceita: true, pesoKg: arredondar(extracao.pesoKg, 1), ...base };
}

// ─────────────────────────────────────────────────────────────────────────
// Parsing e decisão — pressão arterial (Passo 3, puros — sem I/O)
// ─────────────────────────────────────────────────────────────────────────

export function parseRespostaGeminiPressao(textoCru: string): ExtracaoPressao {
  const ilegivel = (motivo: string): ExtracaoPressao => ({
    legivel: false,
    sistolicaMmhg: null,
    diastolicaMmhg: null,
    pulsoBpm: null,
    confianca: 0,
    possivelFotoDeTela: false,
    motivo,
  });

  const bruto = extrairObjetoJson(textoCru);
  if (!bruto) return ilegivel('json_invalido');

  const numOrNull = (valor: unknown): number | null =>
    typeof valor === 'number' && Number.isFinite(valor) ? valor : null;

  return {
    legivel: bruto['legivel'] === true,
    sistolicaMmhg: numOrNull(bruto['sistolica_mmhg']),
    diastolicaMmhg: numOrNull(bruto['diastolica_mmhg']),
    pulsoBpm: numOrNull(bruto['pulso_bpm']),
    confianca: normalizarConfianca(bruto['confianca']),
    possivelFotoDeTela: bruto['possivel_foto_de_tela'] === true,
    motivo: typeof bruto['motivo'] === 'string' ? bruto['motivo'] : null,
  };
}

/// Sistólica/diastólica são obrigatórias para aceitar a leitura — pulso é
/// só um extra: se o aparelho não mostrou ou o Gemini não conseguiu ler,
/// isso NÃO derruba uma leitura de pressão por outro lado boa (mesmo
/// espírito de A.6 — não descartar dado bom por causa de um campo
/// secundário ausente).
export function avaliarLeituraPressao(extracao: ExtracaoPressao): AvaliacaoPressao {
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
  if (extracao.sistolicaMmhg === null || extracao.diastolicaMmhg === null) {
    return { aceita: false, motivo: 'sem_numero', ...base };
  }
  if (
    extracao.sistolicaMmhg < SISTOLICA_MIN_MMHG ||
    extracao.sistolicaMmhg > SISTOLICA_MAX_MMHG ||
    extracao.diastolicaMmhg < DIASTOLICA_MIN_MMHG ||
    extracao.diastolicaMmhg > DIASTOLICA_MAX_MMHG
  ) {
    return { aceita: false, motivo: 'fora_da_faixa', ...base };
  }
  // Checagem de consistência fisiológica — sistólica sempre maior que
  // diastólica; se vier invertido, é erro de leitura, não um paciente real.
  if (extracao.sistolicaMmhg <= extracao.diastolicaMmhg) {
    return { aceita: false, motivo: 'inconsistente', ...base };
  }

  const pulsoValido =
    extracao.pulsoBpm !== null &&
    extracao.pulsoBpm >= PULSO_MIN_BPM &&
    extracao.pulsoBpm <= PULSO_MAX_BPM
      ? Math.round(extracao.pulsoBpm)
      : undefined;

  return {
    aceita: true,
    sistolicaMmhg: Math.round(extracao.sistolicaMmhg),
    diastolicaMmhg: Math.round(extracao.diastolicaMmhg),
    pulsoBpm: pulsoValido,
    ...base,
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Parsing e decisão — rótulo nutricional (Passo 3, puros — sem I/O)
// ─────────────────────────────────────────────────────────────────────────

/// Diferente dos três extratores acima (um valor ou punhado de valores de
/// visor), rótulo tem vários campos opcionais — uma etiqueta pode não
/// imprimir todos. `ingredientesPrincipais` é sempre saneado para no máximo
/// `MAX_INGREDIENTES_ROTULO`, defesa em profundidade mesmo o prompt já
/// pedindo o teto (mesmo padrão de `MAX_ITENS_PRATO`).
export function parseRespostaGeminiRotulo(textoCru: string): ExtracaoRotulo {
  const ilegivel = (motivo: string): ExtracaoRotulo => ({
    legivel: false,
    porcaoDescricao: null,
    caloriasKcal: null,
    proteinasG: null,
    carboidratosG: null,
    gordurasG: null,
    ingredientesPrincipais: [],
    confianca: 0,
    possivelFotoDeTela: false,
    motivo,
  });

  const bruto = extrairObjetoJson(textoCru);
  if (!bruto) return ilegivel('json_invalido');

  const numOrNull = (valor: unknown): number | null =>
    typeof valor === 'number' && Number.isFinite(valor) ? valor : null;

  const ingredientesBrutos = Array.isArray(bruto['ingredientes_principais'])
    ? bruto['ingredientes_principais']
    : [];
  const ingredientesPrincipais = ingredientesBrutos
    .filter((item): item is string => typeof item === 'string' && item.trim().length > 0)
    .map((item) => item.trim())
    .slice(0, MAX_INGREDIENTES_ROTULO);

  return {
    legivel: bruto['legivel'] === true,
    porcaoDescricao: typeof bruto['porcao_descricao'] === 'string' ? bruto['porcao_descricao'] : null,
    caloriasKcal: numOrNull(bruto['calorias_kcal']),
    proteinasG: numOrNull(bruto['proteinas_g']),
    carboidratosG: numOrNull(bruto['carboidratos_g']),
    gordurasG: numOrNull(bruto['gorduras_g']),
    ingredientesPrincipais,
    confianca: normalizarConfianca(bruto['confianca']),
    possivelFotoDeTela: bruto['possivel_foto_de_tela'] === true,
    motivo: typeof bruto['motivo'] === 'string' ? bruto['motivo'] : null,
  };
}

/// Aceita se legível/confiante o bastante E pelo menos um valor nutricional
/// veio — um rótulo real sempre tem ao menos calorias; zero campo numérico
/// nenhum é sinal de que a extração não achou nada de verdade, mesmo que o
/// Gemini tenha marcado `legivel: true`.
export function avaliarLeituraRotulo(extracao: ExtracaoRotulo): AvaliacaoRotulo {
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

  const temAlgumMacro =
    extracao.caloriasKcal !== null ||
    extracao.proteinasG !== null ||
    extracao.carboidratosG !== null ||
    extracao.gordurasG !== null;
  if (!temAlgumMacro) {
    return { aceita: false, motivo: 'sem_numero', ...base };
  }

  if (
    extracao.caloriasKcal !== null &&
    (extracao.caloriasKcal < 0 || extracao.caloriasKcal > CALORIAS_MAX_ROTULO_KCAL)
  ) {
    return { aceita: false, motivo: 'fora_da_faixa', ...base };
  }

  return {
    aceita: true,
    porcaoDescricao: extracao.porcaoDescricao,
    caloriasKcal: extracao.caloriasKcal !== null ? arredondar(extracao.caloriasKcal, 0) : null,
    proteinasG: extracao.proteinasG !== null ? arredondar(extracao.proteinasG, 1) : null,
    carboidratosG: extracao.carboidratosG !== null ? arredondar(extracao.carboidratosG, 1) : null,
    gordurasG: extracao.gordurasG !== null ? arredondar(extracao.gordurasG, 1) : null,
    ingredientesPrincipais: extracao.ingredientesPrincipais,
    ...base,
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Parsing e cálculo — prato de comida (Passo 2, puros — sem I/O, 100% testáveis)
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

    // RELATÓRIO 20260831_0001 — teto de sanidade diferente pra unidade
    // bruta (peso/volume SI, ver `FATORES_UNIDADE_BRUTA`): 20 é certo pra
    // CONTAGEM de medida caseira ("20 colheres de sopa"), mas errado pra
    // grama/mililitro — aplicar o mesmo teto capava "300 gramas" pra "20
    // gramas" silenciosamente, o próprio bug de escala relatado.
    const medidaEhUnidadeBruta = FATORES_UNIDADE_BRUTA[normalizarMedida(medida)] !== undefined;
    const tetoQuantidade = medidaEhUnidadeBruta
      ? QUANTIDADE_MAXIMA_UNIDADE_BRUTA_GRAMAS_OU_ML
      : QUANTIDADE_MAXIMA_ITEM_PRATO;

    const quantidadeBruta = item['quantidade'];
    const quantidade =
      typeof quantidadeBruta === 'number' &&
      Number.isFinite(quantidadeBruta) &&
      quantidadeBruta > 0
        ? Math.min(quantidadeBruta, tetoQuantidade)
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

/// Normaliza\u00e7\u00e3o extra para medidas: remove plurais e varia\u00e7\u00f5es comuns
/// (ex: "colher de sopa" = "colheres de sopa"; "peda\u00e7o" = "pedaco").
function normalizarMedida(medida: string): string {
  let norm = normalizarTexto(medida);
  norm = norm.replace(/s$/, ''); // plurais: -s
  norm = norm.replace(/oes$/, 'ao'); // -\u00f5es -> -\u00e3o
  return norm;
}

// \u26a0\ufe0f REMOVIDO: ehAlimentoLiquido() e estimarTamanhoRecipiente()
// Essas fun\u00e7\u00f5es dependiam de ALIMENTOS_LIQUIDOS e TAMANHO_COPOS_ML (hardcoded).
// Agora a categoria vem do DB (AlimentoCatalogo.categoriaConsumo).
// Ver encontrarMedida() abaixo \u2014 usa categoria do DB em vez de pattern matching.

/// Casa o nome livre do Gemini contra `alimentos_referencia`:
/// 1. Exato: nome_taco === busca OU alias === busca
/// 2. Começa com: nome_taco.startsWith(busca) OU alias.startsWith(busca)
/// 3. Substring: nome_taco.includes(busca) nos dois sentidos (último recurso)
/// Nunca "quase-casa" por similaridade fonética — um alimento não encontrado
/// vira `alimento_nao_encontrado`, nunca um chute (Missão F45).
export function encontrarAlimento(
  catalogo: AlimentoCatalogo[],
  nomeBuscado: string,
): AlimentoCatalogo | null {
  const alvo = normalizarTexto(nomeBuscado);
  if (!alvo) return null;

  // 1. Match exato (nome_taco ou alias)
  const exato = catalogo.find(
    (a) =>
      normalizarTexto(a.nomeTaco) === alvo ||
      a.aliases.some((alias) => normalizarTexto(alias) === alvo),
  );
  if (exato) return exato;

  // 2. Match "começa com" (mais específico que substring genérico)
  const comecaCom = catalogo.find(
    (a) =>
      normalizarTexto(a.nomeTaco).startsWith(alvo) ||
      a.aliases.some((alias) => normalizarTexto(alias).startsWith(alvo)),
  );
  if (comecaCom) return comecaCom;

  // 3. Match substring genérico (fallback menos preferido)
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
/// nunca uma tabela de conversão global) — EXCETO unidades brutas (acima),
/// que são universais e nunca passam por essa tabela.
///
/// FIX (31/jul): Adiciona normalização flexível (remove plurais, variações)
/// e fallback para primeira medida se nenhuma corresponder — melhor usar algo
/// que deixar o alimento cair em "não reconhecido".
export function encontrarMedida(
  alimento: AlimentoCatalogo,
  medidaBuscada: string,
): MedidaCaseiraCatalogo | null {
  const alvo = normalizarMedida(medidaBuscada);
  if (!alvo) {
    // Sem medida buscada: return null (caller decide o fallback)
    return null;
  }

  // RELATÓRIO 20260831_0001 — CAUSA RAIZ do "cálculo ~3x maior que o
  // esperado" no registro descritivo: "300 gramas de X" chega aqui como
  // medida="gramas"/quantidade=300, e nenhum alimento do catálogo tem uma
  // medida caseira literalmente chamada "grama" cadastrada — então isto
  // SEMPRE caía num dos fallbacks abaixo (primeira medida disponível ou
  // peso genérico), que multiplicam um peso-por-unidade ERRADO (de uma
  // medida caseira qualquer) pela quantidade 300, inflando o resultado por
  // um fator arbitrário (não um "3x" fixo — depende de qual medida o
  // alimento tem cadastrada; medido nesta investigação como 25x-120x em
  // casos reais, sempre errado). Checado ANTES de qualquer match por nome
  // — "grama" nunca deveria, por acidente, casar como substring de uma
  // medida caseira registrada.
  const fatorBruto = FATORES_UNIDADE_BRUTA[alvo];
  if (fatorBruto !== undefined) {
    console.log(
      `[encontrarMedida] Unidade bruta: "${medidaBuscada}" -> ${fatorBruto}g/unidade (sem tabela de medida caseira, universal)`,
    );
    return { medida: medidaBuscada, gramas: fatorBruto };
  }

  // Otimização: pré-computar normalização uma vez, não para cada comparação
  const medidasNormalizadas = alimento.medidas.map((m) => ({
    original: m,
    normalizado: normalizarMedida(m.medida),
  }));

  // 1. Match exato (após normalização)
  const exata = medidasNormalizadas.find((m) => m.normalizado === alvo);
  if (exata) {
    console.log(`[encontrarMedida] Match exato: "${medidaBuscada}" -> "${exata.original.medida}"`);
    return exata.original;
  }

  // 2. Match substring
  const substring = medidasNormalizadas.find(
    (m) =>
      m.normalizado.includes(alvo) ||
      alvo.includes(m.normalizado),
  );
  if (substring) {
    console.log(
      `[encontrarMedida] Match substring: "${medidaBuscada}" -> "${substring.original.medida}"`,
    );
    return substring.original;
  }

  // 3. Fallback: usar primeira medida disponível (F46 fallback degradado)
  if (alimento.medidas.length > 0) {
    const fallback = alimento.medidas[0];
    console.log(
      `[encontrarMedida] Fallback (medida não encontrada): "${medidaBuscada}" -> "${fallback.medida}" (primeira disponível)`,
    );
    return fallback;
  }

  // 4. Fallback final: usar categoria e peso padrão do alimento (agora vem do DB)
  // se nenhuma medida caseira está cadastrada.
  //
  // Se categoria_consumo é nulo → alimento ainda pendente de categorização.
  // Fallback seguro: assumir 100g (peso_livre). UI mostrará campo livre para edição.
  if (!alimento.categoriaConsumo || !alimento.medidaPadraoQtd) {
    console.log(
      `[encontrarMedida] Fallback genérico (categoria nula): "${medidaBuscada}" -> "100g (est.)" para "${alimento.nomeTaco}"`,
    );
    return { medida: '100g (est.)', gramas: 100 };
  }

  // Categoria conhecida — usar peso/volume padrão da categoria
  const qtdPadrao = alimento.medidaPadraoQtd;
  const unidade = alimento.unidadeMedidaPadrao || 'g';

  console.log(
    `[encontrarMedida] Fallback categorizado: "${medidaBuscada}" -> "${qtdPadrao}${unidade} (${alimento.categoriaConsumo})" para "${alimento.nomeTaco}"`,
  );
  return { medida: `${qtdPadrao}${unidade} (est.)`, gramas: qtdPadrao };
}

function arredondar(valor: number, casas: number): number {
  const fator = 10 ** casas;
  return Math.round(valor * fator) / fator;
}

/// A regra de três em si — `gramas = medida.gramas * quantidade`, depois
/// `macro = (macro_por_100g / 100) * gramas` — extraída para ser reusada
/// tanto por `calcularPrato` (casamento léxico) quanto por
/// `resolverComBuscaSemantica` (casamento semântico): o CÁLCULO é sempre o
/// mesmo determinístico, só muda COMO o `alimento` foi encontrado.
function calcularItem(params: {
  alimento: AlimentoCatalogo;
  medida: MedidaCaseiraCatalogo;
  nomeIdentificado: string;
  medidaTexto: string;
  quantidade: number;
  confianca: number;
  origemCasamento?: 'semantico';
  similaridade?: number;
  quantidadeEstimada?: boolean;
}): ItemPratoCalculado {
  const gramas = params.medida.gramas * params.quantidade;
  return {
    nomeIdentificado: params.nomeIdentificado,
    alimentoCasado: params.alimento.nomeTaco,
    medida: params.medidaTexto,
    quantidade: params.quantidade,
    gramasEstimados: arredondar(gramas, 0),
    calorias: arredondar((params.alimento.caloriasKcal100g / 100) * gramas, 0),
    proteinasG: arredondar((params.alimento.proteinasG100g / 100) * gramas, 1),
    carboidratosG: arredondar((params.alimento.carboidratosG100g / 100) * gramas, 1),
    gordurasG: arredondar((params.alimento.gordurasG100g / 100) * gramas, 1),
    confianca: params.confianca,
    ...(params.origemCasamento ? { origemCasamento: params.origemCasamento } : {}),
    ...(params.similaridade !== undefined ? { similaridade: params.similaridade } : {}),
    ...(params.quantidadeEstimada ? {
      quantidadeEstimada: params.quantidadeEstimada,
      pesoTipicoGramas: params.medida.gramas,
    } : {}),
    // RELATÓRIO 20260823_0004 — fix do achado 20260823_0003: propaga a
    // categorização do alimento (lida do catálogo, `AlimentoCatalogo`) até
    // aqui, que antes deste fix nunca acontecia — ver doc de
    // `ItemPratoCalculado.categoriaConsumo`.
    ...(params.alimento.categoriaConsumo ? { categoriaConsumo: params.alimento.categoriaConsumo } : {}),
    ...(params.alimento.unidadeMedidaPadrao ? { unidadeMedidaPadrao: params.alimento.unidadeMedidaPadrao } : {}),
    ...(params.alimento.medidaPadraoNome ? { medidaPadraoNome: params.alimento.medidaPadraoNome } : {}),
    ...(params.alimento.medidaPadraoQtd !== undefined ? { medidaPadraoQtd: params.alimento.medidaPadraoQtd } : {}),
  };
}

function somarTotais(itens: ItemPratoCalculado[]): CalculoPrato['totais'] {
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
    calorias: arredondar(somaBruta.calorias, 0),
    proteinasG: arredondar(somaBruta.proteinasG, 1),
    carboidratosG: arredondar(somaBruta.carboidratosG, 1),
    gordurasG: arredondar(somaBruta.gordurasG, 1),
  };
}

/// O CÁLCULO — a única função deste arquivo que produz um número
/// nutricional, e o único lugar do sistema que faz essa conta (A.2: "o
/// Gemini NÃO calcula, apenas identifica"). Só tenta o casamento léxico
/// (`encontrarAlimento`, exato/substring) — quem chama (`processarPratoRefeicao`)
/// decide se vale a pena tentar a busca semântica depois para o que sobrar
/// em `itensNaoReconhecidos`, porque essa segunda tentativa precisa de I/O
/// (Gemini + banco) que esta função, deliberadamente pura, não faz.
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
        quantidade: item.quantidade,
        confianca: item.confianca,
        motivo: 'alimento_nao_encontrado',
      });
      continue;
    }

    const medida = encontrarMedida(alimento, item.medida);
    if (!medida) {
      itensNaoReconhecidos.push({
        nome: item.nome,
        medida: item.medida,
        quantidade: item.quantidade,
        confianca: item.confianca,
        motivo: 'medida_nao_encontrada',
      });
      continue;
    }

    // Detectar se é medida estimada (contém "est." no nome — adicionado pelo fallback)
    const quantidadeEstimada = medida.medida.includes('est.');

    itens.push(
      calcularItem({
        alimento,
        medida,
        nomeIdentificado: item.nome,
        medidaTexto: item.medida,
        quantidade: item.quantidade,
        confianca: item.confianca,
        quantidadeEstimada,
      }),
    );
  }

  return { itens, itensNaoReconhecidos, totais: somarTotais(itens) };
}

/// Segunda tentativa, só para os itens que `calcularPrato` não conseguiu
/// casar por igualdade/substring (`motivo === 'alimento_nao_encontrado'` —
/// `medida_nao_encontrada` já achou o alimento exato, busca semântica não
/// ajudaria nesse caso). Para cada um: gera o embedding do nome buscado
/// (mesmo par assimétrico RETRIEVAL_QUERY/normalização L2 de
/// `search-food/index.ts`, para casar com o RETRIEVAL_DOCUMENT que
/// `scripts/seed_food_embeddings.ts` usou para gerar o embedding do
/// catálogo), consulta `match_alimentos`, e se achar uma linha, resolve a
/// medida contra ESSE alimento — usando o `catalogo` completo já carregado
/// em memória (a RPC devolve só id/nome/macros, não as medidas) — e calcula
/// pela MESMA regra de três de `calcularPrato` (`calcularItem`). Roda em
/// paralelo (`Promise.all`): um item não espera o outro.
export async function resolverComBuscaSemantica(
  itensNaoReconhecidos: ItemPratoNaoReconhecido[],
  catalogo: AlimentoCatalogo[],
  chamarEmbedding: ChamadorEmbedding,
  buscaSemantica: BuscaSemanticaLike,
): Promise<{ resolvidos: ItemPratoCalculado[]; aindaNaoReconhecidos: ItemPratoNaoReconhecido[] }> {
  const candidatos = itensNaoReconhecidos.filter((i) => i.motivo === 'alimento_nao_encontrado');
  const semCandidato = itensNaoReconhecidos.filter((i) => i.motivo !== 'alimento_nao_encontrado');

  // Otimização: criar Map para O(1) lookup por ID em vez de O(n) busca linear
  const alimentoPorId = new Map(catalogo.map((a) => [a.id, a]));

  const resultados = await Promise.all(
    candidatos.map(
      async (item): Promise<{ resolvido: ItemPratoCalculado | null; naoReconhecido: ItemPratoNaoReconhecido | null }> => {
        console.log(`[resolverComBuscaSemantica] Buscando: "${item.nome}" (medida: "${item.medida}")`);

        const embedding = await chamarEmbedding(item.nome);
        const matches = await buscaSemantica.buscar(embedding);
        const melhor = matches[0];

        if (!melhor) {
          console.log(`[resolverComBuscaSemantica] Sem match semântico para "${item.nome}"`);
          return { resolvido: null, naoReconhecido: item };
        }

        console.log(
          `[resolverComBuscaSemantica] Match encontrado: "${item.nome}" -> ID: ${melhor.id}, Similaridade: ${melhor.similarity.toFixed(3)}`,
        );

        // Defensivo: a RPC só enxerga o que está em `alimentos_referencia`
        // Uso Map para O(1) lookup em vez de O(n) busca linear no catálogo
        const alimento = alimentoPorId.get(melhor.id);
        if (!alimento) {
          console.log(`[resolverComBuscaSemantica] ERRO: ID ${melhor.id} não encontrado no catálogo`);
          return { resolvido: null, naoReconhecido: item };
        }

        console.log(`[resolverComBuscaSemantica] Alimento resolvido: "${alimento.nomeTaco}"`);

        const medida = encontrarMedida(alimento, item.medida);
        // `encontrarMedida` só retorna null quando `item.medida` vier vazia
        // (Gemini sempre reporta algum texto de medida, então isto é
        // inalcançável na prática) — guarda aqui só pra bater com a
        // assinatura real da função (achado ao rodar `deno check` de
        // verdade nesta tarefa, RELATÓRIO 20260823_0004): sem isto o
        // TypeScript recusa compilar `medida.medida` duas linhas abaixo,
        // já que o tipo de retorno é `MedidaCaseiraCatalogo | null`.
        if (!medida) {
          console.log(`[resolverComBuscaSemantica] Sem medida buscável para "${item.nome}" (medida vazia)`);
          return { resolvido: null, naoReconhecido: item };
        }

        // Detectar se é medida estimada (contém "est." no nome)
        const quantidadeEstimada = medida.medida.includes('est.');
        if (quantidadeEstimada) {
          console.log(
            `[resolverComBuscaSemantica] Medida estimada: "${item.medida}" -> "${medida.medida}" para "${alimento.nomeTaco}"`,
          );
        }

        return {
          resolvido: calcularItem({
            alimento,
            medida,
            nomeIdentificado: item.nome,
            medidaTexto: item.medida,
            quantidade: item.quantidade,
            confianca: item.confianca,
            origemCasamento: 'semantico',
            similaridade: arredondar(melhor.similarity, 3),
            quantidadeEstimada,
          }),
          naoReconhecido: null,
        };
      },
    ),
  );

  const resolvidos = resultados
    .map((r) => r.resolvido)
    .filter((r): r is ItemPratoCalculado => r !== null);
  const aindaNaoReconhecidos = [
    ...semCandidato,
    ...resultados.map((r) => r.naoReconhecido).filter((r): r is ItemPratoNaoReconhecido => r !== null),
  ];

  return { resolvidos, aindaNaoReconhecidos };
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

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// RELATÓRIO 20260824_0002 — CORREÇÃO DA CORREÇÃO. O RELATÓRIO 20260824_0001
// diagnosticou errado: viu um 503 "high demand" (instabilidade transitória)
// durante a curadoria em massa da véspera e concluiu que retry/backoff
// resolveria "Falha ao analisar a imagem" em produção. O fundador testou de
// novo e reportou o padrão real: a 1ª foto do dia funciona, as seguintes
// falham, e o tempo até falhar ficou MAIOR (não menor) — sintoma clássico
// de retry inútil, não de instabilidade transitória. Investigação desta
// tarefa (chamada real ao Gemini com a chave do projeto) confirma: o erro
// de produção é HTTP 429 `RESOURCE_EXHAUSTED`, quota
// `GenerateRequestsPerDayPerProjectPerModel-FreeTier`, **limite de 20
// requisições por DIA** para o modelo CORE (`gemini-flash-latest`, que
// hoje resolve para `gemini-3.7-flash` — um modelo bem mais novo/restrito
// do que quando o alias foi escolhido). Retentar em 1.5s/3s NUNCA ajuda
// uma cota DIÁRIA — só desperdiça o pouco que sobrar dela e faz o usuário
// esperar mais pra ver a mesma falha (exatamente o "tempo maior" relatado).
//
// Duas correções reais, não uma terceira tentativa de retry:
//   1. 429 nunca é retentado no MESMO modelo (`ErroCotaGemini`, abaixo) —
//      só 5xx (instabilidade de verdade, como o 503 de ontem) continua
//      retentando com backoff curto.
//   2. `criarChamadorGeminiComFallback` — quando o modelo CORE esgota a
//      cota, cai automaticamente pro modelo LITE (confirmado com quota
//      disponível nesta investigação) em vez de falhar pro usuário. Ver
//      uso em `deps.chamarGemini` no handler.
const MAX_TENTATIVAS_VISAO = 3;

/// Sinaliza pro caller (fallback de modelo) que a falha foi por COTA
/// (429/RESOURCE_EXHAUSTED) — nunca por instabilidade transitória. A
/// distinção importa: cota (geralmente "PerDay" no plano gratuito) não se
/// resolve esperando alguns segundos, só trocando de modelo/tier.
class ErroCotaGemini extends ErroHttp {
  constructor(mensagem: string) {
    super(429, mensagem);
  }
}

// Exportada só para o teste de regressão do bug de 22/jul (modelo no
// endpoint + no texto do erro) — que stuba `fetch` global. Nenhum outro
// chamador deveria usar isto fora do próprio handler (que usa
// `criarChamadorGeminiComFallback`, abaixo).
/// RELATÓRIO 20260825_0003 — `maxTentativas`/`backoffBaseMs` configuráveis
/// por chamada (default = comportamento de sempre, `MAX_TENTATIVAS_VISAO`/
/// 1500ms — nenhum chamador existente quebra). `criarChamadorGeminiComFallback`
/// usa isto pra dar orçamento de retry DIFERENTE ao modelo primário (que
/// pode ter fallback pra cair) e ao modelo final (sem mais ninguém pra
/// tentar depois).
interface OpcoesRetryGemini {
  maxTentativas?: number;
  backoffBaseMs?: number;
}

export function criarChamadorGeminiReal(
  apiKey: string,
  modelo: string,
  opcoes: OpcoesRetryGemini = {},
): ChamadorGemini {
  const maxTentativas = opcoes.maxTentativas ?? MAX_TENTATIVAS_VISAO;
  const backoffBaseMs = opcoes.backoffBaseMs ?? 1_500;

  return async ({ base64, mimeType, systemPrompt, userText }) => {
    const url = `${GEMINI_ENDPOINT_BASE}/${modelo}:generateContent?key=${apiKey}`;
    const corpo = {
      systemInstruction: {
        parts: [{ text: systemPrompt }],
      },
      contents: [
        {
          role: 'user',
          // `inlineData` só entra quando há dado binário (foto/áudio) — modo
          // texto (RELATÓRIO 20260824_0003) manda só o prompt.
          parts: [
            ...(base64 && mimeType ? [{ inlineData: { mimeType, data: base64 } }] : []),
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

    let ultimoErro: ErroHttp | null = null;
    for (let tentativa = 1; tentativa <= maxTentativas; tentativa++) {
      const resposta = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(corpo),
      });

      if (resposta.ok) {
        const json = (await resposta.json()) as {
          candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
        };
        const texto = json.candidates?.[0]?.content?.parts?.[0]?.text;
        if (typeof texto !== 'string' || texto.length === 0) {
          // Sem texto = tratamos como ilegível/vazio nos parsers acima.
          return '{}';
        }
        return texto;
      }

      const detalhe = await resposta.text().catch(() => '');
      // Inclui o nome do modelo na mensagem: um 404 aqui quase sempre
      // significa "esse nome de modelo não existe mais para esta chave",
      // não um erro de rede — o log já diz de cara qual modelo falhou, sem
      // precisar ler o corpo da resposta pra descobrir.

      // 429 = cota (quase sempre diária no free tier) — nunca retentável
      // no mesmo modelo. Falha IMEDIATA pro caller decidir (fallback de
      // modelo), sem gastar o orçamento de retry à toa.
      if (resposta.status === 429) {
        throw new ErroCotaGemini(
          `Gemini (modelo "${modelo}") respondeu 429 (cota esgotada): ${detalhe.slice(0, 300)}`,
        );
      }

      ultimoErro = new ErroHttp(
        502,
        `Gemini (modelo "${modelo}") respondeu ${resposta.status}: ${detalhe.slice(0, 300)}`,
      );

      // Só 5xx é retentável agora (instabilidade transitória real, como o
      // 503 "high demand" observado na curadoria de 23/ago) — 429 já
      // lançou acima, outros 4xx (404 de modelo errado etc.) são bug de
      // config, retry não resolve.
      const retentavel = resposta.status >= 500;
      if (!retentavel || tentativa === maxTentativas) {
        throw ultimoErro;
      }
      const backoffMs = backoffBaseMs * tentativa;
      console.warn(
        `criarChamadorGeminiReal: HTTP ${resposta.status} (tentativa ${tentativa}/${maxTentativas}) — retentando em ${backoffMs}ms...`,
      );
      await delay(backoffMs);
    }
    // Inalcançável (o for sempre retorna ou lança), só pra satisfazer o TypeScript.
    throw ultimoErro ?? new ErroHttp(502, 'Gemini generateContent falhou sem detalhe.');
  };
}

/// Encadeia um modelo PRIMÁRIO com um modelo de FALLBACK. `modeloFallback:
/// null` (tipos já no nível LITE, o mais barato) significa "sem degradação
/// possível" — comporta-se como `criarChamadorGeminiReal` puro, com o
/// orçamento de retry inteiro (`MAX_TENTATIVAS_VISAO`) pro único modelo que
/// existe.
///
/// RELATÓRIO 20260825_0003 — achado real em device (fundador testando o
/// Registro de Refeição por foto): `TimeoutException` mesmo com o cliente
/// já dando 45s de folga (RELATÓRIO 20260824_0001) e o servidor já
/// retentando 5xx (RELATÓRIO 20260824_0001) — a raiz mais funda: o
/// fallback de modelo (20260824_0002) só disparava em COTA (429), nunca em
/// "5xx esgotado depois de retentar" — o modelo CORE (mais lento por
/// natureza, é o único com raciocínio de cena visual) podia bater as 3
/// tentativas inteiras contra o MESMO modelo sobrecarregado antes de
/// desistir, e cada tentativa é uma chamada de visão inteira
/// (potencialmente vários segundos) — 3 delas em sequência, mais o
/// backoff entre elas, facilmente estoura qualquer timeout de cliente
/// razoável. Pior: no free tier o CORE tem só 20 requisições/DIA
/// (20260824_0002) — bater 3x nele por UMA foto do usuário queima 3x mais
/// cota do que precisa.
///
/// Duas mudanças, mesmo espírito de "degradação graciosa" já usado pra
/// busca semântica (`resolverComBuscaSemantica`):
///   1. Quando existe fallback configurado, o primário ganha só 1
///      tentativa (nunca retenta contra si mesmo) — qualquer falha dele
///      (cota, 5xx, 4xx de config) já pula pro fallback na hora, mais
///      rápido E gastando menos cota do modelo restrito. O orçamento de
///      retry pesado (`MAX_TENTATIVAS_VISAO`) fica pro modelo que SOBROU —
///      o fallback, sem mais ninguém pra tentar depois dele.
///   2. Backoff reduzido pra 1s/2s (era 1.5s/3s) nas duas pernas — chamada
///      síncrona de usuário esperando na tela, não o script de curadoria
///      em lote que originalmente justificou 1.5s/3s.
export function criarChamadorGeminiComFallback(
  apiKey: string,
  modeloPrimario: string,
  modeloFallback: string | null,
): ChamadorGemini {
  const temFallback = modeloFallback !== null && modeloFallback !== modeloPrimario;
  const chamarPrimario = criarChamadorGeminiReal(apiKey, modeloPrimario, {
    maxTentativas: temFallback ? 1 : MAX_TENTATIVAS_VISAO,
    backoffBaseMs: 1_000,
  });

  return async (params) => {
    try {
      return await chamarPrimario(params);
    } catch (erro) {
      if (!(erro instanceof ErroHttp) || !temFallback) {
        throw erro;
      }
      const motivo = erro instanceof ErroCotaGemini ? 'cota esgotada' : `falha (HTTP ${erro.status})`;
      console.warn(
        `criarChamadorGeminiComFallback: ${motivo} em "${modeloPrimario}" — tentando fallback "${modeloFallback}"...`,
      );
      const chamarFallback = criarChamadorGeminiReal(apiKey, modeloFallback!, { backoffBaseMs: 1_000 });
      return await chamarFallback(params);
    }
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Busca semântica — embedding do termo + RPC match_alimentos (fallback do
// Passo 2, só quando o casamento léxico não acha nada)
// ─────────────────────────────────────────────────────────────────────────

/// Reescala para norma L2 = 1 — mesma correção de `seed_food_embeddings.ts`/
/// `search-food/index.ts`: `outputDimensionality` (Matryoshka) não devolve o
/// vetor já normalizado. Sem isto o termo de busca ficaria numa escala
/// diferente do catálogo (que já foi normalizado na ingestão).
function normalizarL2(values: number[]): number[] {
  const norma = Math.sqrt(values.reduce((soma, v) => soma + v * v, 0));
  if (norma === 0) return values;
  return values.map((v) => v / norma);
}

export function criarChamadorEmbeddingReal(apiKey: string): ChamadorEmbedding {
  return async (texto: string) => {
    const resposta = await fetch(`${GEMINI_EMBED_ENDPOINT}?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: { parts: [{ text: texto }] },
        taskType: 'RETRIEVAL_QUERY',
        outputDimensionality: DIMENSOES_EMBEDDING,
      }),
    });

    if (!resposta.ok) {
      const corpoErro = await resposta.text();
      throw new ErroHttp(502, `Gemini embedContent falhou (HTTP ${resposta.status}): ${corpoErro}`);
    }

    const json = await resposta.json();
    const values = json?.embedding?.values as number[] | undefined;
    if (!values || values.length !== DIMENSOES_EMBEDDING) {
      throw new ErroHttp(
        502,
        `Embedding do Gemini com formato inesperado: esperava ${DIMENSOES_EMBEDDING} dimensões, recebeu ${values?.length ?? 0}.`,
      );
    }

    return normalizarL2(values);
  };
}

/// Consulta `match_alimentos` usando o JWT do PRÓPRIO usuário — mesma regra
/// de menor privilégio de `criarCatalogoAlimentosReal`: a função já concede
/// `execute` a `authenticated` (20260729120000_create_match_alimentos.sql),
/// não precisa da service_role.
function criarBuscaSemanticaReal(
  supabaseUrl: string,
  anonKey: string,
  jwt: string,
): BuscaSemanticaLike {
  return {
    async buscar(embedding: number[]) {
      const client = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
      });
      // Mesma técnica de `criarCatalogoAlimentosReal`/
      // `scripts/seed_food_embeddings.ts`: `vector` não é array nativo do
      // Postgres — PostgREST não converte um array JSON puro para ele. A
      // string "[v1,v2,...]" (JSON.stringify de um array de números)
      // funciona porque pgvector aceita esse texto como entrada literal.
      const { data, error } = await client.rpc('match_alimentos', {
        query_embedding: JSON.stringify(embedding),
        match_threshold: BUSCA_SEMANTICA_THRESHOLD,
        match_count: 1,
      });
      if (error) {
        throw new ErroHttp(500, `Erro na busca semântica: ${error.message}`);
      }
      return ((data ?? []) as Array<{ id: string; similarity: number }>).map((row) => ({
        id: row.id,
        similarity: row.similarity,
      }));
    },
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
  // RELATÓRIO 20260823_0004 — estas 4 colunas já eram lidas pela SELECT
  // abaixo desde a migration 20260802120000 (o cálculo de fallback em
  // `encontrarMedida` sempre dependeu delas), mas esta interface nunca
  // tinha sido atualizada — achado ao rodar `deno check` de verdade
  // (nunca tinha sido rodado nesta função desde aquela migration).
  categoria_consumo: string | null;
  unidade_medida_padrao: string | null;
  medida_padrao_nome: string | null;
  medida_padrao_qtd: number | string | null;
  alimentos_medidas_caseiras: Array<{ medida: string; gramas: number | string }> | null;
}

// RELATÓRIO 20260824_0001 — achado real em device (fundador): fotografar
// um prato ficou lento/instável depois da curadoria em massa do catálogo
// (RELATÓRIO 20260823_0004, 637 alimentos + 1.056 medidas caseiras vs. os
// 270 esparsos de antes). Medido nesta tarefa: a leitura completa de
// `alimentos_referencia` + `alimentos_medidas_caseiras` aninhadas leva
// ~1,5s e ~310KB — e ANTES desta correção isso acontecia em TODA foto de
// prato, sempre do zero, mesmo o catálogo mudando raramente (só quando um
// admin edita pela tela `AdminAlimentos.tsx`).
//
// Cache em memória no ESCOPO DO MÓDULO (nível de isolate Deno) — sobrevive
// entre invocações da função enquanto a instância ficar "quente" (mesmo
// princípio de qualquer runtime serverless com reuso de instância).
// Correto mesmo compartilhado entre usuários diferentes: o dado é público
// do produto (RLS `using (true)`), a query não filtra por usuário — o
// resultado é idêntico não importa de quem for o JWT usado pra buscar.
// TTL de 30 minutos (RELATÓRIO 20260825_0003 — era 5min): achado real ao
// investigar "texto/áudio lentos" — este cache é POR ISOLATE Deno, não
// compartilhado entre instâncias; qualquer novo isolate (escala
// horizontal, ou um cold start depois de ficar ocioso) paga o round-trip
// inteiro de novo (~1,5s/~310KB) mesmo que outro isolate tenha acabado de
// carregar o mesmo catálogo. Isso vale pros TRÊS métodos igualmente (o
// catálogo é lido pra foto/texto/áudio, sempre) — 5min era curto demais
// pra realmente "esquentar" o cache antes de expirar de novo em uso
// normal (não-intenso). 30min equilibra melhor "praticamente elimina o
// round-trip na prática" com "uma edição no Admin demora até 30min pra
// valer" (aceitável — dado de curadoria, não muda a cada segundo).
// Zerado automaticamente a cada cold start da função, como sempre.
const CATALOGO_CACHE_TTL_MS = 30 * 60 * 1000;
let catalogoCacheEmMemoria: { dados: AlimentoCatalogo[]; expiraEm: number } | null = null;

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
      const agora = Date.now();
      if (catalogoCacheEmMemoria && catalogoCacheEmMemoria.expiraEm > agora) {
        return catalogoCacheEmMemoria.dados;
      }

      const client = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${jwt}` } },
      });
      const { data, error } = await client
        .from('alimentos_referencia')
        .select(
          'id, nome_taco, aliases, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g, categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd, alimentos_medidas_caseiras(medida, gramas)',
        );
      if (error) {
        throw new ErroHttp(500, `Erro ao carregar alimentos_referencia: ${error.message}`);
      }

      const catalogo = ((data ?? []) as unknown as LinhaAlimentoBruta[]).map((linha) => ({
        id: linha.id,
        nomeTaco: linha.nome_taco,
        aliases: linha.aliases ?? [],
        caloriasKcal100g: Number(linha.calorias_kcal_100g),
        proteinasG100g: Number(linha.proteinas_g_100g),
        carboidratosG100g: Number(linha.carboidratos_g_100g),
        gordurasG100g: Number(linha.gorduras_g_100g),
        categoriaConsumo: linha.categoria_consumo ?? undefined,
        unidadeMedidaPadrao: linha.unidade_medida_padrao ?? undefined,
        medidaPadraoNome: linha.medida_padrao_nome ?? undefined,
        medidaPadraoQtd: linha.medida_padrao_qtd ? Number(linha.medida_padrao_qtd) : undefined,
        medidas: (linha.alimentos_medidas_caseiras ?? []).map((m) => ({
          medida: m.medida,
          gramas: Number(m.gramas),
        })),
      }));

      catalogoCacheEmMemoria = { dados: catalogo, expiraEm: agora + CATALOGO_CACHE_TTL_MS };
      return catalogo;
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────
// Handler HTTP
// ─────────────────────────────────────────────────────────────────────────
export function createHandler(deps: HandlerDeps = {}) {
  // DIAGNÓSTICO 20260825_0007 (instrumentação temporária, ver relatório) —
  // `handleRequest` (abaixo) é só um wrapper fino em volta da lógica real
  // (renomeada para `processarRequest`, corpo 100% idêntico ao de antes,
  // nenhuma linha de comportamento mudou) — existe só pra logar duração
  // total + status HTTP + tamanho do corpo da resposta, sem importar qual
  // dos MUITOS `return` internos foi o caminho tomado. `resposta.clone()`
  // é necessário porque um `Response` só deixa o corpo ser lido uma vez —
  // sem clonar, o corpo real devolvido ao cliente ficaria consumido aqui.
  async function processarRequest(req: Request): Promise<Response> {
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
          message: `O extrator de "${tipo}" ainda não foi implementado (A.8, incremental).`,
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

      // RELATÓRIO 20260824_0003 — Método 1 (texto): o corpo NÃO é binário
      // de imagem/áudio, é a descrição digitada em UTF-8 puro — decodifica
      // como texto em vez de base64, e pula a detecção de mime de
      // imagem/áudio (não se aplica).
      const ehTexto = tipo === TIPO_PRATO_REFEICAO_TEXTO;
      const ehAudio = tipo === TIPO_PRATO_REFEICAO_AUDIO;

      let descricaoTexto: string | undefined;
      let mimeType = 'image/jpeg';
      if (ehTexto) {
        descricaoTexto = new TextDecoder('utf-8').decode(bytes);
        if (!descricaoTexto.trim()) {
          return jsonResponse({ error: 'Descrição vazia — nenhum texto recebido.' }, 400);
        }
      } else {
        // O cliente manda octet-stream; a câmera do celular produz JPEG e o
        // gravador de áudio produz algo tipo AAC/M4A. Aceita um mime
        // explícito via header quando o formato não é o padrão de cada um.
        const mimeHeader = req.headers.get('X-Image-Mime') ?? req.headers.get('Content-Type') ?? '';
        mimeType = ehAudio
          ? (mimeHeader.startsWith('audio/') ? mimeHeader : 'audio/mp4')
          : (mimeHeader.startsWith('image/') ? mimeHeader : 'image/jpeg');
        base64 = bytesParaBase64(bytes);
      }

      const chamarGemini =
        deps.chamarGemini ??
        (() => {
          const apiKey = Deno.env.get('GEMINI_API_KEY');
          if (!apiKey) {
            throw new ErroHttp(500, 'GEMINI_API_KEY não configurada no servidor.');
          }
          // Model Routing (ver bloco no topo do arquivo): o modelo muda por
          // tipo_captura, não é mais um único valor fixo pra função inteira.
          const modelo = resolverModeloParaTipo(tipo);
          // RELATÓRIO 20260824_0002 — tipos no nível CORE (prato/rótulo)
          // ganham fallback automático pro nível LITE se a cota diária do
          // CORE esgotar (achado real em produção: free tier, 20
          // requisições/dia). Tipos já em LITE não têm pra onde degradar
          // mais (`null` = sem fallback, mesmo comportamento de antes).
          const nivel = NIVEL_POR_TIPO[tipo] ?? 'core';
          const modeloFallback = nivel === 'core' ? resolverModelo('lite') : null;
          return criarChamadorGeminiComFallback(apiKey, modelo, modeloFallback);
        })();

      // Os 4 extratores de OCR de visor (nunca `ehTexto`) sempre passam pelo
      // `else` acima, que preenche `base64` — este guard só existe pra
      // TypeScript enxergar isso (o tipo de `base64` continua `string |
      // null` até aqui porque o ramo `ehTexto` pode ter deixado nulo).
      if (tipo === TIPO_GLICOSIMETRO || tipo === TIPO_BALANCA || tipo === TIPO_PRESSAO_ARTERIAL || tipo === TIPO_ROTULO) {
        if (base64 === null) {
          return jsonResponse({ error: 'Erro interno ao processar a captura.' }, 500);
        }
        if (tipo === TIPO_GLICOSIMETRO) {
          return await processarGlicosimetro({ base64, mimeType, chamarGemini });
        }
        if (tipo === TIPO_BALANCA) {
          return await processarBalanca({ base64, mimeType, chamarGemini });
        }
        if (tipo === TIPO_PRESSAO_ARTERIAL) {
          return await processarPressaoArterial({ base64, mimeType, chamarGemini });
        }
        return await processarRotulo({ base64, mimeType, chamarGemini });
      }

      // Only remaining types: TIPO_PRATO_REFEICAO / _TEXTO / _AUDIO — as 3
      // fontes do Registro de Refeição (RELATÓRIO 20260824_0003), todas
      // processadas por `processarPratoRefeicao` (ver `fonte`).
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

      // Fábricas, NÃO instâncias já construídas — diferente de `chamarGemini`
      // acima (que roda em toda foto, glicosímetro ou prato), a busca
      // semântica só é necessária quando sobra item não reconhecido pelo
      // casamento léxico, e isso só se sabe DEPOIS de rodar `calcularPrato`
      // dentro de `processarPratoRefeicao`. Chamar `criarChamadorEmbeddingReal`/
      // `criarBuscaSemanticaReal` (ou checar GEMINI_API_KEY) eagerly aqui
      // quebraria o caminho comum — prato onde tudo já casa por alias nunca
      // deveria exigir GEMINI_API_KEY duas vezes nem tocar o banco de novo.
      const obterChamarEmbedding = (): ChamadorEmbedding => {
        if (deps.chamarEmbedding) return deps.chamarEmbedding;
        const apiKey = Deno.env.get('GEMINI_API_KEY');
        if (!apiKey) {
          throw new ErroHttp(500, 'GEMINI_API_KEY não configurada no servidor.');
        }
        return criarChamadorEmbeddingReal(apiKey);
      };

      const obterBuscaSemantica = (): BuscaSemanticaLike => {
        if (deps.buscaSemantica) return deps.buscaSemantica;
        if (!supabaseUrl || !anonKey) {
          throw new ErroHttp(500, 'Configuração do servidor incompleta.');
        }
        return criarBuscaSemanticaReal(supabaseUrl, anonKey, jwt);
      };

      const fonte: FontePratoRefeicao = ehTexto ? 'texto' : ehAudio ? 'audio' : 'foto';
      return await processarPratoRefeicao({
        fonte,
        base64: base64 ?? undefined,
        mimeType,
        descricaoTexto,
        chamarGemini,
        catalogoAlimentos,
        obterChamarEmbedding,
        obterBuscaSemantica,
      });
    } catch (erro) {
      if (erro instanceof ErroHttp) {
        // 502 do Gemini / 500 de config ou banco: mensagem genérica ao
        // cliente, detalhe só no log do servidor. 429 só chega até aqui se
        // o fallback de modelo (CORE→LITE, ver `criarChamadorGeminiComFallback`)
        // TAMBÉM esgotou — ou o tipo já era LITE e não tinha pra onde
        // degradar. Mensagem HONESTA (Regra 0.15): "tente novamente" seria
        // enganoso pra uma cota diária — não é uma falha que alguns
        // segundos resolvem.
        console.error('extract-metric-photo:', erro.message);
        const mensagem =
          erro.status === 429
            ? 'Limite diário de análises por IA atingido. Tente novamente amanhã, ou digite a refeição manualmente.'
            : erro.status === 502
              ? 'Falha ao analisar a imagem.'
              : 'Erro interno.';
        return jsonResponse({ error: mensagem }, erro.status);
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
  }

  return async function handleRequest(req: Request): Promise<Response> {
    const inicioExecucao = Date.now();
    const resposta = await processarRequest(req);
    const duracaoMs = Date.now() - inicioExecucao;
    let tamanhoCorpo = 'desconhecido';
    try {
      tamanhoCorpo = String((await resposta.clone().text()).length);
    } catch {
      // Best-effort — nunca deixa o log de diagnóstico derrubar a resposta
      // real que já está pronta pra sair.
    }
    console.log(
      `[extract-metric-photo] CONCLUSÃO: duracao=${duracaoMs}ms status=${resposta.status} tamanho_corpo=${tamanhoCorpo}bytes`,
    );
    return resposta;
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

async function processarBalanca(params: {
  base64: string;
  mimeType: string;
  chamarGemini: ChamadorGemini;
}): Promise<Response> {
  const textoCru = await params.chamarGemini({
    base64: params.base64,
    mimeType: params.mimeType,
    systemPrompt: SYSTEM_PROMPT_BALANCA,
    userText: 'Read the weight value on this scale display.',
  });
  const extracao = parseRespostaGeminiBalanca(textoCru);

  const avaliacao = avaliarLeituraBalanca(extracao);
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

  // `peso_kg` é a chave que o cliente (HealthPayloadModel.fromAiExtraction)
  // já sabe parsear.
  return jsonResponse(
    {
      peso_kg: avaliacao.pesoKg,
      confianca: avaliacao.confianca,
      tipo_captura: TIPO_BALANCA,
      possivel_foto_de_tela: avaliacao.possivelFotoDeTela,
    },
    200,
  );
}

async function processarPressaoArterial(params: {
  base64: string;
  mimeType: string;
  chamarGemini: ChamadorGemini;
}): Promise<Response> {
  const textoCru = await params.chamarGemini({
    base64: params.base64,
    mimeType: params.mimeType,
    systemPrompt: SYSTEM_PROMPT_PRESSAO,
    userText: 'Read the systolic, diastolic and pulse values on this blood pressure monitor display.',
  });
  const extracao = parseRespostaGeminiPressao(textoCru);

  const avaliacao = avaliarLeituraPressao(extracao);
  if (!avaliacao.aceita) {
    return jsonResponse(
      {
        error: 'leitura_ilegivel',
        motivo: avaliacao.motivo,
        message:
          'Não consegui ler o visor com segurança. Tente outra foto, sem reflexo e com os números nítidos.',
      },
      422,
    );
  }

  // `pressao_sistolica`/`pressao_diastolica` são as chaves que o cliente
  // (HealthPayloadModel.fromAiExtraction) já sabe parsear. O modelo não tem
  // coluna própria de "pulso" — reaproveita `fc_repouso` (mesma medida
  // fisiológica, batimentos por minuto; já alimenta o mesmo pipeline de
  // `metricas_saude_diarias` e a checagem de anomalia de frequência
  // cardíaca do app). Ausente do JSON quando o aparelho não mostrou pulso —
  // nunca um `null` explícito nem um zero inventado.
  return jsonResponse(
    {
      pressao_sistolica: avaliacao.sistolicaMmhg,
      pressao_diastolica: avaliacao.diastolicaMmhg,
      ...(avaliacao.pulsoBpm !== undefined ? { fc_repouso: avaliacao.pulsoBpm } : {}),
      confianca: avaliacao.confianca,
      tipo_captura: TIPO_PRESSAO_ARTERIAL,
      possivel_foto_de_tela: avaliacao.possivelFotoDeTela,
    },
    200,
  );
}

async function processarRotulo(params: {
  base64: string;
  mimeType: string;
  chamarGemini: ChamadorGemini;
}): Promise<Response> {
  const textoCru = await params.chamarGemini({
    base64: params.base64,
    mimeType: params.mimeType,
    systemPrompt: SYSTEM_PROMPT_ROTULO,
    userText: 'Transcribe the nutrition facts label in this photo.',
  });
  const extracao = parseRespostaGeminiRotulo(textoCru);

  const avaliacao = avaliarLeituraRotulo(extracao);
  if (!avaliacao.aceita) {
    return jsonResponse(
      {
        error: 'leitura_ilegivel',
        motivo: avaliacao.motivo,
        message:
          'Não consegui ler o rótulo com segurança. Tente outra foto, com a tabela nutricional inteira e nítida.',
      },
      422,
    );
  }

  // Formato próprio, não mapeia em HealthPayloadModel (mesma situação de
  // pratoRefeicao — ver `rawFoodResult` no client) — pendência de UI
  // registrada no RELATÓRIO, fora do escopo desta função servidora.
  return jsonResponse(
    {
      tipo_captura: TIPO_ROTULO,
      porcao_descricao: avaliacao.porcaoDescricao,
      calorias_kcal: avaliacao.caloriasKcal,
      proteinas_g: avaliacao.proteinasG,
      carboidratos_g: avaliacao.carboidratosG,
      gorduras_g: avaliacao.gordurasG,
      ingredientes_principais: avaliacao.ingredientesPrincipais,
      confianca: avaliacao.confianca,
      possivel_foto_de_tela: avaliacao.possivelFotoDeTela,
    },
    200,
  );
}

/// RELATÓRIO 20260824_0003 — um por método de captura de refeição. As TRÊS
/// fontes produzem o MESMO contrato de itens (nome/medida/quantidade/
/// confiança) — só o prompt/entrada que vai pro Gemini muda; casamento
/// léxico/semântico, cálculo determinístico e a resposta JSON abaixo são
/// idênticos pras três (não duplicados por fonte).
type FontePratoRefeicao = 'foto' | 'texto' | 'audio';

function montarChamadaGeminiPrato(params: {
  fonte: FontePratoRefeicao;
  base64?: string;
  mimeType?: string;
  descricaoTexto?: string;
}): { base64?: string; mimeType?: string; systemPrompt: string; userText: string } {
  switch (params.fonte) {
    case 'foto':
      return {
        base64: params.base64,
        mimeType: params.mimeType,
        systemPrompt: SYSTEM_PROMPT_PRATO_REFEICAO,
        userText: 'Identify the food items and their home-measure portions on this plate.',
      };
    case 'audio':
      return {
        base64: params.base64,
        mimeType: params.mimeType,
        systemPrompt: SYSTEM_PROMPT_PRATO_REFEICAO_AUDIO,
        userText: 'Listen to this audio and identify the food items mentioned, with their home-measure portions.',
      };
    case 'texto':
      return {
        // Sem inlineData — o texto do usuário É o conteúdo, vai como
        // userText mesmo (ver `criarChamadorGeminiReal`: sem base64/
        // mimeType, `parts` não inclui `inlineData`).
        systemPrompt: SYSTEM_PROMPT_PRATO_REFEICAO_TEXTO,
        userText: `User's meal description: "${(params.descricaoTexto ?? '').trim()}"`,
      };
  }
}

async function processarPratoRefeicao(params: {
  fonte: FontePratoRefeicao;
  base64?: string;
  mimeType?: string;
  /// Só presente/usado quando `fonte === 'texto'`.
  descricaoTexto?: string;
  chamarGemini: ChamadorGemini;
  catalogoAlimentos: CatalogoAlimentosLike;
  /// Fábricas, não instâncias — só invocadas se sobrar item não reconhecido
  /// pelo casamento léxico (ver comentário no handler).
  obterChamarEmbedding: () => ChamadorEmbedding;
  obterBuscaSemantica: () => BuscaSemanticaLike;
}): Promise<Response> {
  // Gemini (identificação) e catálogo (banco) não dependem um do outro —
  // rodam em paralelo para não somar as duas latências.
  const [textoCru, catalogo] = await Promise.all([
    params.chamarGemini(
      montarChamadaGeminiPrato({
        fonte: params.fonte,
        base64: params.base64,
        mimeType: params.mimeType,
        descricaoTexto: params.descricaoTexto,
      }),
    ),
    params.catalogoAlimentos.carregar(),
  ]);

  const extracao = parseRespostaGeminiPrato(textoCru);
  // O CÁLCULO é inteiramente do backend — o Gemini nunca viu `catalogo`.
  const calculo = calcularPrato(extracao.itens, catalogo);
  // DIAGNÓSTICO 20260825_0007 (instrumentação temporária, ver relatório) —
  // marca a fronteira entre "casamento de medida" (dentro de calcularPrato,
  // já logado item a item por `encontrarMedida`) e o que vem depois
  // (busca semântica condicional + montagem da resposta) — se a execução
  // parar de aparecer no log DEPOIS desta linha, o problema está em algo
  // abaixo dela, não no casamento em si.
  console.log(
    `[processarPratoRefeicao] calcularPrato concluído: ${calculo.itens.length} itens casados, ${calculo.itensNaoReconhecidos.length} não reconhecidos`,
  );

  // Segunda tentativa (Missão F45): só roda I/O extra (Gemini + banco) se
  // sobrou algo que o casamento léxico não achou — o caminho comum (tudo já
  // casa por alias) nunca paga esse custo.
  const temCandidatoSemantico = calculo.itensNaoReconhecidos.some(
    (item) => item.motivo === 'alimento_nao_encontrado',
  );
  const itensFinais = [...calculo.itens];
  let itensNaoReconhecidosFinais = calculo.itensNaoReconhecidos;

  if (temCandidatoSemantico) {
    try {
      const { resolvidos, aindaNaoReconhecidos } = await resolverComBuscaSemantica(
        calculo.itensNaoReconhecidos,
        catalogo,
        params.obterChamarEmbedding(),
        params.obterBuscaSemantica(),
      );
      itensFinais.push(...resolvidos);
      itensNaoReconhecidosFinais = aindaNaoReconhecidos;
    } catch (erro) {
      // Degradação graciosa: se busca semântica falhar, manter itens em "Não
      // reconhecidos" é melhor que derrubar a função. Log para debugging.
      console.error(
        'Falha em busca semântica (fallback degradado):',
        erro instanceof Error ? erro.message : 'erro desconhecido',
      );
      // itensNaoReconhecidosFinais já tem os itens não encontrados — eles
      // permanecem como estão, sem processamento semântico
    }
  }

  const totaisFinais = somarTotais(itensFinais);

  // Informativo (nenhum código Flutter lê `tipo_captura` da resposta —
  // confirmado nesta tarefa — mas vale refletir a fonte real nos logs).
  const tipoCapturaResposta =
    params.fonte === 'texto'
      ? TIPO_PRATO_REFEICAO_TEXTO
      : params.fonte === 'audio'
        ? TIPO_PRATO_REFEICAO_AUDIO
        : TIPO_PRATO_REFEICAO;

  return jsonResponse(
    {
      tipo_captura: tipoCapturaResposta,
      itens: itensFinais.map((item) => ({
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
        ...(item.origemCasamento ? { origem_casamento: item.origemCasamento } : {}),
        ...(item.similaridade !== undefined ? { similaridade: item.similaridade } : {}),
        ...(item.quantidadeEstimada ? {
          quantidade_estimada: item.quantidadeEstimada,
          peso_tipico_gramas: item.pesoTipicoGramas,
        } : {}),
        // RELATÓRIO 20260823_0004 — fix do achado 20260823_0003: antes deste
        // fix, estes 4 campos nunca chegavam aqui (ver doc de
        // `ItemPratoCalculado.categoriaConsumo`) — `ItemPratoExtraidoModel.
        // fromJson` no Flutter já sabia ler `categoria_consumo`/etc., só
        // nunca recebia.
        ...(item.categoriaConsumo ? { categoria_consumo: item.categoriaConsumo } : {}),
        ...(item.unidadeMedidaPadrao ? { unidade_medida_padrao: item.unidadeMedidaPadrao } : {}),
        ...(item.medidaPadraoNome ? { medida_padrao_nome: item.medidaPadraoNome } : {}),
        ...(item.medidaPadraoQtd !== undefined ? { medida_padrao_qtd: item.medidaPadraoQtd } : {}),
      })),
      itens_nao_reconhecidos: itensNaoReconhecidosFinais.map((item) => ({
        nome: item.nome,
        medida: item.medida,
        motivo: item.motivo,
      })),
      totais: {
        calorias: totaisFinais.calorias,
        proteinas_g: totaisFinais.proteinasG,
        carboidratos_g: totaisFinais.carboidratosG,
        gorduras_g: totaisFinais.gordurasG,
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
