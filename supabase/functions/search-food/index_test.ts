// Suíte de testes de search-food — Deno.test nativo + @std/assert.
//
// Rodar com:
//   deno test --allow-env --config supabase/functions/search-food/deno.json \
//     supabase/functions/search-food/index_test.ts
//
// Mesmo padrão de manage-professional-link/extract-metric-photo: um
// `supabaseAdmin` falso em memória, um `chamarEmbedding` falso (nunca toca a
// rede), e um grupo separado que stuba `fetch` global só para provar que
// `criarChamadorEmbeddingReal` monta a requisição certa (taskType/dimensão).

import { assertEquals, assertExists, assertStringIncludes } from '@std/assert';
import {
  createHandler,
  criarChamadorEmbeddingReal,
  type AlimentoEncontrado,
  type SupabaseAdminLike,
} from './index.ts';

const USUARIO = '11111111-1111-1111-1111-111111111111';
const JWT_VALIDO = 'jwt-valido';

const ARROZ: AlimentoEncontrado = {
  id: '22222222-2222-2222-2222-222222222222',
  nome_taco: 'Arroz, branco, cozido',
  aliases: ['arroz', 'arroz branco'],
  calorias_kcal_100g: 128,
  proteinas_g_100g: 2.5,
  carboidratos_g_100g: 28.1,
  gorduras_g_100g: 0.2,
  similarity: 0.91,
};

function vetorFalso(): number[] {
  return Array.from({ length: 768 }, (_, i) => (i % 7) / 10);
}

function fakeSupabaseAdmin(options: {
  usuarioAutenticado?: string | null;
  resultadosRpc?: AlimentoEncontrado[];
  erroRpc?: string;
}): {
  admin: SupabaseAdminLike;
  chamadasRpc: Array<{ fn: string; params: Record<string, unknown> }>;
  insertsCache: Array<Record<string, unknown>>;
} {
  const chamadasRpc: Array<{ fn: string; params: Record<string, unknown> }> = [];
  // BUG CORRIGIDO (N20): este fixture não implementava `.from()` — o handler
  // real já dependia dele (etapas 1/3, cache de sinônimos) desde antes desta
  // tarefa, e os testes "caminho feliz"/"RPC" quebravam com
  // `admin.from is not a function` sem que ninguém notasse porque o erro
  // caía no catch genérico e virava 500 (assertEquals comparava 500 contra
  // 200 esperado, mas a causa raiz — fixture desatualizado, não bug de
  // produto — ficava escondida). Sempre devolve cache MISS (lista vazia):
  // nenhum teste existente depende de cache HIT, e adicionar um define esse
  // comportamento explicitamente para quem escrever o próximo teste.
  const insertsCache: Array<Record<string, unknown>> = [];

  const admin: SupabaseAdminLike = {
    auth: {
      // deno-lint-ignore require-await
      async getUser(_jwt: string) {
        if (!options.usuarioAutenticado) {
          return { data: { user: null }, error: { message: 'Sessão inválida.' } };
        }
        return { data: { user: { id: options.usuarioAutenticado } }, error: null };
      },
    },
    from(_table: string) {
      return {
        select(_columns: string) {
          return {
            // deno-lint-ignore require-await
            async eq(_column: string, _value: string) {
              return { data: [], error: null };
            },
          };
        },
        // deno-lint-ignore require-await
        async insert(data: unknown) {
          insertsCache.push(...(Array.isArray(data) ? data : [data]) as Record<string, unknown>[]);
          return { data: null, error: null };
        },
      };
    },
    // deno-lint-ignore require-await
    async rpc(fn, params) {
      chamadasRpc.push({ fn, params });
      if (options.erroRpc) {
        return { data: null, error: { message: options.erroRpc } };
      }
      return { data: options.resultadosRpc ?? [], error: null };
    },
  };

  return { admin, chamadasRpc, insertsCache };
}

