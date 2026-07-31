/**
 * F46 — Geração de Embeddings Semânticos para Alimentos (Nutrição Semântica, Adendo v5.1).
 *
 * Popula a coluna `embedding` (vector(768)) em `alimentos_referencia` com vetores.
 *
 * MODO ATUAL: Fallback com mock embedding determinístico.
 * MODO FUTURO: API de embeddings do Gemini (text-embedding-gecko-multilingual) quando
 *              a chave de API tiver permissões de embeddings ativadas.
 *
 * CARACTERÍSTICAS:
 * - Busca apenas registros onde embedding IS NULL (idempotência)
 * - Batch processing: 20 alimentos por lote com delay de 1s entre lotes (rate limiting)
 * - Embedding: Determinístico baseado em hash (768 dimensões)
 * - Usa GEMINI_API_KEY e SUPABASE_SERVICE_ROLE_KEY do .env.local
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Confirme que .env.local tem GEMINI_API_KEY + SUPABASE_SERVICE_ROLE_KEY
 *   3. npm run seed:food-embeddings
 *      ou: npx tsx scripts/seed_food_embeddings.ts
 *
 * Custos de API:
 * - Versão atual (mock): Nenhum custo
 * - Versão Gemini: ~$0.0001 por 1000 embeddings (gratuito até limite)
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
 * Gera um embedding semântico determinístico para um texto.
 * MODO FALLBACK: Como a API key fornecida não tem acesso aos modelos de embeddings
 * do Gemini, usa um algoritmo hash determinístico que simula um embedding de 768 dimensões.
 *
 * Em produção, seria: text-embedding-gecko-multilingual via API Gemini.
 *
 * NOTA: Este é um mock para fins de desenvolvimento/teste. O embedding real seria
 * gerado pela API do Gemini com semantics reais, não apenas hash.
 */
async function gerarEmbeddingGemini(
  texto: string,
  geminiApiKey: string,
): Promise<number[]> {
  // Algoritmo determinístico baseado em hash para simular embedding
  // Produz um vetor de 768 dimensões com valores normalizados [0, 1)

  const embedding: number[] = [];

  // Seed baseada no texto + uma constante
  let hash = 5381;
  for (let i = 0; i < texto.length; i++) {
    hash = ((hash << 5) + hash) ^ texto.charCodeAt(i);
  }

  // Gerar 768 dimensões pseudo-aleatórias a partir do hash
  let seed = Math.abs(hash);
  for (let i = 0; i < 768; i++) {
    // Linear congruential generator para pseudo-aleatoriedade reproduzível
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    embedding.push(seed / 0x7fffffff);
  }

  // Normalizar para média ~0.5 (padrão de embeddings reais)
  const media = embedding.reduce((a, b) => a + b, 0) / embedding.length;
  const offset = 0.5 - media;

  return embedding.map((v) => {
    const normalizado = Math.max(0, Math.min(1, v + offset));
    return parseFloat(normalizado.toFixed(6));
  });
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
    console.log(`   - Modo: Mock embedding determinístico (fallback - API Gemini sem permissão)`);
    console.log(`   - Dimensões por embedding: 768`);
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
