// N45 — sinal operacional de HTTP 402 do Gemini para o admin.
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@^1.0.0';
import { CHAVE_INCIDENTE_SALDO_GEMINI, registrarIncidenteSaldoGemini } from './incidente_saldo_gemini.ts';

function stubFetch(handler: typeof fetch): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = handler;
  return () => {
    globalThis.fetch = original;
  };
}

Deno.test('grava incidente_gemini_402 em configuracoes_sistema (upsert por chave) com a chave secreta só em apikey', async () => {
  let url = '';
  let init: RequestInit | undefined;
  const restaurar = stubFetch(((u: string | URL | Request, i?: RequestInit) => {
    url = String(u);
    init = i;
    return Promise.resolve(new Response(null, { status: 201 }));
  }) as typeof fetch);
  try {
    const ok = await registrarIncidenteSaldoGemini('https://x.supabase.co', 'sb_secret_fake', new Date('2026-11-23T12:00:00Z'));
    assertEquals(ok, true);
    assertEquals(url, 'https://x.supabase.co/rest/v1/configuracoes_sistema?on_conflict=chave');
    const headers = init!.headers as Record<string, string>;
    assertEquals(headers['apikey'], 'sb_secret_fake');
    assertEquals(headers['Authorization'], undefined); // sb_secret_ não é JWT
    assertStringIncludes(headers['Prefer'], 'merge-duplicates');
    const corpo = JSON.parse(String(init!.body));
    assertEquals(corpo.chave, CHAVE_INCIDENTE_SALDO_GEMINI);
    assertEquals(corpo.valor, '2026-11-23T12:00:00.000Z');
    assertEquals(CHAVE_INCIDENTE_SALDO_GEMINI.startsWith('cliente_'), false); // nunca legível a não-admin
  } finally {
    restaurar();
  }
});

Deno.test('chave legada (JWT) também vai em Authorization', async () => {
  let init: RequestInit | undefined;
  const restaurar = stubFetch(((_u: string | URL | Request, i?: RequestInit) => {
    init = i;
    return Promise.resolve(new Response(null, { status: 201 }));
  }) as typeof fetch);
  try {
    await registrarIncidenteSaldoGemini('https://x.supabase.co', 'eyJfake');
    assertEquals((init!.headers as Record<string, string>)['Authorization'], 'Bearer eyJfake');
  } finally {
    restaurar();
  }
});

Deno.test('nunca lança: falha HTTP, erro de rede e config ausente devolvem false', async () => {
  assertEquals(await registrarIncidenteSaldoGemini(undefined, 'k'), false);
  assertEquals(await registrarIncidenteSaldoGemini('https://x', undefined), false);

  let restaurar = stubFetch((() => Promise.resolve(new Response('no', { status: 401 }))) as typeof fetch);
  try {
    assertEquals(await registrarIncidenteSaldoGemini('https://x', 'k'), false);
  } finally {
    restaurar();
  }
  restaurar = stubFetch((() => Promise.reject(new Error('rede caiu'))) as typeof fetch);
  try {
    assertEquals(await registrarIncidenteSaldoGemini('https://x', 'k'), false);
  } finally {
    restaurar();
  }
});
