/**
 * N20 (Fase 0, Parte 9.1 do Mestre v7.0) — Re-seed de embeddings REAIS para
 * `alimentos_referencia`, sobrescrevendo os 23 vetores MOCK (hash MD5) e
 * qualquer linha semeada com um modelo que não é mais o vigente.
 *
 * REESCRITO NESTA TAREFA (era `seed_food_embeddings.ts` do F46 — ver git log
 * para a versão anterior). Diferenças principais:
 *   1. Modelo vem de EMBEDDING_MODEL_NAME (Regra 16), não mais hardcoded
 *      'text-embedding-004' — que, aliás, já não existe na API v1beta (ver
 *      commit 14083ed); rodar a versão antiga hoje daria HTTP 404 em toda
 *      chamada.
 *   2. Corrigido: faltava `taskType: 'RETRIEVAL_DOCUMENT'` +
 *      `outputDimensionality` no corpo da requisição — mesmo bug que
 *      search-food/index.ts tinha (ver RELATÓRIO). Sem isso o embedding do
 *      catálogo e o do termo de busca não formam o par assimétrico que
 *      `match_alimentos` pressupõe.
 *   3. Seleciona por PROVENIÊNCIA (`embedding_model`, coluna nova de
 *      20260807200000), não por `embedding IS NULL` — a versão antiga nunca
 *      reprocessaria os 23 mock nem nenhum real desatualizado, porque os
 *      dois já têm `embedding` não-nulo. Ver comentário de `buscarPendentes`.
 *   4. Rate limit real (RPM configurável, não só um `setTimeout(100)` fixo
 *      dentro do loop) + retry com backoff exponencial em 429/5xx (Regra 21
 *      — "não um loop O(n) ingênuo que dará timeout").
 *   5. Carrega `.env` E `.env.local` — a versão antiga só carregava `.env`
 *      (`import 'dotenv/config'` sem `path`), então `SUPABASE_SERVICE_ROLE_KEY`
 *      /`GEMINI_API_KEY` (que só existem em `.env.local`, nunca commitado)
 *      não eram carregadas por este script mesmo com o arquivo presente —
 *      só funcionava se alguém copiasse os valores pra dentro do `.env` na
 *      mão. Corrigido para carregar os dois, mesma convenção que o Vite já
 *      usa para o app.
 *
 * CONTAGEM REAL (investigada nesta tarefa, não presumida): `alimentos_referencia`
 * tem 637 linhas hoje, não ~8.000 como o Mestre v7.0 registra — ver
 * RELATÓRIO DE FIM DE TAREFA (docs/log_dev/20260807_0002.md) para a
 * correção de fato completa. Este script processa "o que existir na
 * tabela", nunca um número fixo — se o catálogo crescer depois (nova carga
 * TACO/USDA), rodar de novo re-semeia só as linhas novas.
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Confirme .env.local com GEMINI_API_KEY + SUPABASE_SERVICE_ROLE_KEY
 *   3. Rode a migration 20260807200000 antes (supabase db push) — este
 *      script depende da coluna alimentos_referencia.embedding_model.
 *   4. npm run seed:food-embeddings
 *      Opcional: EMBEDDING_SEED_LIMIT=5 npm run seed:food-embeddings
 *        (processa só 5 linhas — smoke test antes do lote completo)
 *      Opcional: EMBEDDING_MODEL_NAME=outro-modelo npm run seed:food-embeddings
 *        (força um modelo diferente do padrão — troque a secret da Edge
 *        Function pro mesmo valor depois, ou os três lados divergem de novo)
 *      Opcional: EMBEDDING_RPM_LIMIT=60 npm run seed:food-embeddings
 *        (padrão 100 req/min — baixe se sua chave estiver num tier mais restrito)
 */
import { config } from 'dotenv';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

config(); // .env (valores públicos, versionados como .env.example)
config({ path: '.env.local', override: true }); // .env.local (segredos, nunca commitado)

const EMBEDDING_MODEL_NAME = process.env.EMBEDDING_MODEL_NAME || 'gemini-embedding-001';
const DIMENSOES_EMBEDDING = 768;
const RPM_LIMIT = Number(process.env.EMBEDDING_RPM_LIMIT) || 100;
const DELAY_ENTRE_CHAMADAS_MS = Math.ceil(60_000 / RPM_LIMIT);
const MAX_TENTATIVAS = 5;
const LIMITE_TESTE = process.env.EMBEDDING_SEED_LIMIT ? Number(process.env.EMBEDDING_SEED_LIMIT) : undefined;

interface AlimentoPendente {
  id: string;
  nome_taco: string;
  aliases: string[];
}

