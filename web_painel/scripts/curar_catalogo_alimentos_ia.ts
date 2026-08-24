/**
 * RELATÓRIO 20260823_0004 — Curadoria em massa (via Gemini) do catálogo
 * `alimentos_referencia` (637 linhas) + regeneração completa de
 * `alimentos_medidas_caseiras` (F45, Adendo v5.1 §A.3).
 *
 * Corrige o estado real encontrado na investigação 20260823_0003:
 *   - 594/637 alimentos sem NENHUM alias (só o nome_taco cru).
 *   - 620/637 sem categoria_consumo/unidade_medida_padrao (só os 17
 *     curados manualmente nas migrations 20260716120000/20260802120000
 *     têm).
 *   - 599/637 sem NENHUMA medida caseira; os 38 que têm foram semeados por
 *     `seed_taco_completa.ts` com a MESMA lista de 7 medidas genéricas
 *     aplicada cegamente a todo alimento (ex.: "Alface, crua" ganhou
 *     "unidade=100g"/"fatia=50g", "Café, coado" ganhou "colher de
 *     sopa=25g") — dado errado, não só incompleto.
 *
 * ESTRATÉGIA (decisão do fundador, RELATÓRIO 20260823_0003→0004):
 *   1. Apagar as 270 linhas de `alimentos_medidas_caseiras` existentes e
 *      regenerar do zero para os 637, de forma consistente.
 *   2. Usar o Gemini (mesma infra do produto, `GEMINI_API_KEY`) para gerar
 *      aliases/categoria/unidade/medida padrão/medidas caseiras REAIS por
 *      alimento — não uma lista genérica única.
 *   3. Qualquer alimento que o próprio Gemini reportar baixa confiança
 *      fica com `revisao_necessaria=true` + `observacao_revisao`
 *      (colunas novas, migration `20260823100000`) — nunca fica
 *      silenciosamente errado. O mesmo vale para falhas técnicas
 *      (resposta ilegível, item fora do formato esperado): fallback
 *      seguro (peso_livre, 100g) + revisão marcada, nunca null.
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Confirme .env.local com GEMINI_API_KEY + SUPABASE_SERVICE_ROLE_KEY
 *   3. Rode a migration 20260823100000 antes (supabase db push).
 *   4. npm run curar:catalogo-alimentos
 *      Opcional: CURADORIA_LIMIT=30 npm run curar:catalogo-alimentos
 *        (processa só os 30 primeiros — smoke test antes do lote completo)
 *      Opcional: GEMINI_MODEL_CURADORIA=outro-modelo npm run curar:catalogo-alimentos
 *      Opcional: CURADORIA_RPM_LIMIT=20 npm run curar:catalogo-alimentos
 *        (padrão 20 req/min — prompts de lote são maiores que os de embedding)
 *      Opcional: CURADORIA_SKIP_DELETE=1 npm run curar:catalogo-alimentos
 *        (não apaga as medidas caseiras existentes antes — só para debug/
 *        reexecução parcial; a corrida normal deve rodar SEM essa flag)
 */
import { config } from 'dotenv';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

config(); // .env (valores públicos, versionados)
config({ path: '.env.local', override: true }); // .env.local (segredos)

const MODELO = process.env.GEMINI_MODEL_CURADORIA || 'gemini-flash-latest';
const TAMANHO_LOTE = 15;
const RPM_LIMIT = Number(process.env.CURADORIA_RPM_LIMIT) || 20;
const DELAY_ENTRE_CHAMADAS_MS = Math.ceil(60_000 / RPM_LIMIT);
const MAX_TENTATIVAS = 5;
const LIMITE_TESTE = process.env.CURADORIA_LIMIT ? Number(process.env.CURADORIA_LIMIT) : undefined;
const PULAR_DELETE = process.env.CURADORIA_SKIP_DELETE === '1';

const CATEGORIAS_VALIDAS = ['liquido_frio', 'liquido_quente', 'unidade', 'fatia', 'peso_livre'] as const;
type CategoriaConsumo = (typeof CATEGORIAS_VALIDAS)[number];

