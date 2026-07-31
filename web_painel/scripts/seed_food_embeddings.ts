/**
 * F46 — Geração de Embeddings Semânticos para Alimentos (Nutrição Semântica, Adendo v5.1).
 *
 * Popula a coluna `embedding` (vector(768)) em `alimentos_referencia` com vetores
 * gerados pela API de embeddings do Gemini (text-embedding-004).
 *
 * CARACTERÍSTICAS:
 * - Busca apenas registros onde embedding IS NULL (idempotência)
 * - Batch processing: 20 alimentos por lote com delay de 1s entre lotes (rate limiting)
 * - API: Gemini text-embedding-004 (768 dimensões)
 * - Usa GEMINI_API_KEY e SUPABASE_SERVICE_ROLE_KEY do .env.local
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Confirme que .env.local tem GEMINI_API_KEY (de Google AI Studio) + SUPABASE_SERVICE_ROLE_KEY
 *   3. npm run seed:food-embeddings
 *      ou: npx tsx scripts/seed_food_embeddings.ts
 *
 * Custos de API:
 * - Gemini text-embedding-004: Gratuito (sem cobrança)
 * - Supabase: updates simples via PostgREST (uso normal, sem custos extras)
 */
import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

interface AlimentoSemEmbedding {
  id: string;
  nome_taco: string;
  aliases: string[];
}

interface EmbeddingResponse {
  embedding: number[];
  model: string;
  index: number;
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Variável de ambiente ${name} não configurada — veja .env.local`,
    );
  }
  return value;
}

function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

/**
 * Busca todos os alimentos sem embedding ainda.
 */
async function buscarAlimentosSemEmbedding(
  admin: SupabaseClient,
): Promise<AlimentoSemEmbedding[]> {
  const { data, error } = await admin
    .from('alimentos_referencia')
    .select('id, nome_taco, aliases')
    .is('embedding', null);

  if (error) {
    throw new Error(`Erro ao buscar alimentos sem embedding: ${error.message}`);
  }

  return data ?? [];
}

/**
 * Gera um embedding semântico via API Gemini text-embedding-004.
 * Retorna um vetor de 768 dimensões normalizado em L2.
 */
async function gerarEmbeddingGemini(
  texto: string,
  geminiApiKey: string,
): Promise<number[]> {
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent';

  const response = await fetch(`${url}?key=${geminiApiKey}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'models/text-embedding-004',
      content: {
        parts: [
          {
            text: texto,
          },
        ],
      },
    }),
  });

  if (!response.ok) {
    const errorData = await response.text();
    throw new Error(
      `Erro da API Gemini (HTTP ${response.status}): ${errorData}`,
    );
  }

  const data = (await response.json()) as {
    embedding?: { values: number[] };
  };

  if (!data.embedding?.values) {
    throw new Error('Resposta do Gemini sem campo embedding.values');
  }

  const values = data.embedding.values;

  // Normalizar para L2 (norma = 1)
  const norma = Math.sqrt(values.reduce((soma, v) => soma + v * v, 0));
  if (norma === 0) return values;

  return values.map((v) => v / norma);
}

/**
 * Processa um lote de alimentos, gerando embeddings e atualizando o Supabase.
 */
async function processarLote(
  admin: SupabaseClient,
  alimentos: AlimentoSemEmbedding[],
  geminiApiKey: string,
): Promise<void> {
  const embeddings: Array<{
    id: string;
    embedding: number[];
  }> = [];

  for (const alimento of alimentos) {
    try {
      // Preparar texto para embedding: nome + aliases
      const textoBase = [alimento.nome_taco, ...alimento.aliases]
        .filter((t) => t)
        .join(' ');

      console.log(`  🧮 Gerando embedding para "${alimento.nome_taco}"...`);

      const embedding = await gerarEmbeddingGemini(textoBase, geminiApiKey);
      embeddings.push({
        id: alimento.id,
        embedding,
      });

      console.log(`    ✅ Embedding gerado (${embedding.length} dimensões)`);

      // Pequeno delay entre requisições mesmo dentro do lote (respeita rate limits)
      await new Promise((resolve) => setTimeout(resolve, 100));
    } catch (err) {
      console.error(
        `    ❌ Erro ao gerar embedding para "${alimento.nome_taco}": ${err instanceof Error ? err.message : err}`,
      );
      throw err;
    }
  }

  // Atualizar Supabase com todos os embeddings do lote
  console.log(`  💾 Atualizando Supabase com ${embeddings.length} embeddings...`);

  for (const { id, embedding } of embeddings) {
    const { error } = await admin
      .from('alimentos_referencia')
      .update({ embedding })
      .eq('id', id);

    if (error) {
      throw new Error(
        `Erro ao atualizar embedding do alimento ${id}: ${error.message}`,
      );
    }
  }

  console.log(`  ✅ Lote atualizado com sucesso`);
}

/**
 * Aguarda um tempo específico (para delay entre lotes).
 */
async function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const geminiApiKey = requireEnv('GEMINI_API_KEY');

  console.log('🚀 Iniciando geração de embeddings para alimentos...\n');

  try {
    // 1. Buscar alimentos sem embedding
    console.log('🔍 Buscando alimentos sem embedding...');
    const alimentosSemEmbedding = await buscarAlimentosSemEmbedding(admin);

    if (alimentosSemEmbedding.length === 0) {
      console.log('✅ Todos os alimentos já possuem embeddings.');
      return;
    }

    console.log(`\n📊 Encontrados ${alimentosSemEmbedding.length} alimentos para processar\n`);

    // 2. Processar em lotes com throttling
    const tamanheLote = 20;
    const delayEntreLotes = 1000; // 1 segundo entre lotes

    for (let i = 0; i < alimentosSemEmbedding.length; i += tamanheLote) {
      const lote = alimentosSemEmbedding.slice(
        i,
        Math.min(i + tamanheLote, alimentosSemEmbedding.length),
      );

      const numeroLote = Math.floor(i / tamanheLote) + 1;
      const totalLotes = Math.ceil(alimentosSemEmbedding.length / tamanheLote);

      console.log(
        `\n📦 Processando lote ${numeroLote}/${totalLotes} (${lote.length} alimentos)...`,
      );

      try {
        await processarLote(admin, lote, geminiApiKey);
      } catch (err) {
        console.error(`\n❌ Erro ao processar lote ${numeroLote}:`, err);
        throw err;
      }

      // Delay entre lotes para respeitar rate limits
      if (i + tamanheLote < alimentosSemEmbedding.length) {
        console.log(`⏳ Aguardando ${delayEntreLotes}ms antes do próximo lote...`);
        await delay(delayEntreLotes);
      }
    }

    console.log('\n🎉 Geração de embeddings concluída com sucesso!');
    console.log(`\n📊 Resumo:`);
    console.log(`   - Alimentos processados: ${alimentosSemEmbedding.length}`);
    console.log(`   - Modelo Gemini: text-embedding-004`);
    console.log(`   - Dimensões por embedding: 768 (L2-normalizado)`);
    console.log(`   - Lotes processados: ${Math.ceil(alimentosSemEmbedding.length / tamanheLote)}`);
  } catch (err) {
    console.error(
      '\n❌ Erro durante a geração de embeddings:',
      err instanceof Error ? err.message : err,
    );
    process.exit(1);
  }
}

main();
