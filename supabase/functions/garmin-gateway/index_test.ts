// Suíte de testes do Garmin Gateway — Deno.test nativo + @std/assert.
//
// Rodar com: deno test --allow-env supabase/functions/garmin-gateway/index_test.ts
//
// Sem --allow-net de propósito: nenhum teste aqui faz uma chamada de rede
// de verdade. As duas únicas superfícies de I/O externo que o handler tem
// (Supabase e Garmin) são substituídas — Supabase via injeção de
// dependência (`createHandler({ supabaseAdmin })`), Garmin via
// interceptação de `globalThis.fetch`, exatamente como pedido. --allow-env
// é necessário porque tanto o próprio `index.ts` (`Deno.env.get`) quanto os
// testes (`Deno.env.set`/`delete`, no cenário c) leem/escrevem variáveis de
// ambiente.

import { assertEquals, assertExists } from '@std/assert';
import { OAuth1Signer, percentEncode } from './oauth_helper.ts';
import { createHandler, type SupabaseAdminLike } from './index.ts';

// ============================================================================
// (a) Geração e Codificação da Assinatura OAuth 1.0a
// ============================================================================
Deno.test('Test: Geração e Codificação da Assinatura OAuth 1.0a', async (t) => {
  await t.step('buildSignatureBaseString monta a base string corretamente, com params ordenados e caracteres especiais escapados', () => {
    // Dados estáticos fixos — nonce/timestamp/chaves não são gerados
    // aleatoriamente aqui, então o resultado é 100% determinístico e pode
    // ser comparado a uma string esperada calculada à mão (RFC 5849
    // §3.4.1: METHOD & url-encoded & params-normalizados-encoded).
    const params: Record<string, string> = {
      oauth_consumer_key: 'consumerkey123',
      oauth_nonce: 'fixednonce123456',
      oauth_signature_method: 'HMAC-SHA1',
      oauth_timestamp: '1700000000',
      oauth_token: 'accesstoken456',
      oauth_version: '1.0',
      // Caractere especial de propósito (`!`) — é exatamente o tipo de
      // caractere que `encodeURIComponent` nativo NÃO escapa, mas o RFC
      // 3986 (e portanto o OAuth 1.0a) exige que seja escapado. Sem o
      // `percentEncode` customizado em oauth_helper.ts, esta base string
      // sairia errada e a assinatura calculada sobre ela nunca bateria com
      // a que a Garmin calcula do lado dela.
      workout_name: 'corrida!',
    };

    const baseString = OAuth1Signer.buildSignatureBaseString(
      'POST',
      'https://apis.garmin.com/training-api/rest/workout',
      params,
    );

    const esperado =
      'POST&https%3A%2F%2Fapis.garmin.com%2Ftraining-api%2Frest%2Fworkout&' +
      'oauth_consumer_key%3Dconsumerkey123%26' +
      'oauth_nonce%3Dfixednonce123456%26' +
      'oauth_signature_method%3DHMAC-SHA1%26' +
      'oauth_timestamp%3D1700000000%26' +
      'oauth_token%3Daccesstoken456%26' +
      'oauth_version%3D1.0%26' +
      'workout_name%3Dcorrida%2521';

    assertEquals(baseString, esperado);
  });

  await t.step('percentEncode escapa ! * \' ( ) que o encodeURIComponent nativo deixa passar (RFC 3986 vs RFC 2396)', () => {
    assertEquals(percentEncode('!'), '%21');
    assertEquals(percentEncode('*'), '%2A');
    assertEquals(percentEncode("'"), '%27');
    assertEquals(percentEncode('('), '%28');
    assertEquals(percentEncode(')'), '%29');
    assertEquals(percentEncode('corrida (intervalos)!'), 'corrida%20%28intervalos%29%21');
  });

  await t.step('sign() produz o mesmo HMAC-SHA1 que um cálculo independente via Web Crypto', async () => {
    const baseString =
      'POST&https%3A%2F%2Fapis.garmin.com%2Ftraining-api%2Frest%2Fworkout&oauth_nonce%3Dabc123';
    const consumerSecret = 'segredo-do-consumidor';
    const tokenSecret = 'segredo-do-token-do-aluno';

    const assinaturaDoCodigo = await OAuth1Signer.sign(baseString, consumerSecret, tokenSecret);

    // Cálculo de referência propositalmente independente: usa a Web
    // Crypto API diretamente aqui no teste, sem chamar nenhuma função
    // interna de oauth_helper.ts — se `OAuth1Signer.sign` tivesse um erro
    // na construção da signing key ou na chamada HMAC, este teste
    // detectaria a divergência em vez de "concordar consigo mesmo".
    const signingKeyEsperada = `${encodeURIComponent(consumerSecret)}&${encodeURIComponent(tokenSecret)}`;
    const chave = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(signingKeyEsperada),
      { name: 'HMAC', hash: 'SHA-1' },
      false,
      ['sign'],
    );
    const bufferEsperado = await crypto.subtle.sign(
      'HMAC',
      chave,
      new TextEncoder().encode(baseString),
    );
    const bytesEsperado = new Uint8Array(bufferEsperado);
    let binarioEsperado = '';
    for (const byte of bytesEsperado) binarioEsperado += String.fromCharCode(byte);
    const assinaturaEsperada = btoa(binarioEsperado);

    assertEquals(assinaturaDoCodigo, assinaturaEsperada);
  });

  await t.step('buildAuthorizationHeader monta um cabeçalho OAuth bem formado com nonce/timestamp fixos', async () => {
    const cabecalho = await OAuth1Signer.buildAuthorizationHeader({
      method: 'POST',
      url: 'https://apis.garmin.com/training-api/rest/workout',
      credentials: {
        consumerKey: 'consumerkey123',
        consumerSecret: 'consumersecret456',
        accessToken: 'accesstoken789',
        accessTokenSecret: 'accesstokensecret012',
      },
      nonce: 'fixednonce123456',
      timestamp: '1700000000',
    });

    assertEquals(cabecalho.startsWith('OAuth '), true);
    assertEquals(cabecalho.includes('oauth_consumer_key="consumerkey123"'), true);
    assertEquals(cabecalho.includes('oauth_nonce="fixednonce123456"'), true);
    assertEquals(cabecalho.includes('oauth_timestamp="1700000000"'), true);
    assertEquals(cabecalho.includes('oauth_signature_method="HMAC-SHA1"'), true);
    assertEquals(cabecalho.includes('oauth_signature="'), true);
  });
});