interface AlimentoPendente {
  id: string;
  nome_taco: string;
  fonte: string;
  calorias_kcal_100g: number;
  proteinas_g_100g: number;
  carboidratos_g_100g: number;
  gorduras_g_100g: number;
}

interface MedidaCaseiraGerada {
  medida: string;
  quantidade: number;
}

interface ClassificacaoGerada {
  aliases: string[];
  categoria_consumo: CategoriaConsumo;
  unidade_medida_padrao: 'g' | 'ml';
  medida_padrao_nome: string;
  medida_padrao_qtd: number;
  medidas_caseiras: MedidaCaseiraGerada[];
  confianca: number;
  observacao: string | null;
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Variável de ambiente ${name} não configurada — confirme web_painel/.env.local (veja .env.local.example).`,
    );
  }
  return value;
}

function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Mesmo normalizador usado em `alimentos_referencia`/aliases pelo resto do produto (lowercase, sem acento) — para o alias mínimo de fallback. */
function normalizarNomeSimples(nome: string): string {
  return nome
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/,.*/, '') // "Arroz, branco, cozido" -> "arroz"
    .trim();
}

/** Fallback seguro — nunca deixa um alimento sem classificação nenhuma, mesmo quando a IA falha (resposta ilegível, item ausente do lote, etc.). Sempre marcado para revisão humana. */
function classificacaoFallback(nomeTaco: string, motivo: string): ClassificacaoGerada {
  return {
    aliases: [normalizarNomeSimples(nomeTaco)],
    categoria_consumo: 'peso_livre',
    unidade_medida_padrao: 'g',
    medida_padrao_nome: 'Porção padrão',
    medida_padrao_qtd: 100,
    medidas_caseiras: [{ medida: 'Porção padrão', quantidade: 100 }],
    confianca: 0,
    observacao: `Curadoria automática falhou (${motivo}) — classificação de fallback (peso livre, 100g), precisa de revisão manual.`,
  };
}

function buscarPendentes(admin: SupabaseClient) {
  let query = admin
    .from('alimentos_referencia')
    .select('id, nome_taco, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g')
    .order('nome_taco', { ascending: true });
  if (LIMITE_TESTE !== undefined) {
    query = query.limit(LIMITE_TESTE);
  }
  return query;
}

function montarPrompt(lote: AlimentoPendente[]): string {
  const itensTexto = lote
    .map(
      (a, i) =>
        `${i}. "${a.nome_taco}" (fonte: ${a.fonte}; por 100g: ${a.calorias_kcal_100g}kcal, ` +
        `${a.proteinas_g_100g}g proteína, ${a.carboidratos_g_100g}g carboidrato, ${a.gorduras_g_100g}g gordura)`,
    )
    .join('\n');

  return `Você é um nutricionista curando um catálogo de alimentos para um app brasileiro de registro de refeições por foto. Para CADA alimento da lista abaixo, gere uma classificação completa.

LISTA DE ALIMENTOS (índice — nome — macros por 100g):
${itensTexto}

Para cada alimento, gere:
- "indice": o número do alimento na lista acima (0-based), EXATAMENTE como veio.
- "aliases": 3 a 6 sinônimos/variações em pt-BR que uma pessoa comum diria ao fotografar esse alimento (sem acento não é necessário, use português normal). Inclua sempre uma versão simplificada do nome (ex.: "Carne, bovina, contrafilé, grelhado" -> "bife", "contrafilé", "carne grelhada").
- "categoria_consumo": EXATAMENTE um destes 5 valores: "liquido_frio" (bebidas frias: suco, refrigerante, leite gelado, água), "liquido_quente" (café, chá, sopa líquida), "unidade" (alimentos contados em unidades inteiras: ovo, pão de queijo, azeitona, coxinha, biscoito), "fatia" (alimentos fatiados: presunto, queijo, pão de forma, bolo fatiado), ou "peso_livre" (tudo que se serve por peso/porção variável: arroz, feijão, carne, salada, massa).
- "unidade_medida_padrao": "ml" se categoria_consumo for líquido, senão "g".
- "medida_padrao_nome": rótulo amigável e curto (ex.: "Unidade", "Fatia", "Copo médio", "Xícara", "Porção padrão").
- "medida_padrao_qtd": número — quantos g/ml representa 1 medida_padrao_nome desse alimento especificamente (NÃO um valor genérico igual pra tudo — 1 azeitona não pesa o mesmo que 1 pão de queijo).
- "medidas_caseiras": array com 1 a 3 medidas caseiras REALISTAS pra ESTE alimento específico (ex.: azeitona -> [{"medida":"unidade","quantidade":5}]; presunto -> [{"medida":"fatia","quantidade":20}]; arroz -> [{"medida":"colher de sopa","quantidade":25},{"medida":"escumadeira","quantidade":90}]; café -> [{"medida":"xícara","quantidade":50}]). "quantidade" sempre na mesma unidade de unidade_medida_padrao.
- "confianca": 0.0 a 1.0 — sua confiança nesta classificação. Use menos de 0.6 quando o nome for ambíguo, genérico demais, ou você não tiver certeza da categoria/porção típica.
- "observacao": string curta explicando a incerteza quando confianca < 0.6 (ex.: "nome genérico da TACO, porção típica incerta"), ou null quando confianca >= 0.6.

Responda APENAS com um array JSON, um objeto por alimento da lista, na mesma ordem. Nenhum texto fora do array.`;
}

function validarCategoria(valor: unknown): valor is CategoriaConsumo {
  return typeof valor === 'string' && (CATEGORIAS_VALIDAS as readonly string[]).includes(valor);
}

/** Valida e normaliza um item bruto do array devolvido pelo Gemini — nunca confia cegamente no shape (Regra 0.15: IA erra, o código nunca assume). Item inválido vira `null` (caller aplica o fallback). */
function normalizarItemGerado(bruto: unknown, nomeTaco: string): ClassificacaoGerada | null {
  if (typeof bruto !== 'object' || bruto === null) return null;
  const obj = bruto as Record<string, unknown>;

  if (!validarCategoria(obj.categoria_consumo)) return null;
  const unidade = obj.unidade_medida_padrao === 'ml' ? 'ml' : 'g';

  const aliasesBrutos = Array.isArray(obj.aliases) ? obj.aliases : [];
  const aliases = aliasesBrutos
    .filter((a): a is string => typeof a === 'string' && a.trim().length > 0)
    .map((a) => a.trim().toLowerCase());
  if (aliases.length === 0) aliases.push(normalizarNomeSimples(nomeTaco));

  const medidaPadraoQtd = typeof obj.medida_padrao_qtd === 'number' && obj.medida_padrao_qtd > 0
    ? obj.medida_padrao_qtd
    : 100;
  const medidaPadraoNome = typeof obj.medida_padrao_nome === 'string' && obj.medida_padrao_nome.trim().length > 0
    ? obj.medida_padrao_nome.trim()
    : 'Porção padrão';

  const medidasBrutas = Array.isArray(obj.medidas_caseiras) ? obj.medidas_caseiras : [];
  const medidasCaseiras: MedidaCaseiraGerada[] = medidasBrutas
    .filter(
      (m): m is { medida: string; quantidade: number } =>
        typeof m === 'object' &&
        m !== null &&
        typeof (m as Record<string, unknown>).medida === 'string' &&
        typeof (m as Record<string, unknown>).quantidade === 'number' &&
        (m as Record<string, unknown>).quantidade as number > 0,
    )
    .map((m) => ({ medida: m.medida.trim(), quantidade: m.quantidade }));
  if (medidasCaseiras.length === 0) {
    medidasCaseiras.push({ medida: medidaPadraoNome, quantidade: medidaPadraoQtd });
  }

  const confianca = typeof obj.confianca === 'number' ? Math.min(1, Math.max(0, obj.confianca)) : 0;
  const observacao = typeof obj.observacao === 'string' && obj.observacao.trim().length > 0
    ? obj.observacao.trim()
    : null;

  return {
    aliases,
    categoria_consumo: obj.categoria_consumo,
    unidade_medida_padrao: unidade,
    medida_padrao_nome: medidaPadraoNome,
    medida_padrao_qtd: medidaPadraoQtd,
    medidas_caseiras: medidasCaseiras,
    confianca,
    observacao,
  };
}

async function chamarGeminiComRetry(prompt: string, apiKey: string, contextoLog: string): Promise<string> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODELO}:generateContent?key=${apiKey}`;

