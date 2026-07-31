// search-food — "Cérebro da Busca" (Nutrição Semântica, Adendo v5.1 §A.3/§C.3).
//
// Recebe um termo de busca livre (`{"query": "..."}`), gera o embedding dele
// via Gemini (text-embedding-004) e devolve os alimentos de `alimentos_referencia`
// mais próximos por similaridade de cosseno, consultando a RPC `match_alimentos`
// (20260729120000_create_match_alimentos.sql).
//
// Simétrico com scripts/seed_food_embeddings.ts, que gera o embedding do
// CATÁLOGO com o mesmo modelo: aqui, o embedding do TERMO DE BUSCA usa
// a mesma API — os dois lados geram embeddings comparáveis para busca
// de similaridade de cosseno eficaz.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MODELO_EMBEDDING = 'text-embedding-004';
const GEMINI_EMBED_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODELO_EMBEDDING}:embedContent`;
const DIMENSOES_EMBEDDING = 768;

// Fixos no servidor, não configuráveis pelo cliente: um match_count alto
// pedido pelo chamador custaria uma consulta cara sem benefício de UX (a
// tela só mostra um punhado de sugestões); um threshold baixo devolveria
// "sinônimos" sem relação nenhuma. Ajustar estes dois valores é decisão de
// produto, não de payload de requisição.
//
// CALIBRADO (30/jul/2026) contra o banco real — mesmo valor e mesma
// justificativa de BUSCA_SEMANTICA_THRESHOLD em
// extract-metric-photo/index.ts (ver RELATÓRIO DE FIM DE TAREFA daquela
// tarefa): 0.5 deixava passar pratos fora do catálogo TACO (ex.: "sushi",
// "pizza") como se fossem casamentos válidos. Os dois endpoints têm que
// concordar — o mesmo termo não pode se comportar diferente dependendo de
// por onde entrou. Se um dia existir uma tela de busca com humano
// revisando a lista (ao contrário do fallback automático de
// extract-metric-photo), pode valer reavaliar um valor mais permissivo
// aqui especificamente — não fiz essa distinção agora para não deixar os
// dois lugares divergentes sem necessidade comprovada.
const MATCH_THRESHOLD_PADRAO = 0.68;
const MATCH_COUNT_PADRAO = 5;

const QUERY_MAX_LEN = 200;

/**
 * Normaliza um termo de busca para consulta no cache.
 * Mesmo normalizador usado em alimentos_referencia/aliases: lowercase + sem acentos.
 */
function normalizarTermoBusca(termo: string): string {
  return termo
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, ''); // Remove diacríticos
}

class ErroHttp extends Error {
  constructor(readonly status: number, mensagem: string) {
    super(mensagem);
  }
}

interface SearchFoodRequest {
  query: string;
}

export function validarRequisicao(corpo: unknown): SearchFoodRequest {
  if (typeof corpo !== 'object' || corpo === null) {
    throw new ErroHttp(400, 'Corpo da requisição deve ser um objeto JSON.');
  }
  const { query } = corpo as Record<string, unknown>;
  if (typeof query !== 'string' || query.trim().length === 0) {
    throw new ErroHttp(400, '"query" é obrigatório e deve ser um texto não vazio.');
  }
  const queryLimpa = query.trim();
  if (queryLimpa.length > QUERY_MAX_LEN) {
    throw new ErroHttp(400, `"query" excede o tamanho máximo de ${QUERY_MAX_LEN} caracteres.`);
  }
  return { query: queryLimpa };
}

/** Reescala para norma L2 = 1 — ver nota de cabeçalho: outputDimensionality (Matryoshka) não devolve o vetor já normalizado. */
function normalizarL2(values: number[]): number[] {
  const norma = Math.sqrt(values.reduce((soma, v) => soma + v * v, 0));
  if (norma === 0) return values;
  return values.map((v) => v / norma);
}

export type ChamadorEmbedding = (texto: string) => Promise<number[]>;

/// Assina a chamada real ao Gemini, injetável para teste — assim
/// index_test.ts exercita todo o handler sem tocar a rede nem precisar de
/// GEMINI_API_KEY (mesma filosofia do `chamarGemini` falso de
/// extract-metric-photo/index.ts).
export function criarChamadorEmbeddingReal(apiKey: string): ChamadorEmbedding {
  return async (texto: string) => {
    const resposta = await fetch(`${GEMINI_EMBED_ENDPOINT}?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: `models/${MODELO_EMBEDDING}`,
        content: { parts: [{ text: texto }] },
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

