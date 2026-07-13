// Suíte de testes de manage-professional-link — Deno.test nativo + @std/assert.
//
// Rodar com:
//   deno test --allow-env --config supabase/functions/manage-professional-link/deno.json \
//     supabase/functions/manage-professional-link/index_test.ts
//
// Mesmo padrão de calculate-recovery-mode/garmin-gateway: um `supabaseAdmin`
// falso em memória (implementa só o que o handler chama), `fetch` nunca tocado
// de verdade, e o relógio injetado para as datas serem determinísticas.
//
// O foco dos testes é o que esta função tem de mais perigoso: ela escreve com a
// service role, então cada caminho que NÃO deve escrever precisa de prova.

import { assertEquals, assertExists } from '@std/assert';
import { createHandler, type SupabaseAdminLike, type VinculoRow } from './index.ts';

const PROFISSIONAL = '11111111-1111-1111-1111-111111111111';
const PACIENTE = '22222222-2222-2222-2222-222222222222';
const OUTRO_USUARIO = '33333333-3333-3333-3333-333333333333';
const VINCULO = '55555555-5555-5555-5555-555555555555';
const HOJE = new Date('2026-07-13T12:00:00Z');

interface PerfilFake {
  id: string;
  eh_profissional: boolean;
}

/// Admin falso: duas "tabelas" em memória (perfis e vínculos) e o mínimo de
/// encadeamento (`select().eq().in().maybeSingle()`, `insert().select().single()`,
/// `update().eq().select().single()`) que o handler realmente usa.
function fakeSupabaseAdmin(options: {
  usuarioAutenticado?: string | null;
  perfis?: PerfilFake[];
  vinculos?: VinculoRow[];
}): { admin: SupabaseAdminLike; vinculos: VinculoRow[] } {
  const perfis = options.perfis ?? [];
  const vinculos = [...(options.vinculos ?? [])];

  function filtrar(
    linhas: Record<string, unknown>[],
    filtros: { coluna: string; valores: readonly string[] }[],
  ) {
    return linhas.filter((linha) =>
      filtros.every((f) => f.valores.includes(String(linha[f.coluna]))),
    );
  }

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
    from(tabela: string) {
      const linhas = (): Record<string, unknown>[] =>
        tabela === 'perfis_usuarios'
          ? (perfis as unknown as Record<string, unknown>[])
          : (vinculos as unknown as Record<string, unknown>[]);

      return {
        select(_colunas: string) {
          const filtros: { coluna: string; valores: readonly string[] }[] = [];
          const builder = {
            eq(coluna: string, valor: string) {
              filtros.push({ coluna, valores: [valor] });
              return builder;
            },
            in(coluna: string, valores: readonly string[]) {
              filtros.push({ coluna, valores });
              return builder;
            },
            // deno-lint-ignore require-await
            async maybeSingle() {
              return { data: filtrar(linhas(), filtros)[0] ?? null, error: null };
            },
          };
          return builder;
        },
        insert(valores: Record<string, unknown>) {
          return {
            select(_colunas: string) {
              return {
                // deno-lint-ignore require-await
                async single() {
                  const nova = {
                    // UUID de verdade: este `id` volta ao cliente e é o que ele
                    // manda em aceitar/encerrar — que exigem UUID válido.
                    id: crypto.randomUUID(),
                    data_saida: null,
                    fim_carencia: null,
                    ...valores,
                  } as unknown as VinculoRow;
                  vinculos.push(nova);
                  return { data: nova as unknown as Record<string, unknown>, error: null };
                },
              };
            },
          };
        },
        update(patch: Record<string, unknown>) {
          const filtros: { coluna: string; valores: readonly string[] }[] = [];
          const builder = {
            eq(coluna: string, valor: string) {
              filtros.push({ coluna, valores: [valor] });
              return builder;
            },
            select(_colunas: string) {
              return {
                // deno-lint-ignore require-await
                async single() {
                  const alvo = filtrar(linhas(), filtros)[0];
                  if (!alvo) return { data: null, error: { message: 'não encontrado' } };
                  Object.assign(alvo, patch);
                  return { data: alvo, error: null };
                },
              };
            },
          };
          return builder;
        },
      };
    },
  };

  return { admin, vinculos };
}