interface EmbeddingParaGravar {
  id: string;
  embedding: string; // literal pgvector "[v1,v2,...]" — ver nota em gravarLote
  embedding_model: string;
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

/** Mesma lógica de seed_cloud.ts/etl_carga_taco.ts: VITE_SUPABASE_URL já vem com `/rest/v1/`; o client admin precisa só da origem. */
function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Busca as linhas que precisam de um embedding novo — três casos cobertos
 * pela MESMA condição, todos "não tenho garantia de que este vetor veio do
 * EMBEDDING_MODEL_NAME vigente":
 *   - `embedding IS NULL`: nunca foi semeada.
 *   - `embedding_model IS NULL`: foi semeada antes da coluna existir — cobre
 *     TANTO os 23 vetores MOCK quanto qualquer real semeado com um modelo
 *     anterior (não dá pra distinguir os dois só olhando o vetor — testado
 *     na investigação desta tarefa, um mock normalizado em L2 fica com a
 *     mesma forma estatística superficial de um real; a proveniência tem
 *     que vir de fora do vetor).
 *   - `embedding_model <> EMBEDDING_MODEL_NAME`: foi semeada com um modelo
 *     que não é mais o vigente (cenário de troca de modelo, Regra 20).
 */
async function buscarPendentes(admin: SupabaseClient): Promise<AlimentoPendente[]> {
  let query = admin
    .from('alimentos_referencia')
    .select('id, nome_taco, aliases')
    .or(`embedding.is.null,embedding_model.is.null,embedding_model.neq.${EMBEDDING_MODEL_NAME}`)
    .order('nome_taco', { ascending: true });

  if (LIMITE_TESTE !== undefined) {
    query = query.limit(LIMITE_TESTE);
  }

  const { data, error } = await query;
  if (error) {
    if (error.message.includes('embedding_model')) {
      throw new Error(
        `Coluna alimentos_referencia.embedding_model não existe ainda. Rode a migration ` +
          `20260807200000_embeddings_reais_provenance_hnsw.sql primeiro (supabase db push).\n\nErro original: ${error.message}`,
      );
    }
    throw new Error(`Erro ao buscar alimentos pendentes: ${error.message}`);
  }
  return data ?? [];
}

/**
 * Gera um embedding via Gemini, com retry/backoff exponencial em 429
 * (rate limit) e 5xx (instabilidade transitória do lado do Google) — Regra
 * 21: uma corrida de ~625+ chamadas não pode morrer na primeira soneca da
 * API. Erros 4xx que não sejam 429 (ex.: 400 texto inválido, 404 modelo
 * errado) NÃO são retentados — são bug de configuração, retry não resolve.
 */
async function gerarEmbeddingComRetry(
  texto: string,
  apiKey: string,
  contextoLog: string,
): Promise<number[]> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${EMBEDDING_MODEL_NAME}:embedContent`;

  for (let tentativa = 1; tentativa <= MAX_TENTATIVAS; tentativa++) {
    const response = await fetch(`${url}?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: `models/${EMBEDDING_MODEL_NAME}`,
        content: { parts: [{ text: texto }] },
        // Par assimétrico com o lado de busca (search-food/index.ts,
        // extract-metric-photo/index.ts usam RETRIEVAL_QUERY) — ver nota de
        // cabeçalho e migration 20260729120000_create_match_alimentos.sql.
        taskType: 'RETRIEVAL_DOCUMENT',
        outputDimensionality: DIMENSOES_EMBEDDING,
      }),
    });

    if (response.ok) {
      const data = (await response.json()) as { embedding?: { values: number[] } };
      const values = data.embedding?.values;
      if (!values || values.length !== DIMENSOES_EMBEDDING) {
        throw new Error(
          `${contextoLog}: embedding com formato inesperado (esperava ${DIMENSOES_EMBEDDING} dims, recebeu ${values?.length ?? 0}).`,
        );
      }
      // outputDimensionality (Matryoshka) não devolve o vetor já normalizado
      // — mesma correção de search-food/index.ts/extract-metric-photo.
      const norma = Math.sqrt(values.reduce((soma, v) => soma + v * v, 0));
      return norma === 0 ? values : values.map((v) => v / norma);
    }

    const retentavel = response.status === 429 || response.status >= 500;
    const corpoErro = await response.text();

    if (!retentavel || tentativa === MAX_TENTATIVAS) {
      throw new Error(
        `${contextoLog}: Gemini embedContent falhou (HTTP ${response.status}, tentativa ${tentativa}/${MAX_TENTATIVAS}): ${corpoErro}`,
      );
    }

    const backoffMs = 2_000 * 2 ** (tentativa - 1); // 2s, 4s, 8s, 16s
    console.warn(
      `  ⚠️  ${contextoLog}: HTTP ${response.status} (tentativa ${tentativa}/${MAX_TENTATIVAS}) — ` +
        `retentando em ${backoffMs / 1000}s...`,
    );
    await delay(backoffMs);
  }

  // Inalcançável (o for sempre retorna ou lança), só pra satisfazer o TypeScript.
  throw new Error(`${contextoLog}: esgotou tentativas sem sucesso nem erro explícito.`);
}