  for (let tentativa = 1; tentativa <= MAX_TENTATIVAS; tentativa++) {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.2, // baixo, mas não zero — precisa variar aliases entre alimentos parecidos
          responseMimeType: 'application/json',
        },
      }),
    });

    if (response.ok) {
      const data = (await response.json()) as {
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      };
      const texto = data.candidates?.[0]?.content?.parts?.[0]?.text;
      if (typeof texto !== 'string' || texto.length === 0) {
        throw new Error(`${contextoLog}: resposta do Gemini sem texto.`);
      }
      return texto;
    }

    const retentavel = response.status === 429 || response.status >= 500;
    const corpoErro = await response.text();
    if (!retentavel || tentativa === MAX_TENTATIVAS) {
      throw new Error(`${contextoLog}: Gemini generateContent falhou (HTTP ${response.status}): ${corpoErro.slice(0, 300)}`);
    }
    const backoffMs = 2_000 * 2 ** (tentativa - 1);
    console.warn(`  ⚠️  ${contextoLog}: HTTP ${response.status} (tentativa ${tentativa}/${MAX_TENTATIVAS}) — retentando em ${backoffMs / 1000}s...`);
    await delay(backoffMs);
  }
  throw new Error(`${contextoLog}: esgotou tentativas.`);
}