function requisicao(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request('http://localhost/search-food', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${JWT_VALIDO}`, ...headers },
    body: JSON.stringify(body),
  });
}

Deno.test('OPTIONS devolve 200 (preflight CORS)', async () => {
  const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
  const handler = createHandler({ supabaseAdmin: admin });

  const resposta = await handler(new Request('http://localhost/search-food', { method: 'OPTIONS' }));

  assertEquals(resposta.status, 200);
});

Deno.test('método diferente de POST/OPTIONS devolve 405', async () => {
  const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
  const handler = createHandler({ supabaseAdmin: admin });

  const resposta = await handler(new Request('http://localhost/search-food', { method: 'GET' }));

  assertEquals(resposta.status, 405);
});

Deno.test('JSON inválido no corpo devolve 400', async () => {
  const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
  const handler = createHandler({ supabaseAdmin: admin });

  const resposta = await handler(
    new Request('http://localhost/search-food', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${JWT_VALIDO}` },
      body: '{not json',
    }),
  );

  assertEquals(resposta.status, 400);
});

Deno.test('"query" ausente ou vazia devolve 400', async () => {
  const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
  const handler = createHandler({ supabaseAdmin: admin });

  const semQuery = await handler(requisicao({}));
  assertEquals(semQuery.status, 400);

  const queryVazia = await handler(requisicao({ query: '   ' }));
  assertEquals(queryVazia.status, 400);
});

Deno.test('"query" acima de 200 caracteres devolve 400', async () => {
  const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
  const handler = createHandler({ supabaseAdmin: admin });

  const resposta = await handler(requisicao({ query: 'a'.repeat(201) }));

  assertEquals(resposta.status, 400);
});

Deno.test('sem header Authorization devolve 401 sem chamar o Gemini nem o banco', async () => {
  const { admin, chamadasRpc } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
  let chamouEmbedding = false;
  const handler = createHandler({
    supabaseAdmin: admin,
    chamarEmbedding: () => {
      chamouEmbedding = true;
      return Promise.resolve(vetorFalso());
    },
  });

  const resposta = await handler(requisicao({ query: 'arroz' }, { Authorization: '' }));

  assertEquals(resposta.status, 401);
  assertEquals(chamouEmbedding, false);
  assertEquals(chamadasRpc.length, 0);
});

Deno.test('sessão inválida (getUser falha) devolve 401', async () => {
  const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: null });
  const handler = createHandler({
    supabaseAdmin: admin,
    chamarEmbedding: () => Promise.resolve(vetorFalso()),
  });

  const resposta = await handler(requisicao({ query: 'arroz' }));

  assertEquals(resposta.status, 401);
});

Deno.test('caminho feliz: devolve os resultados da RPC com status 200', async () => {
  const { admin, chamadasRpc } = fakeSupabaseAdmin({
    usuarioAutenticado: USUARIO,
    resultadosRpc: [ARROZ],
  });
  const handler = createHandler({
    supabaseAdmin: admin,
    chamarEmbedding: () => Promise.resolve(vetorFalso()),
  });

  const resposta = await handler(requisicao({ query: 'arroz branco' }));
  const corpo = await resposta.json();

  assertEquals(resposta.status, 200);
  assertEquals(corpo.results, [ARROZ]);
  assertEquals(chamadasRpc.length, 1);
  assertEquals(chamadasRpc[0].fn, 'match_alimentos');
});

Deno.test('chama match_alimentos com o embedding serializado como string (literal do pgvector)', async () => {
  const { admin, chamadasRpc } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO, resultadosRpc: [] });
  const vetor = vetorFalso();
  const handler = createHandler({
    supabaseAdmin: admin,
    chamarEmbedding: () => Promise.resolve(vetor),
  });

  await handler(requisicao({ query: 'arroz' }));

  const params = chamadasRpc[0].params;
  assertEquals(typeof params.query_embedding, 'string');
  assertEquals(params.query_embedding, JSON.stringify(vetor));
  assertEquals(typeof params.match_threshold, 'number');
  assertEquals(typeof params.match_count, 'number');
});