// ============================================================================
// (b) Validação do Payload de Planilha Estruturada
// ============================================================================
Deno.test('Test: Validação do Payload de Planilha Estruturada', async (t) => {
  await t.step('rejeita (400) um treino sem tipo de esporte, sem tocar a rede', async () => {
    const { fetchFoiChamado, restaurar } = interceptarFetchEFalhar();
    try {
      const handler = createHandler();
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            planejamentoClinicoId: 'plano-1',
            pacienteIdAnonimo: 'paciente-1',
            estrutura: {
              // tipoTreino ausente de propósito
              duracaoMinutos: 30,
              zonaFcAlvoMin: 120,
              zonaFcAlvoMax: 150,
              dataAgenda: '2026-08-01',
            },
          }),
        }),
      );

      assertEquals(resposta.status, 400);
      const corpo = await resposta.json();
      assertExists(corpo.error);
      assertEquals(fetchFoiChamado(), false);
    } finally {
      restaurar();
    }
  });

  await t.step('rejeita (400) zonas de FC absurdas (mínima >= máxima), sem tocar a rede', async () => {
    const { fetchFoiChamado, restaurar } = interceptarFetchEFalhar();
    try {
      const handler = createHandler();
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            planejamentoClinicoId: 'plano-1',
            pacienteIdAnonimo: 'paciente-1',
            estrutura: {
              tipoTreino: 'corrida',
              duracaoMinutos: 30,
              zonaFcAlvoMin: 180,
              zonaFcAlvoMax: 150, // absurdo: mínima maior que a máxima
              dataAgenda: '2026-08-01',
            },
          }),
        }),
      );

      assertEquals(resposta.status, 400);
      assertEquals(fetchFoiChamado(), false);
    } finally {
      restaurar();
    }
  });

  await t.step('rejeita (400) uma duração negativa, sem tocar a rede', async () => {
    const { fetchFoiChamado, restaurar } = interceptarFetchEFalhar();
    try {
      const handler = createHandler();
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            planejamentoClinicoId: 'plano-1',
            pacienteIdAnonimo: 'paciente-1',
            estrutura: {
              tipoTreino: 'ciclismo',
              duracaoMinutos: -10,
              zonaFcAlvoMin: 120,
              zonaFcAlvoMax: 150,
              dataAgenda: '2026-08-01',
            },
          }),
        }),
      );

      assertEquals(resposta.status, 400);
      assertEquals(fetchFoiChamado(), false);
    } finally {
      restaurar();
    }
  });

  await t.step('rejeita (400) JSON malformado no corpo, sem tocar a rede', async () => {
    const { fetchFoiChamado, restaurar } = interceptarFetchEFalhar();
    try {
      const handler = createHandler();
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: '{ isto não é json válido',
        }),
      );

      assertEquals(resposta.status, 400);
      assertEquals(fetchFoiChamado(), false);
    } finally {
      restaurar();
    }
  });
});