/** Grava a classificação de UM alimento: UPDATE em alimentos_referencia + INSERT das medidas caseiras dele. Mesma justificativa de UPDATE-por-linha (não upsert em lote) de `seed_food_embeddings.ts` — evita a validação de NOT NULL da linha candidata de INSERT no upsert. */
async function gravarClassificacao(
  admin: SupabaseClient,
  alimentoId: string,
  classificacao: ClassificacaoGerada,
): Promise<void> {
  const { error: erroUpdate } = await admin
    .from('alimentos_referencia')
    .update({
      aliases: classificacao.aliases,
      categoria_consumo: classificacao.categoria_consumo,
      unidade_medida_padrao: classificacao.unidade_medida_padrao,
      medida_padrao_nome: classificacao.medida_padrao_nome,
      medida_padrao_qtd: classificacao.medida_padrao_qtd,
      revisao_necessaria: classificacao.confianca < 0.6,
      observacao_revisao: classificacao.confianca < 0.6 ? classificacao.observacao : null,
    })
    .eq('id', alimentoId);
  if (erroUpdate) {
    throw new Error(`Erro ao atualizar alimento ${alimentoId}: ${erroUpdate.message}`);
  }

  const linhasMedidas = classificacao.medidas_caseiras.map((m) => ({
    alimento_id: alimentoId,
    medida: m.medida,
    gramas: m.quantidade,
    revisao_necessaria: classificacao.confianca < 0.6,
    observacao_revisao: classificacao.confianca < 0.6 ? classificacao.observacao : null,
  }));
  const { error: erroInsert } = await admin.from('alimentos_medidas_caseiras').insert(linhasMedidas);
  if (erroInsert) {
    throw new Error(`Erro ao inserir medidas caseiras de ${alimentoId}: ${erroInsert.message}`);
  }
}