function req(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request('https://example.com/manage-professional-link', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

const AUTORIZADO = { Authorization: 'Bearer token-valido' };

function cenarioPadrao(overrides: Parameters<typeof fakeSupabaseAdmin>[0] = {}) {
  const { admin, vinculos } = fakeSupabaseAdmin({
    usuarioAutenticado: PROFISSIONAL,
    perfis: [
      { id: PROFISSIONAL, eh_profissional: true },
      { id: PACIENTE, eh_profissional: false },
    ],
    ...overrides,
  });
  return { handler: createHandler({ supabaseAdmin: admin, agora: () => HOJE }), vinculos };
}

function vinculoPendente(): VinculoRow {
  return {
    id: VINCULO,
    profissional_id: PROFISSIONAL,
    paciente_id: PACIENTE,
    status: 'pendente',
    tipo_pagador: 'profissional',
    tipo_produto: 'sem_garmin',
    data_inicio: '2026-07-01',
    data_saida: null,
    fim_carencia: null,
  };
}

// ============================================================================
// Payload malformado
// ============================================================================
Deno.test('Test: validação de payload', async (t) => {
  const { handler } = cenarioPadrao();

  await t.step('rejeita método diferente de POST/OPTIONS com 405', async () => {
    const resposta = await handler(
      new Request('https://example.com/manage-professional-link', { method: 'GET' }),
    );
    assertEquals(resposta.status, 405);
  });

  await t.step('rejeita JSON inválido com 400', async () => {
    const resposta = await handler(
      new Request('https://example.com/manage-professional-link', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...AUTORIZADO },
        body: '{not-json',
      }),
    );
    assertEquals(resposta.status, 400);
  });

  await t.step('rejeita "acao" desconhecida com 400', async () => {
    const resposta = await handler(req({ acao: 'apagar_tudo', paciente_id: PACIENTE }, AUTORIZADO));
    assertEquals(resposta.status, 400);
  });

  await t.step('rejeita criar_vinculo sem paciente_id com 400', async () => {
    const resposta = await handler(req({ acao: 'criar_vinculo' }, AUTORIZADO));
    assertEquals(resposta.status, 400);
  });

  await t.step('rejeita paciente_id que não é UUID com 400', async () => {
    const resposta = await handler(
      req({ acao: 'criar_vinculo', paciente_id: "ou-1=1; drop table" }, AUTORIZADO),
    );
    assertEquals(resposta.status, 400);
  });

  await t.step('rejeita aceitar_vinculo sem vinculo_id com 400', async () => {
    const resposta = await handler(req({ acao: 'aceitar_vinculo' }, AUTORIZADO));
    assertEquals(resposta.status, 400);
  });
});

// ============================================================================
// Autenticação e autorização — os caminhos que NÃO podem escrever
// ============================================================================
Deno.test('Test: autenticação', async (t) => {
  await t.step('rejeita requisição sem header Authorization com 401', async () => {
    const { handler, vinculos } = cenarioPadrao();
    const resposta = await handler(req({ acao: 'criar_vinculo', paciente_id: PACIENTE }));
    assertEquals(resposta.status, 401);
    assertEquals(vinculos.length, 0); // nada foi escrito
  });

  await t.step('rejeita JWT inválido/expirado com 401', async () => {
    const { handler, vinculos } = cenarioPadrao({ usuarioAutenticado: null });
    const resposta = await handler(
      req({ acao: 'criar_vinculo', paciente_id: PACIENTE }, { Authorization: 'Bearer expirado' }),
    );
    assertEquals(resposta.status, 401);
    assertEquals(vinculos.length, 0);
  });
});