Deno.test('erro da RPC vira 500 genérico (não vaza mensagem do Postgres)', async () => {
  const { admin } = fakeSupabaseAdmin({
    usuarioAutenticado: USUARIO,
    erroRpc: 'relation "alimentos_referencia" does not exist',
  });
  const handler = createHandler({
    supabaseAdmin: admin,
    chamarEmbedding: () => Promise.resolve(vetorFalso()),
  });

  const resposta = await handler(requisicao({ query: 'arroz' }));
  const corpo = await resposta.json();

  assertEquals(resposta.status, 500);
  assertExists(corpo.error);
  assertEquals(String(corpo.error).includes('alimentos_referencia'), false);
});

Deno.test('GEMINI_API_KEY ausente (sem chamarEmbedding injetado) devolve 500 sem tentar rede', async () => {
  const original = Deno.env.get('GEMINI_API_KEY');
  Deno.env.delete('GEMINI_API_KEY');
  try {
    const { admin } = fakeSupabaseAdmin({ usuarioAutenticado: USUARIO });
    const handler = createHandler({ supabaseAdmin: admin });

    const resposta = await handler(requisicao({ query: 'arroz' }));

    assertEquals(resposta.status, 500);
  } finally {
    if (original !== undefined) Deno.env.set('GEMINI_API_KEY', original);
  }
});

// ============================================================================
// criarChamadorEmbeddingReal — stuba `fetch` global para provar que a
// requisição de verdade sai com o par assimétrico certo (RETRIEVAL_QUERY) e
// a dimensão truncada certa (768) — as duas coisas que, se erradas, não
// dariam erro nenhum, só busca ruim silenciosa (ver nota no cabeçalho de
// index.ts). Mesmo padrão de extract-metric-photo/index_test.ts para
// criarChamadorGeminiReal.
// ============================================================================
function stubFetch(handler: typeof fetch): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = handler;
  return () => {
    globalThis.fetch = original;
  };
}

Deno.test('criarChamadorEmbeddingReal: envia taskType RETRIEVAL_QUERY e outputDimensionality 768', async () => {
  let corpoEnviado: Record<string, unknown> = {};
  const restaurar = stubFetch(((_input: RequestInfo | URL, init?: RequestInit) => {
    corpoEnviado = JSON.parse(String(init?.body ?? '{}'));
    return Promise.resolve(
      new Response(JSON.stringify({ embedding: { values: Array(768).fill(0.1) } }), { status: 200 }),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorEmbeddingReal('fake-key');
    await chamar('arroz branco');

    assertEquals(corpoEnviado.taskType, 'RETRIEVAL_QUERY');
    assertEquals(corpoEnviado.outputDimensionality, 768);
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorEmbeddingReal: normaliza o vetor recebido para norma L2 = 1', async () => {
  const restaurar = stubFetch((() =>
    Promise.resolve(
      new Response(JSON.stringify({ embedding: { values: [3, 4, ...Array(766).fill(0)] } }), { status: 200 }),
    )) as typeof fetch);

  try {
    const chamar = criarChamadorEmbeddingReal('fake-key');
    const vetor = await chamar('teste');

    const norma = Math.sqrt(vetor.reduce((soma, v) => soma + v * v, 0));
    assertEquals(Math.abs(norma - 1) < 1e-9, true);
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorEmbeddingReal: HTTP não-200 vira ErroHttp 502 com o corpo do erro', async () => {
  const restaurar = stubFetch((() =>
    Promise.resolve(
      new Response('{"error":{"code":404,"message":"models/text-embedding-004 is not found"}}', {
        status: 404,
      }),
    )) as typeof fetch);

  try {
    const chamar = criarChamadorEmbeddingReal('fake-key');
    let erro: unknown;
    try {
      await chamar('arroz');
    } catch (e) {
      erro = e;
    }
    assertExists(erro);
    assertStringIncludes(String((erro as Error).message), '404');
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorEmbeddingReal: dimensão diferente de 768 na resposta vira erro', async () => {
  const restaurar = stubFetch((() =>
    Promise.resolve(new Response(JSON.stringify({ embedding: { values: [0.1, 0.2, 0.3] } }), { status: 200 }))) as typeof fetch);

  try {
    const chamar = criarChamadorEmbeddingReal('fake-key');
    let erro: unknown;
    try {
      await chamar('arroz');
    } catch (e) {
      erro = e;
    }
    assertExists(erro);
  } finally {
    restaurar();
  }
});