/**
 * Grava UM embedding por `UPDATE` (não `upsert`).
 *
 * TENTATIVA INICIAL (descartada, documentada aqui para quem for mexer de
 * novo): `upsert` em lote parecia a otimização óbvia — 1 request de rede
 * para N linhas em vez de N requests. Falha na prática: `upsert` do
 * PostgREST vira `INSERT ... ON CONFLICT (id) DO UPDATE`, e o Postgres
 * valida as constraints NOT NULL da linha de INSERT ANTES de checar o
 * conflito — mesmo a linha já existindo e o resultado final sendo só um
 * UPDATE. Como o payload aqui só tem `id/embedding/embedding_model` (não
 * `nome_taco`/`calorias_kcal_100g`/etc., todos NOT NULL no schema), todo
 * upsert falhava com "null value in column nome_taco violates not-null
 * constraint" — confirmado contra o banco real durante esta tarefa.
 *
 * `UPDATE` puro não tem esse problema (não constrói uma linha candidata de
 * INSERT). O verdadeiro gargalo de performance aqui (Regra 21) é a API do
 * Gemini, rate-limitada por `DELAY_ENTRE_CHAMADAS_MS` — o UPDATE em si, sem
 * esse delay, é uma escrita trivial para o Postgres neste volume (~625
 * linhas); não precisa de batching para não estourar tempo.
 *
 * `embedding` vai como string "[v1,v2,...]" (não array cru): os dois
 * formatos foram testados contra o banco real nesta tarefa e ambos
 * funcionam nesta instância, mas a string é a técnica já documentada em
 * search-food/index.ts para o parâmetro de RPC — mantém uma convenção só.
 */
async function gravarEmbedding(admin: SupabaseClient, item: EmbeddingParaGravar): Promise<void> {
  const { error } = await admin
    .from('alimentos_referencia')
    .update({ embedding: item.embedding, embedding_model: item.embedding_model })
    .eq('id', item.id);
  if (error) {
    throw new Error(`Erro ao gravar embedding de ${item.id}: ${error.message}`);
  }
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const geminiApiKey = requireEnv('GEMINI_API_KEY');

  console.log('🚀 N20 — Re-seed de embeddings reais (alimentos_referencia)\n');
  console.log(`   Modelo: ${EMBEDDING_MODEL_NAME} (EMBEDDING_MODEL_NAME${process.env.EMBEDDING_MODEL_NAME ? '' : ', padrão — secret não configurada localmente'})`);
  console.log(`   Rate limit: ${RPM_LIMIT} req/min (${DELAY_ENTRE_CHAMADAS_MS}ms entre chamadas)`);
  if (LIMITE_TESTE !== undefined) {
    console.log(`   ⚠️  MODO TESTE: limitado a ${LIMITE_TESTE} linha(s) (EMBEDDING_SEED_LIMIT)`);
  }
  console.log('');

  const pendentes = await buscarPendentes(admin);
  if (pendentes.length === 0) {
    console.log('✅ Nenhuma linha pendente — todo o catálogo já está no modelo vigente.');
    return;
  }
  console.log(`📊 ${pendentes.length} alimento(s) para (re)semear (mock + desatualizados + nunca semeados)\n`);

  let processados = 0;
  let falhas = 0;
  const inicio = Date.now();

  for (const alimento of pendentes) {
    const textoBase = [alimento.nome_taco, ...alimento.aliases].filter(Boolean).join(' ');
    const contexto = `[${processados + 1}/${pendentes.length}] "${alimento.nome_taco}"`;

    try {
      const embedding = await gerarEmbeddingComRetry(textoBase, geminiApiKey, contexto);
      await gravarEmbedding(admin, {
        id: alimento.id,
        embedding: JSON.stringify(embedding),
        embedding_model: EMBEDDING_MODEL_NAME,
      });
      if ((processados + 1) % 25 === 0 || processados + 1 === pendentes.length) {
        console.log(`  💾 ${processados + 1}/${pendentes.length} gravados (${falhas} falha(s) até agora)`);
      }
    } catch (err) {
      falhas++;
      console.error(`  ❌ ${contexto}: ${err instanceof Error ? err.message : err}`);
      // Não interrompe a corrida inteira por 1 alimento problemático (Regra
      // 21 — sem crash no meio do processo); a linha simplesmente continua
      // pendente (embedding_model não foi carimbado) e será pega de novo na
      // próxima execução do script.
    }

    processados++;

    if (processados < pendentes.length) {
      await delay(DELAY_ENTRE_CHAMADAS_MS);
    }
  }

  const duracaoS = ((Date.now() - inicio) / 1000).toFixed(1);
  console.log(`\n🎉 Concluído em ${duracaoS}s`);
  console.log(`   Processados: ${processados - falhas}/${pendentes.length}`);
  console.log(`   Falhas: ${falhas}`);
  console.log(`   Modelo: ${EMBEDDING_MODEL_NAME} (${DIMENSOES_EMBEDDING} dimensões, L2-normalizado, RETRIEVAL_DOCUMENT)`);

  if (falhas > 0) {
    console.log(`\n⚠️  ${falhas} alimento(s) continuam pendentes — rode o script de novo para retentar só esses.`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error('\n❌ Erro fatal durante a geração de embeddings:', err instanceof Error ? err.message : err);
  process.exit(1);
});