// ============================================================================
// Contrato mínimo do cliente Supabase que este handler usa — mesmo padrão de
// manage-professional-link/garmin-gateway/calculate-recovery-mode: permite ao
// index_test.ts injetar um admin falso em memória sem simular a SDK inteira.
// ============================================================================
type ErroSupabase = { message: string } | null;

export interface AlimentoEncontrado {
  id: string;
  nome_taco: string;
  aliases: string[];
  calorias_kcal_100g: number;
  proteinas_g_100g: number;
  carboidratos_g_100g: number;
  gorduras_g_100g: number;
  similarity: number;
}

export interface SupabaseAdminLike {
  auth: {
    getUser(jwt: string): Promise<{
      data: { user: { id: string } | null };
      error: ErroSupabase;
    }>;
  };
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): Promise<{ data: unknown[] | null; error: ErroSupabase }>;
    };
    insert(data: unknown): Promise<{ data: unknown | null; error: ErroSupabase }>;
  };
  rpc(
    fn: string,
    params: Record<string, unknown>,
  ): Promise<{ data: AlimentoEncontrado[] | null; error: ErroSupabase }>;
}

interface HandlerDeps {
  supabaseAdmin?: SupabaseAdminLike;
  chamarEmbedding?: ChamadorEmbedding;
}

