// Suíte de testes do stub calculate-recovery-mode — Deno.test nativo +
// @std/assert.
//
// Rodar com: deno test --allow-env supabase/functions/calculate-recovery-mode/index_test.ts
//
// Escopo desta suíte (Etapa 0.5): só cobre o que já é real nesta função —
// validação de payload e autenticação. O cálculo do estado da Esteira em si
// é um stub (sempre 501); testes do algoritmo real (dia/congelamento) devem
// ser escritos junto da implementação, numa sessão futura, seguindo o
// TODO no topo de index.ts.

import { assertEquals } from '@std/assert';
import { createHandler, type SupabaseAdminLike } from './index.ts';

function fakeSupabaseAdmin(usuarioId: string | null): SupabaseAdminLike {
  return {
    auth: {
      async getUser(_jwt: string) {
        if (usuarioId === null) {
          return { data: { user: null }, error: { message: 'Sessão inválida.' } };
        }
        return { data: { user: { id: usuarioId } }, error: null };
      },
    },
  };
}

function req(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request('https://example.com/calculate-recovery-mode', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

Deno.test('Test: validação de payload', async (t) => {
  const handler = createHandler({ supabaseAdmin: fakeSupabaseAdmin('user-1') });

  await t.step('rejeita método diferente de POST/OPTIONS com 405', async () => {
    const response = await handler(
      new Request('https://example.com/calculate-recovery-mode', { method: 'GET' }),
    );
    assertEquals(response.status, 405);
  });

  await t.step('rejeita JSON inválido com 400', async () => {
    const response = await handler(
      new Request('https://example.com/calculate-recovery-mode', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer token' },
        body: '{not-json',
      }),
    );
    assertEquals(response.status, 400);
  });

  await t.step('rejeita "acao" fora do conjunto conhecido com 400', async () => {
    const response = await handler(
      req(
        { acao: 'zerar_tudo', dataCadastro: '2026-07-01T00:00:00.000Z' },
        { Authorization: 'Bearer token' },
      ),
    );
    assertEquals(response.status, 400);
  });

  await t.step('rejeita "dataCadastro" que não é data ISO válida com 400', async () => {
    const response = await handler(
      req({ acao: 'consultar', dataCadastro: 'não-é-uma-data' }, { Authorization: 'Bearer token' }),
    );
    assertEquals(response.status, 400);
  });

  await t.step('rejeita "dia" fora do intervalo 1-6 com 400', async () => {
    const response = await handler(
      req(
        { acao: 'registrar_missao_exame', dataCadastro: '2026-07-01T00:00:00.000Z', dia: 9 },
        { Authorization: 'Bearer token' },
      ),
    );
    assertEquals(response.status, 400);
  });
});

Deno.test('Test: autenticação', async (t) => {
  await t.step('rejeita requisição sem header Authorization com 401', async () => {
    const handler = createHandler({ supabaseAdmin: fakeSupabaseAdmin('user-1') });
    const response = await handler(
      req({ acao: 'consultar', dataCadastro: '2026-07-01T00:00:00.000Z' }),
    );
    assertEquals(response.status, 401);
  });

  await t.step('rejeita um JWT que o Supabase considera inválido/expirado com 401', async () => {
    const handler = createHandler({ supabaseAdmin: fakeSupabaseAdmin(null) });
    const response = await handler(
      req(
        { acao: 'consultar', dataCadastro: '2026-07-01T00:00:00.000Z' },
        { Authorization: 'Bearer token-expirado' },
      ),
    );
    assertEquals(response.status, 401);
  });
});

Deno.test(
  'Test: stub — requisição válida e autenticada devolve 501 (não implementada), nunca um resultado inventado',
  async () => {
    const handler = createHandler({ supabaseAdmin: fakeSupabaseAdmin('user-1') });
    const response = await handler(
      req(
        { acao: 'consultar', dataCadastro: '2026-07-01T00:00:00.000Z' },
        { Authorization: 'Bearer token-valido' },
      ),
    );
    assertEquals(response.status, 501);

    const corpo = await response.json();
    assertEquals(corpo.acaoRecebida, 'consultar');
  },
);
