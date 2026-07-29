/**
 * Semeadeira de Embeddings — Nutrição Semântica (Adendo v5.1 §A.3/§C.3).
 *
 * Popula `alimentos_referencia.embedding` (coluna `vector(768)`, criada em
 * 20260727120000_setup_nutricao_semantica.sql, nula até aqui) para todo
 * alimento que ainda não tem embedding: busca `nome_taco` + `aliases`,
 * gera o vetor via Gemini e grava de volta na mesma linha. Esse embedding é
 * o que vai permitir casar sinônimos/gírias que o casamento exato/substring
 * por `aliases` (supabase/functions/extract-metric-photo/index.ts) não
 * cobre — a busca por similaridade em si (Edge Function que consome este
 * embedding) é trabalho de uma tarefa separada; este script só faz a
 * ingestão.
 *
 * BUG CORRIGIDO (29/jul/2026): rodando pela primeira vez, `text-embedding-004`
 * devolveu 404 ("is not found for API version v1beta, or is not supported
 * for embedContent"). Confirmado chamando ListModels contra a própria chave
 * do projeto: o modelo NEM APARECE na lista — foi desativado por completo
 * (mesma classe de bug já documentada em
 * extract-metric-photo/index.ts para 'gemini-2.5-flash'). Os modelos de
 * embedding disponíveis hoje são `gemini-embedding-001` (estável, usado
 * aqui), `gemini-embedding-2-preview` e `gemini-embedding-2`. Três
 * diferenças em relação ao que este script tinha antes:
 *
 *   1. Endpoint: nenhum dos modelos atuais lista `batchEmbedContents`
 *      (síncrono) em `supportedGenerationMethods` — só `embedContent`
 *      (um texto por chamada) e `asyncBatchEmbedContent` (fluxo
 *      assíncrono, cria um job e exige polling — infraestrutura extra que
 *      não compensa no volume deste catálogo, algumas dezenas/centenas de
 *      itens, não milhões). Por isso o script agora chama `embedContent`
 *      uma vez por alimento, sequencialmente, com delay entre cada chamada
 *      — a noção de "lote" (`TAMANHO_LOTE`) continua existindo só como
 *      agrupamento de log/checkpoint, não como uma única chamada HTTP.
 *   2. Dimensão: `gemini-embedding-001` devolve 3072 valores por padrão —
 *      incompatível com a coluna `vector(768)`. `outputDimensionality: 768`
 *      no corpo da requisição trunca pro tamanho certo (Matryoshka
 *      Representation Learning — o modelo foi treinado pra isso, não é um
 *      corte arbitrário).
 *   3. Normalização: confirmado testando contra a API de verdade — um
 *      embedding truncado por `outputDimensionality` NÃO sai normalizado
 *      (norma L2 ~0.59, não 1.0). Documentação do próprio Google recomenda
 *      normalizar antes de guardar; feito em `normalizarL2`. Sem isso, o
 *      vetor ainda funcionaria para busca por distância de cosseno (`<=>`,
 *      que já é invariante a escala), mas ficaria incorreto se algum dia
 *      alguém trocar para `<->`/`<#>` — normalizar na ingestão custa quase
 *      nada e elimina essa pegadinha de vez.
 *
 * REST puro (`fetch` direto para `generativelanguage.googleapis.com`), sem
 * SDK `@google/genai`: mesmo padrão que `extract-metric-photo/index.ts` já
 * usa para o resto do pipeline de IA deste projeto.
 *
 * `taskType: 'RETRIEVAL_DOCUMENT'` em cada embedding gerado aqui — é o modo
 * assimétrico do Gemini para o lado "catálogo" de uma busca por
 * similaridade. Quem for construir a Edge Function que consulta este vetor
 * (pendência, ver RELATÓRIO) precisa gerar o embedding do termo de busca do
 * usuário com `taskType: 'RETRIEVAL_QUERY'` — não `RETRIEVAL_DOCUMENT` — ou
 * os dois espaços vetoriais não ficam comparáveis.
 *
 * Idempotente por construção: só busca linhas com `embedding IS NULL`, sem
 * nenhum estado externo de progresso — rodar de novo depois de uma falha
 * simplesmente retoma dos alimentos que ainda não têm vetor. Cada alimento
 * é gravado assim que seu próprio embedding chega (não espera o lote
 * inteiro terminar), então uma falha no meio de um lote não descarta o que
 * já tinha sido processado com sucesso antes dela.
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. No mesmo `.env` que já tem VITE_SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY
 *      (ver scripts/seed_cloud.ts), adicione GEMINI_API_KEY — a mesma chave
 *      já configurada como secret da Edge Function `extract-metric-photo`
 *      (Google AI Studio). NUNCA prefixe com VITE_ e nunca commite o valor.
 *   3. npm run seed:food-embeddings
 */
import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const MODELO_EMBEDDING = 'gemini-embedding-001';
const GEMINI_EMBED_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODELO_EMBEDDING}:embedContent`;
const DIMENSOES_ESPERADAS = 768;

// "Lote" aqui é só agrupamento de log/checkpoint — cada alimento vira uma
// chamada HTTP própria (embedContent não tem variante síncrona em lote, ver
// nota de correção no cabeçalho), então quem controla o rate limit de
// verdade é DELAY_ENTRE_ITENS_MS.
const TAMANHO_LOTE = 20;
const DELAY_ENTRE_ITENS_MS = 1000;
const DELAY_ENTRE_LOTES_MS = 2000;

interface AlimentoPendente {
  id: string;
  nome_taco: string;
  aliases: string[];
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Variável de ambiente ${name} não configurada — veja as instruções no topo de scripts/seed_food_embeddings.ts.`,
    );
  }
  return value;
}