export function createHandler(deps: HandlerDeps = {}) {
  return async function handleRequest(req: Request): Promise<Response> {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: CORS_HEADERS });
    }
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Método não suportado — use POST.' }, 405);
    }

    let corpoBruto: unknown;
    try {
      corpoBruto = await req.json();
    } catch {
      return jsonResponse({ error: 'JSON inválido no corpo da requisição.' }, 400);
    }

    let requisicao: SearchFoodRequest;
    try {
      requisicao = validarRequisicao(corpoBruto);
    } catch (erro) {
      if (erro instanceof ErroHttp) {
        return jsonResponse({ error: erro.message }, erro.status);
      }
      return jsonResponse({ error: mensagemDeErro(erro) }, 400);
    }

    const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!jwt) {
      return jsonResponse({ error: 'Token de autenticação ausente.' }, 401);
    }

    let admin: SupabaseAdminLike;
    if (deps.supabaseAdmin) {
      admin = deps.supabaseAdmin;
    } else {
      const supabaseUrl = Deno.env.get('SUPABASE_URL');
      const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      if (!supabaseUrl || !serviceRoleKey) {
        console.error('search-food: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY não configuradas.');
        return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
      }
      // A service role vive só aqui dentro, no processo da Edge Function.
      admin = createClient(supabaseUrl, serviceRoleKey) as unknown as SupabaseAdminLike;
    }

    const { data: userData, error: erroAuth } = await admin.auth.getUser(jwt);
    if (erroAuth || !userData.user) {
      return jsonResponse({ error: 'Sessão inválida ou expirada.' }, 401);
    }

    try {
      const termoNormalizado = normalizarTermoBusca(requisicao.query);

      // Etapa 1: Consultar cache de sinônimos
      console.log(`🔍 Buscando "${requisicao.query}" no cache...`);
      const { data: cacheData, error: erroCache } = await admin
        .from('cache_sinonimos_alimentos')
        .select('alimento_id, contagem_hits')
        .eq('termo_buscado', termoNormalizado);

      if (erroCache) {
        console.warn(`⚠️ Erro ao consultar cache: ${erroCache.message} — continuando com busca semântica`);
      } else if (cacheData && cacheData.length > 0) {
        // Cache hit! Buscar o alimento cached
        const { alimento_id, contagem_hits } = cacheData[0] as {
          alimento_id: string;
          contagem_hits: number;
        };

        console.log(`✅ Cache hit! termo="${termoNormalizado}" → alimento="${alimento_id}" (hits=${contagem_hits})`);

        // Buscar os dados completos do alimento para retornar
        const { data: alimentoData, error: erroAlimento } = await admin
          .from('alimentos_referencia')
          .select(
            'id, nome_taco, aliases, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g',
          )
          .eq('id', alimento_id);

        if (!erroAlimento && alimentoData && alimentoData.length > 0) {
          const alimento = alimentoData[0] as AlimentoEncontrado & { similarity?: number };
          // Adicionar similaridade como 1.0 para cache hits (matches perfeitos)
          alimento.similarity = 1.0;

          // Atualizar contador de hits assincronamente (não bloqueia resposta)
          admin
            .from('cache_sinonimos_alimentos')
            .insert([
              {
                termo_buscado: termoNormalizado,
                alimento_id,
                contagem_hits: contagem_hits + 1,
                ultimo_hit_em: new Date().toISOString(),
              },
            ])
            .catch((err) => console.warn(`⚠️ Erro ao atualizar contador de cache hits: ${err}`));

          return jsonResponse({ results: [alimento], cache_hit: true }, 200);
        }
      }

      // Etapa 2: Cache miss — gerar embedding e buscar
      console.log(`📝 Cache miss para "${requisicao.query}" — gerando embedding...`);

      const chamarEmbedding =
        deps.chamarEmbedding ??
        (() => {
          const apiKey = Deno.env.get('GEMINI_API_KEY');
          if (!apiKey) {
            throw new ErroHttp(500, 'GEMINI_API_KEY não configurada no servidor.');
          }
          return criarChamadorEmbeddingReal(apiKey);
        })();

      const vetor = await chamarEmbedding(requisicao.query);

      // `vector` não é um array nativo do Postgres — PostgREST não converte
      // um array JSON puro para ele. A string "[v1,v2,...]" (exatamente o
      // que JSON.stringify de um array de números produz) funciona porque
      // pgvector aceita esse texto como entrada literal — mesma técnica já
      // confirmada contra o banco real em scripts/seed_food_embeddings.ts
      // (lá, para UPDATE de coluna; aqui, para parâmetro de RPC).
      const { data, error } = await admin.rpc('match_alimentos', {
        query_embedding: JSON.stringify(vetor),
        match_threshold: MATCH_THRESHOLD_PADRAO,
        match_count: MATCH_COUNT_PADRAO,
      });
      if (error) {
        throw new Error(`Erro ao consultar match_alimentos: ${error.message}`);
      }

      // Etapa 3: Gravar primeiro resultado no cache para futuras buscas
      if (data && data.length > 0) {
        const primeiroResultado = data[0];
        console.log(`💾 Cachando resultado: "${requisicao.query}" → "${primeiroResultado.nome_taco}"`);

        await admin.from('cache_sinonimos_alimentos').insert([
          {
            termo_buscado: termoNormalizado,
            alimento_id: primeiroResultado.id,
            contagem_hits: 1,
          },
        ]);
      }

      return jsonResponse({ results: data ?? [], cache_hit: false }, 200);
    } catch (erro) {
      if (erro instanceof ErroHttp) {
        return jsonResponse({ error: erro.message }, erro.status);
      }
      console.error('search-food:', mensagemDeErro(erro));
      return jsonResponse({ error: 'Erro ao buscar alimentos.' }, 500);
    }
  };
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