Deno.test('Test: só profissional cria vínculo', async (t) => {
  await t.step('usuário comum (eh_profissional=false) recebe 403 e nada é escrito', async () => {
    const { handler, vinculos } = cenarioPadrao({
      usuarioAutenticado: OUTRO_USUARIO,
      perfis: [
        { id: OUTRO_USUARIO, eh_profissional: false },
        { id: PACIENTE, eh_profissional: false },
      ],
    });
    const resposta = await handler(
      req({ acao: 'criar_vinculo', paciente_id: PACIENTE }, AUTORIZADO),
    );
    assertEquals(resposta.status, 403);
    assertEquals(vinculos.length, 0);
  });

  await t.step('profissional não pode vincular-se a si mesmo (400)', async () => {
    const { handler, vinculos } = cenarioPadrao();
    const resposta = await handler(
      req({ acao: 'criar_vinculo', paciente_id: PROFISSIONAL }, AUTORIZADO),
    );
    assertEquals(resposta.status, 400);
    assertEquals(vinculos.length, 0);
  });

  await t.step('paciente inexistente recebe 404', async () => {
    const { handler, vinculos } = cenarioPadrao();
    const resposta = await handler(
      req({ acao: 'criar_vinculo', paciente_id: OUTRO_USUARIO }, AUTORIZADO),
    );
    assertEquals(resposta.status, 404);
    assertEquals(vinculos.length, 0);
  });
});

// ============================================================================
// Criação — o vínculo nasce PENDENTE (não libera dado nenhum)
// ============================================================================
Deno.test('Test: criar_vinculo nasce pendente e o profissional é sempre o do JWT', async () => {
  const { handler, vinculos } = cenarioPadrao();

  const resposta = await handler(
    // `profissional_id` no corpo é ignorado de propósito — o ator vem do JWT.
    // Se este campo fosse lido, um profissional criaria vínculo em nome de outro.
    req(
      { acao: 'criar_vinculo', paciente_id: PACIENTE, profissional_id: OUTRO_USUARIO },
      AUTORIZADO,
    ),
  );

  assertEquals(resposta.status, 201);
  const corpo = await resposta.json();
  assertExists(corpo.vinculo);
  assertEquals(corpo.vinculo.profissional_id, PROFISSIONAL);
  assertEquals(corpo.vinculo.paciente_id, PACIENTE);
  // O ponto central: NÃO nasce ativo. As policies de terceiro exigem 'ativo',
  // então o convite, sozinho, não dá acesso a exame nem a telemetria nenhuma.
  assertEquals(corpo.vinculo.status, 'pendente');
  assertEquals(corpo.vinculo.tipo_pagador, 'profissional');
  assertEquals(corpo.vinculo.tipo_produto, 'sem_garmin');
  assertEquals(corpo.vinculo.data_inicio, '2026-07-13');

  assertEquals(vinculos.length, 1);
});

Deno.test('Test: criar_vinculo é idempotente — clique duplo não duplica slot', async () => {
  const { handler, vinculos } = cenarioPadrao();

  const primeira = await handler(req({ acao: 'criar_vinculo', paciente_id: PACIENTE }, AUTORIZADO));
  const segunda = await handler(req({ acao: 'criar_vinculo', paciente_id: PACIENTE }, AUTORIZADO));

  assertEquals(primeira.status, 201); // criado
  assertEquals(segunda.status, 200); // já existia
  const corpoPrimeira = await primeira.json();
  const corpoSegunda = await segunda.json();
  assertEquals(corpoSegunda.vinculo.id, corpoPrimeira.vinculo.id);
  // Um vínculo = um slot: duplicar aqui inflaria a carteira e, no futuro, a fatura.
  assertEquals(vinculos.length, 1);
});