async function apagarMedidasCaseirasExistentes(admin: SupabaseClient): Promise<void> {
  if (PULAR_DELETE) {
    console.log('⏭️  CURADORIA_SKIP_DELETE=1 — mantendo medidas caseiras existentes.');
    return;
  }
  console.log('🗑️  Apagando medidas caseiras existentes (270 linhas, geradas por regra genérica em seed_taco_completa.ts — vão ser regeneradas por alimento)...');
  // `.neq` com um valor impossível é o idioma padrão do PostgREST para
  // "delete tudo" sem precisar de uma cláusula WHERE literal `true` (que a
  // lib recusa por segurança) — mesmo alimento_id nunca é uma string vazia.
  const { error } = await admin.from('alimentos_medidas_caseiras').delete().neq('alimento_id', '00000000-0000-0000-0000-000000000000');
  if (error) {
    throw new Error(`Erro ao apagar medidas caseiras existentes: ${error.message}`);
  }
  console.log('   ✅ Medidas caseiras existentes apagadas.\n');
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const geminiApiKey = requireEnv('GEMINI_API_KEY');

  console.log('🚀 RELATÓRIO 20260823_0004 — Curadoria em massa do catálogo de alimentos (IA)\n');
  console.log(`   Modelo: ${MODELO}`);
  console.log(`   Lote: ${TAMANHO_LOTE} alimentos/chamada`);
  console.log(`   Rate limit: ${RPM_LIMIT} req/min (${DELAY_ENTRE_CHAMADAS_MS}ms entre chamadas)`);
  if (LIMITE_TESTE !== undefined) {
    console.log(`   ⚠️  MODO TESTE: limitado a ${LIMITE_TESTE} linha(s) (CURADORIA_LIMIT)`);
  }
  console.log('');

  await apagarMedidasCaseirasExistentes(admin);

  const { data: alimentos, error } = await buscarPendentes(admin);
  if (error) throw new Error(`Erro ao buscar alimentos: ${error.message}`);
  if (!alimentos || alimentos.length === 0) {
    console.log('✅ Nenhum alimento encontrado em alimentos_referencia.');
    return;
  }
  console.log(`📊 ${alimentos.length} alimento(s) a classificar\n`);

  let processados = 0;
  let marcadosRevisao = 0;
  let falhasTecnicas = 0;
  const inicio = Date.now();

  for (let inicioLote = 0; inicioLote < alimentos.length; inicioLote += TAMANHO_LOTE) {
    const lote = alimentos.slice(inicioLote, inicioLote + TAMANHO_LOTE) as AlimentoPendente[];
    const numeroLote = Math.floor(inicioLote / TAMANHO_LOTE) + 1;
    const totalLotes = Math.ceil(alimentos.length / TAMANHO_LOTE);
    const contexto = `Lote ${numeroLote}/${totalLotes}`;

    let itensGerados: unknown[] = [];
    try {
      const prompt = montarPrompt(lote);
      const textoResposta = await chamarGeminiComRetry(prompt, geminiApiKey, contexto);
      const parseado = JSON.parse(textoResposta);
      if (!Array.isArray(parseado)) throw new Error('resposta não é um array JSON');
      itensGerados = parseado;
    } catch (err) {
      console.error(`  ❌ ${contexto}: falha ao gerar/parsear (${err instanceof Error ? err.message : err}) — aplicando fallback em todo o lote.`);
      itensGerados = [];
      falhasTecnicas += lote.length;
    }

    for (let i = 0; i < lote.length; i++) {
      const alimento = lote[i];
      const itemBruto = itensGerados.find(
        (item) => typeof item === 'object' && item !== null && (item as Record<string, unknown>).indice === i,
      );
      let classificacao = itemBruto ? normalizarItemGerado(itemBruto, alimento.nome_taco) : null;
      if (!classificacao) {
        classificacao = classificacaoFallback(alimento.nome_taco, itemBruto ? 'item malformado' : 'item ausente na resposta');
      }

      try {
        await gravarClassificacao(admin, alimento.id, classificacao);
        if (classificacao.confianca < 0.6) marcadosRevisao++;
      } catch (err) {
        console.error(`  ❌ Erro ao gravar "${alimento.nome_taco}" (${alimento.id}): ${err instanceof Error ? err.message : err}`);
        falhasTecnicas++;
      }
      processados++;
    }

    console.log(`  💾 ${contexto} gravado (${processados}/${alimentos.length} alimentos processados até agora)`);

    if (inicioLote + TAMANHO_LOTE < alimentos.length) {
      await delay(DELAY_ENTRE_CHAMADAS_MS);
    }
  }

  const duracaoS = ((Date.now() - inicio) / 1000).toFixed(1);
  console.log(`\n🎉 Concluído em ${duracaoS}s`);
  console.log(`   Processados: ${processados}/${alimentos.length}`);
  console.log(`   Marcados para revisão humana (confiança < 0.6 ou falha): ${marcadosRevisao}`);
  console.log(`   Falhas técnicas (fallback aplicado): ${falhasTecnicas}`);
}

main().catch((err) => {
  console.error('\n❌ Erro fatal durante a curadoria do catálogo:', err instanceof Error ? err.message : err);
  process.exit(1);
});