// ============================================================================
// (c) Mock do Pipeline de Criação e Agendamento (Sucesso)
// ============================================================================
Deno.test('Test: Mock do Pipeline de Criação e Agendamento (Sucesso)', async (t) => {
  await t.step('cria o workout (201) e agenda (201) — retorna 200 com garmin_workout_id para o app', async () => {
    const fetchOriginal = globalThis.fetch;
    Deno.env.set('GARMIN_CONSUMER_KEY', 'consumer-key-teste');
    Deno.env.set('GARMIN_CONSUMER_SECRET', 'consumer-secret-teste');

    let chamadasFetch = 0;
    let workoutIdEnviadoNoAgendamento: unknown;

    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
      chamadasFetch += 1;
      const url = typeof input === 'string' ? input : input.toString();

      if (url.includes('/training-api/rest/workout')) {
        assertEquals(init?.method, 'POST');
        return Promise.resolve(
          new Response(JSON.stringify({ workoutId: 'wk_ficticio_123' }), {
            status: 201,
            headers: { 'Content-Type': 'application/json' },
          }),
        );
      }

      if (url.includes('/training-api/rest/schedule')) {
        assertEquals(init?.method, 'POST');
        const corpo = JSON.parse(String(init?.body));
        workoutIdEnviadoNoAgendamento = corpo.workoutId;
        return Promise.resolve(new Response(null, { status: 201 }));
      }

      throw new Error(`fetch chamado para uma URL inesperada no teste: ${url}`);
    }) as typeof fetch;

    const supabaseAdminFalso: SupabaseAdminLike = {
      auth: {
        getUser: (_jwt: string) =>
          Promise.resolve({ data: { user: { id: 'profissional-1' } }, error: null }),
      },
      from: (tabela: string) => ({
        select: (_colunas: string) => ({
          eq: (_coluna: string, _valor: string) => ({
            eq: (_coluna2: string, _valor2: string) => ({
              maybeSingle: () => {
                if (tabela === 'planejamento_clinico') {
                  return Promise.resolve({
                    data: { id: 'plano-1', paciente_id_anonimo: 'paciente-1' },
                    error: null,
                  });
                }
                return Promise.resolve({ data: null, error: null });
              },
            }),
            maybeSingle: () => {
              if (tabela === 'garmin_conexoes') {
                return Promise.resolve({
                  data: {
                    garmin_user_id: 'garmin-user-999',
                    access_token: 'access-token-aluno',
                    access_token_secret: 'access-token-secret-aluno',
                  },
                  error: null,
                });
              }
              return Promise.resolve({ data: null, error: null });
            },
          }),
        }),
      }),
    };

    try {
      const handler = createHandler({ supabaseAdmin: supabaseAdminFalso });
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: 'Bearer jwt-de-teste-do-profissional',
          },
          body: JSON.stringify({
            planejamentoClinicoId: 'plano-1',
            pacienteIdAnonimo: 'paciente-1',
            estrutura: {
              tipoTreino: 'corrida',
              duracaoMinutos: 45,
              zonaFcAlvoMin: 120,
              zonaFcAlvoMax: 150,
              dataAgenda: '2026-08-01',
            },
          }),
        }),
      );

      const corpo = await resposta.json();

      assertEquals(resposta.status, 200);
      assertEquals(corpo.garmin_workout_id, 'wk_ficticio_123');
      assertEquals(chamadasFetch, 2);
      // Prova que a Ação 2 usou o workoutId capturado da Ação 1 — não um
      // valor solto/hardcoded — encadeando de verdade as duas chamadas.
      assertEquals(workoutIdEnviadoNoAgendamento, 'wk_ficticio_123');
    } finally {
      globalThis.fetch = fetchOriginal;
      Deno.env.delete('GARMIN_CONSUMER_KEY');
      Deno.env.delete('GARMIN_CONSUMER_SECRET');
    }
  });

  await t.step('aluno sem conta Garmin conectada: pipeline nunca chega a chamar a Garmin, retorna 422', async () => {
    const fetchOriginal = globalThis.fetch;
    Deno.env.set('GARMIN_CONSUMER_KEY', 'consumer-key-teste');
    Deno.env.set('GARMIN_CONSUMER_SECRET', 'consumer-secret-teste');

    let fetchFoiChamado = false;
    globalThis.fetch = (() => {
      fetchFoiChamado = true;
      throw new Error('fetch não deveria ter sido chamado — o aluno não tem conexão Garmin.');
    }) as typeof fetch;

    const supabaseAdminFalso: SupabaseAdminLike = {
      auth: {
        getUser: (_jwt: string) =>
          Promise.resolve({ data: { user: { id: 'profissional-1' } }, error: null }),
      },
      from: (tabela: string) => ({
        select: (_colunas: string) => ({
          eq: (_coluna: string, _valor: string) => ({
            eq: (_coluna2: string, _valor2: string) => ({
              maybeSingle: () => {
                if (tabela === 'planejamento_clinico') {
                  return Promise.resolve({
                    data: { id: 'plano-1', paciente_id_anonimo: 'paciente-1' },
                    error: null,
                  });
                }
                return Promise.resolve({ data: null, error: null });
              },
            }),
            // `garmin_conexoes`: nenhuma linha encontrada — o aluno nunca
            // conectou a conta Garmin. Este é o cenário defensivo
            // explicitamente pedido ("falhas de autenticação do token do
            // aluno").
            maybeSingle: () => Promise.resolve({ data: null, error: null }),
          }),
        }),
      }),
    };

    try {
      const handler = createHandler({ supabaseAdmin: supabaseAdminFalso });
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: 'Bearer jwt-de-teste-do-profissional',
          },
          body: JSON.stringify({
            planejamentoClinicoId: 'plano-1',
            pacienteIdAnonimo: 'paciente-1',
            estrutura: {
              tipoTreino: 'corrida',
              duracaoMinutos: 45,
              zonaFcAlvoMin: 120,
              zonaFcAlvoMax: 150,
              dataAgenda: '2026-08-01',
            },
          }),
        }),
      );

      assertEquals(resposta.status, 422);
      assertEquals(fetchFoiChamado, false);
    } finally {
      globalThis.fetch = fetchOriginal;
      Deno.env.delete('GARMIN_CONSUMER_KEY');
      Deno.env.delete('GARMIN_CONSUMER_SECRET');
    }
  });

  await t.step('sem token de autenticação do profissional: retorna 401 sem consultar nada', async () => {
    const { fetchFoiChamado, restaurar } = interceptarFetchEFalhar();
    try {
      // Nenhum supabaseAdmin sequer precisa ser injetado — a ausência do
      // Bearer token é barrada antes de qualquer consulta.
      const handler = createHandler();
      const resposta = await handler(
        new Request('https://edge.local/garmin-gateway', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            planejamentoClinicoId: 'plano-1',
            pacienteIdAnonimo: 'paciente-1',
            estrutura: {
              tipoTreino: 'corrida',
              duracaoMinutos: 45,
              zonaFcAlvoMin: 120,
              zonaFcAlvoMax: 150,
              dataAgenda: '2026-08-01',
            },
          }),
        }),
      );

      assertEquals(resposta.status, 401);
      assertEquals(fetchFoiChamado(), false);
    } finally {
      restaurar();
    }
  });
});

// ============================================================================
// Utilitário de teste compartilhado
// ============================================================================

/**
 * Substitui `globalThis.fetch` por uma função que lança se for chamada —
 * usado nos cenários "isto nunca deveria tocar a rede". Retorna um getter
 * (`fetchFoiChamado`) em vez de um booleano solto para não precisar
 * exportar/capturar estado mutável fora de escopo, e `restaurar` para
 * devolver o `fetch` original mesmo se a asserção do teste falhar antes.
 */
function interceptarFetchEFalhar(): { fetchFoiChamado: () => boolean; restaurar: () => void } {
  const fetchOriginal = globalThis.fetch;
  let chamado = false;

  globalThis.fetch = (() => {
    chamado = true;
    throw new Error('fetch não deveria ter sido chamado neste cenário.');
  }) as typeof fetch;

  return {
    fetchFoiChamado: () => chamado,
    restaurar: () => {
      globalThis.fetch = fetchOriginal;
    },
  };
}