// ============================================================================
// Aceite — o consentimento do paciente é o que abre a leitura
// ============================================================================
Deno.test('Test: aceitar_vinculo', async (t) => {
  await t.step('o PROFISSIONAL não pode aceitar em nome do paciente (403)', async () => {
    const { handler, vinculos } = cenarioPadrao({ vinculos: [vinculoPendente()] });
    const resposta = await handler(req({ acao: 'aceitar_vinculo', vinculo_id: VINCULO }, AUTORIZADO));
    assertEquals(resposta.status, 403);
    // O que este teste protege: se o profissional pudesse aceitar o próprio
    // convite, o consentimento seria decorativo e ele leria os dados clínicos de
    // qualquer UUID que digitasse.
    assertEquals(vinculos[0].status, 'pendente');
  });

  await t.step('um terceiro qualquer não pode aceitar (403)', async () => {
    const { handler, vinculos } = cenarioPadrao({
      usuarioAutenticado: OUTRO_USUARIO,
      vinculos: [vinculoPendente()],
    });
    const resposta = await handler(req({ acao: 'aceitar_vinculo', vinculo_id: VINCULO }, AUTORIZADO));
    assertEquals(resposta.status, 403);
    assertEquals(vinculos[0].status, 'pendente');
  });

  await t.step('o PACIENTE aceita: pendente -> ativo, data_inicio = dia do aceite', async () => {
    const { handler, vinculos } = cenarioPadrao({
      usuarioAutenticado: PACIENTE,
      vinculos: [vinculoPendente()],
    });
    const resposta = await handler(req({ acao: 'aceitar_vinculo', vinculo_id: VINCULO }, AUTORIZADO));
    assertEquals(resposta.status, 200);
    const corpo = await resposta.json();
    assertEquals(corpo.vinculo.status, 'ativo');
    assertEquals(corpo.vinculo.data_inicio, '2026-07-13');
    assertEquals(vinculos[0].status, 'ativo');
  });

  await t.step('aceitar duas vezes é idempotente (200, segue ativo)', async () => {
    const { handler } = cenarioPadrao({
      usuarioAutenticado: PACIENTE,
      vinculos: [{ ...vinculoPendente(), status: 'ativo' }],
    });
    const resposta = await handler(req({ acao: 'aceitar_vinculo', vinculo_id: VINCULO }, AUTORIZADO));
    assertEquals(resposta.status, 200);
    assertEquals((await resposta.json()).vinculo.status, 'ativo');
  });

  await t.step('vínculo encerrado não pode ser "reaceito" (409)', async () => {
    const { handler } = cenarioPadrao({
      usuarioAutenticado: PACIENTE,
      vinculos: [{ ...vinculoPendente(), status: 'encerrado' }],
    });
    const resposta = await handler(req({ acao: 'aceitar_vinculo', vinculo_id: VINCULO }, AUTORIZADO));
    assertEquals(resposta.status, 409);
  });

  await t.step('vínculo inexistente devolve 404', async () => {
    const { handler } = cenarioPadrao({ usuarioAutenticado: PACIENTE });
    const resposta = await handler(
      req({ acao: 'aceitar_vinculo', vinculo_id: '44444444-4444-4444-4444-444444444444' }, AUTORIZADO),
    );
    assertEquals(resposta.status, 404);
  });
});

// ============================================================================
// Encerramento — os dois lados podem; terceiros não
// ============================================================================
Deno.test('Test: encerrar_vinculo', async (t) => {
  const ativo = (): VinculoRow => ({ ...vinculoPendente(), status: 'ativo' });

  await t.step('o profissional encerra: status encerrado, saída hoje, carência +30d', async () => {
    const { handler, vinculos } = cenarioPadrao({ vinculos: [ativo()] });
    const resposta = await handler(
      req({ acao: 'encerrar_vinculo', vinculo_id: VINCULO }, AUTORIZADO),
    );
    assertEquals(resposta.status, 200);
    const corpo = await resposta.json();
    assertEquals(corpo.vinculo.status, 'encerrado');
    assertEquals(corpo.vinculo.data_saida, '2026-07-13');
    assertEquals(corpo.vinculo.fim_carencia, '2026-08-12'); // F.5: 30 dias
    assertEquals(vinculos[0].status, 'encerrado');
  });

  await t.step('o paciente também encerra (revoga o acesso — F.3)', async () => {
    const { handler, vinculos } = cenarioPadrao({
      usuarioAutenticado: PACIENTE,
      vinculos: [ativo()],
    });
    const resposta = await handler(
      req({ acao: 'encerrar_vinculo', vinculo_id: VINCULO }, AUTORIZADO),
    );
    assertEquals(resposta.status, 200);
    assertEquals(vinculos[0].status, 'encerrado');
  });

  await t.step('um terceiro não encerra vínculo alheio (403)', async () => {
    const { handler, vinculos } = cenarioPadrao({
      usuarioAutenticado: OUTRO_USUARIO,
      vinculos: [ativo()],
    });
    const resposta = await handler(
      req({ acao: 'encerrar_vinculo', vinculo_id: VINCULO }, AUTORIZADO),
    );
    assertEquals(resposta.status, 403);
    assertEquals(vinculos[0].status, 'ativo');
  });
});