/** Mesma lógica de `seed_cloud.ts`: VITE_SUPABASE_URL no .env já vem com `/rest/v1/`; a Admin API/RPC precisa só da origem. */
function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Texto que vira o embedding — combina o nome canônico com os sinônimos já cadastrados, para o vetor carregar o significado de todas as formas conhecidas de se referir ao alimento, não só o nome oficial da TACO. */
function construirTextoEmbedding(alimento: AlimentoPendente): string {
  const sinonimos = (alimento.aliases ?? []).filter((a) => a.trim().length > 0);
  return sinonimos.length > 0
    ? `${alimento.nome_taco} (também chamado de: ${sinonimos.join(', ')})`
    : alimento.nome_taco;
}

/** Reescala para norma L2 = 1 — necessário porque `outputDimensionality` (Matryoshka) não devolve o vetor já normalizado (ver nota de correção no cabeçalho). */
function normalizarL2(values: number[]): number[] {
  const norma = Math.sqrt(values.reduce((soma, v) => soma + v * v, 0));
  if (norma === 0) return values;
  return values.map((v) => v / norma);
}

async function contarPendentes(admin: SupabaseClient): Promise<number> {
  const { count, error } = await admin
    .from('alimentos_referencia')
    .select('id', { count: 'exact', head: true })
    .is('embedding', null);
  if (error) throw new Error(`count alimentos_referencia: ${error.message}`);
  return count ?? 0;
}

async function buscarLotePendente(admin: SupabaseClient, limite: number): Promise<AlimentoPendente[]> {
  const { data, error } = await admin
    .from('alimentos_referencia')
    .select('id, nome_taco, aliases')
    .is('embedding', null)
    .limit(limite);
  if (error) throw new Error(`select alimentos_referencia: ${error.message}`);
  return data ?? [];
}

async function gerarEmbeddingParaAlimento(apiKey: string, alimento: AlimentoPendente): Promise<number[]> {
  const resposta = await fetch(`${GEMINI_EMBED_ENDPOINT}?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      content: { parts: [{ text: construirTextoEmbedding(alimento) }] },
      taskType: 'RETRIEVAL_DOCUMENT',
      outputDimensionality: DIMENSOES_ESPERADAS,
    }),
  });

  if (!resposta.ok) {
    const corpoErro = await resposta.text();
    throw new Error(`Gemini embedContent falhou para "${alimento.nome_taco}" (HTTP ${resposta.status}): ${corpoErro}`);
  }

  const json = (await resposta.json()) as { embedding?: { values: number[] } };
  const values = json.embedding?.values;
  if (!values) {
    throw new Error(`Resposta do Gemini sem "embedding.values" para "${alimento.nome_taco}": ${JSON.stringify(json)}`);
  }
  if (values.length !== DIMENSOES_ESPERADAS) {
    throw new Error(
      `Embedding de "${alimento.nome_taco}" veio com ${values.length} dimensões, esperado ${DIMENSOES_ESPERADAS}.`,
    );
  }

  return normalizarL2(values);
}

/**
 * `vector` não é um tipo array nativo do Postgres — o PostgREST não sabe
 * convertê-lo a partir de um array JSON puro. Enviar a string
 * `"[v1,v2,...]"` (é exatamente isso que `JSON.stringify` de um array de
 * números produz) funciona porque pgvector aceita esse texto como entrada
 * literal (`'[1,2,3]'::vector`) — abordagem documentada pelo próprio
 * Supabase para gravar vetores via supabase-js.
 */
async function gravarEmbedding(admin: SupabaseClient, id: string, values: number[]): Promise<void> {
  const { error } = await admin
    .from('alimentos_referencia')
    .update({ embedding: JSON.stringify(values) })
    .eq('id', id);
  if (error) throw new Error(`update alimentos_referencia (${id}): ${error.message}`);
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const geminiApiKey = requireEnv('GEMINI_API_KEY');

  const total = await contarPendentes(admin);
  if (total === 0) {
    console.log('Nenhum alimento pendente — todos já têm embedding.');
    return;
  }

  const totalLotes = Math.ceil(total / TAMANHO_LOTE);
  console.log(`${total} alimento(s) sem embedding. Processando em até ${totalLotes} lote(s) de ${TAMANHO_LOTE} (modelo ${MODELO_EMBEDDING}).`);

  let processados = 0;

  for (let numeroLote = 1; numeroLote <= totalLotes; numeroLote += 1) {
    const lote = await buscarLotePendente(admin, TAMANHO_LOTE);
    if (lote.length === 0) break;

    console.log(`\nProcessando lote ${numeroLote}/${totalLotes} (${lote.length} alimento(s))...`);

    for (const [i, alimento] of lote.entries()) {
      const values = await gerarEmbeddingParaAlimento(geminiApiKey, alimento);
      await gravarEmbedding(admin, alimento.id, values);
      processados += 1;
      console.log(`  OK: "${alimento.nome_taco}" atualizado (${values.length} dimensões).`);

      const ehUltimoItemDoLote = i === lote.length - 1;
      if (!ehUltimoItemDoLote) {
        await sleep(DELAY_ENTRE_ITENS_MS);
      }
    }

    if (numeroLote < totalLotes) {
      console.log(`Aguardando ${DELAY_ENTRE_LOTES_MS}ms antes do próximo lote (rate limit do Gemini)...`);
      await sleep(DELAY_ENTRE_LOTES_MS);
    }
  }

  console.log(`\nConcluído: ${processados}/${total} alimento(s) atualizado(s) com embedding.`);
}

main().catch((err) => {
  console.error('Semeadeira de embeddings falhou:', err instanceof Error ? err.message : err);
  console.error(
    'O script é idempotente (só processa linhas com embedding IS NULL) — corrija o problema e rode de novo; ele retoma de onde parou.',
  );
  process.exit(1);
});
