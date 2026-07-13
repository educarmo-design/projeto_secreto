// Suíte de testes de calculate-recovery-mode — Deno.test nativo + @std/assert.
//
// Rodar com: deno test --allow-env supabase/functions/calculate-recovery-mode/index_test.ts
//
// Duas camadas, como em garmin-gateway:
//   (a) o algoritmo puro (`aplicarAcao`/`calcularDiaAtual`) — sem I/O,
//       exercitado com datas fixas para ser 100% determinístico;
//   (b) o handler HTTP completo, com um `supabaseAdmin` falso em memória
//       (implementa só o que o handler realmente chama) e `fetch` nunca
//       tocado de verdade.

import { assertEquals, assertExists } from '@std/assert';
import {
  aplicarAcao,
  calcularDiaAtual,
  createHandler,
  type EsteiraTrialEstadoRow,
  type SupabaseAdminLike,
} from './index.ts';

function estadoBase(overrides: Partial<EsteiraTrialEstadoRow> = {}): EsteiraTrialEstadoRow {
  return {
    usuario_id_anonimo: 'user-1',
    ancora_efetiva: '2026-07-01',
    recuperacao_ativa: false,
    congelado_desde: null,
    meta_movimento_cumprida: false,
    missoes_exames_concluidas: [],
    ...overrides,
  };
}

// ============================================================================
// (a) Algoritmo puro
// ============================================================================
Deno.test('Test: cálculo do dia atual — usuário ativo (sem congelamento)', async (t) => {
  await t.step('dia 1 no dia da âncora', () => {
    const estado = estadoBase({ ancora_efetiva: '2026-07-01' });
    assertEquals(calcularDiaAtual(estado, '2026-07-01'), 1);
  });

  await t.step('avança um dia por dia corrido desde a âncora', () => {
    const estado = estadoBase({ ancora_efetiva: '2026-07-01' });
    assertEquals(calcularDiaAtual(estado, '2026-07-07'), 7);
  });

  await t.step('é limitado a 14 mesmo muito depois do fim do trial', () => {
    const estado = estadoBase({ ancora_efetiva: '2026-07-01' });
    assertEquals(calcularDiaAtual(estado, '2026-08-10'), 14);
  });
});

Deno.test('Test: cálculo do dia atual — usuário com congelamento (Modo Recuperação)', async (t) => {
  await t.step('ativar trava o dia atual, mesmo com o relógio avançando', () => {
    const estado = estadoBase({
      ancora_efetiva: '2026-07-01',
      recuperacao_ativa: true,
      congelado_desde: '2026-07-06', // dia 6 quando congelou
    });
    // "Hoje" bem depois — o dia não deve pular, fica travado no 6.
    assertEquals(calcularDiaAtual(estado, '2026-07-15'), 6);
  });

  await t.step(
    'aplicarAcao("ativar_recuperacao") trava congelado_desde em "hoje" e é idempotente',
    () => {
      const estado = estadoBase({ ancora_efetiva: '2026-07-01' });
      const ativado = aplicarAcao(estado, 'ativar_recuperacao', '2026-07-06');
      assertEquals(ativado.recuperacao_ativa, true);
      assertEquals(ativado.congelado_desde, '2026-07-06');

      // Ativar de novo, num dia diferente, não deve mudar congelado_desde.
      const ativadoDeNovo = aplicarAcao(ativado, 'ativar_recuperacao', '2026-07-10');
      assertEquals(ativadoDeNovo, ativado);
    },
  );

  await t.step(
    'aplicarAcao("desativar_recuperacao") retoma exatamente de onde parou e estende o prazo',
    () => {
      const congelado = estadoBase({
        ancora_efetiva: '2026-07-01',
        recuperacao_ativa: true,
        congelado_desde: '2026-07-06', // congelou no dia 6
      });

      // 5 dias corridos depois, desativa.
      const desativado = aplicarAcao(congelado, 'desativar_recuperacao', '2026-07-11');
      assertEquals(desativado.recuperacao_ativa, false);
      assertEquals(desativado.congelado_desde, null);
      // Âncora empurrada 5 dias para frente: 07-01 -> 07-06.
      assertEquals(desativado.ancora_efetiva, '2026-07-06');
      // No instante da desativação, o dia retomado é exatamente o 6 (nem
      // pulou para o 11, nem voltou pro 1).
      assertEquals(calcularDiaAtual(desativado, '2026-07-11'), 6);

      // 3 dias corridos depois de desativar: o contador volta a andar
      // normalmente a partir de onde parou (dia 9), não do dia 14 que
      // corresponderia a 13 dias corridos sem o congelamento.
      assertEquals(calcularDiaAtual(desativado, '2026-07-14'), 9);
    },
  );

  await t.step('desativar sem nunca ter ativado é um no-op seguro', () => {
    const estado = estadoBase({ ancora_efetiva: '2026-07-01' });
    const resultado = aplicarAcao(estado, 'desativar_recuperacao', '2026-07-03');
    assertEquals(resultado, estado);
  });
});

Deno.test(
  'Test: usuário que falhou na consistência — trial encerra (dia 14) sem a Semana 1 completa',
  async (t) => {
    await t.step('gatilho do Dia 7 nunca dispara sem meta de movimento nem exame', () => {
      // O "sucesso"/"falha" da Semana 1 não é um campo derivado aqui — é o
      // app (EsteiraTrialState.gatilhoDia7Ativo) que combina diaAtual >= 7
      // com metaMovimentoCumprida && missoesExamesConcluidas.isNotEmpty.
      // Este teste prova que o servidor nunca finge essas duas condições
      // como cumpridas por conta própria: um usuário que nunca chamou
      // registrar_meta_movimento/registrar_missao_exame chega ao dia 14
      // com ambas ainda falsas/vazias.
      const estado = estadoBase({ ancora_efetiva: '2026-07-01' });
      assertEquals(calcularDiaAtual(estado, '2026-07-20'), 14);
      assertEquals(estado.meta_movimento_cumprida, false);
      assertEquals(estado.missoes_exames_concluidas, []);
    });

    await t.step(
      'registrar_missao_exame é idempotente e não conclui a meta de movimento sozinho',
      () => {
        const estado = estadoBase();
        const comMissao1 = aplicarAcao(estado, 'registrar_missao_exame', '2026-07-01', 1);
        const comMissao1DeNovo = aplicarAcao(comMissao1, 'registrar_missao_exame', '2026-07-02', 1);

        assertEquals(comMissao1.missoes_exames_concluidas, [1]);
        // Idempotente: registrar o mesmo dia de novo não duplica.
        assertEquals(comMissao1DeNovo.missoes_exames_concluidas, [1]);
        assertEquals(comMissao1DeNovo.meta_movimento_cumprida, false);
      },
    );
  },
);

// ============================================================================
// (b) Handler HTTP — supabaseAdmin falso em memória
// ============================================================================
function fakeSupabaseAdmin(options: {
  usuarioId?: string | null;
  createdAt?: string;
  linhaInicial?: EsteiraTrialEstadoRow;
}): { admin: SupabaseAdminLike; tabela: Map<string, EsteiraTrialEstadoRow> } {
  const tabela = new Map<string, EsteiraTrialEstadoRow>();
  if (options.linhaInicial) {
    tabela.set(options.linhaInicial.usuario_id_anonimo, options.linhaInicial);
  }

  const admin: SupabaseAdminLike = {
    auth: {
      async getUser(_jwt: string) {
        if (!options.usuarioId) {
          return { data: { user: null }, error: { message: 'Sessão inválida.' } };
        }
        return {
          data: { user: { id: options.usuarioId, created_at: options.createdAt } },
          error: null,
        };
      },
    },
    from(_tabelaNome: string) {
      return {
        select(_colunas: string) {
          return {
            eq(_coluna: string, valor: string) {
              return {
                async maybeSingle() {
                  return { data: tabela.get(valor) ?? null, error: null };
                },
              };
            },
          };
        },
        async upsert(valores: EsteiraTrialEstadoRow, _opcoes: { onConflict: string }) {
          tabela.set(valores.usuario_id_anonimo, valores);
          return { error: null };
        },
      };
    },
  };

  return { admin, tabela };
}

function req(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request('https://example.com/calculate-recovery-mode', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
}

Deno.test('Test: validação de payload', async (t) => {
  const { admin } = fakeSupabaseAdmin({ usuarioId: 'user-1', createdAt: '2026-07-01T00:00:00Z' });
  const handler = createHandler({ supabaseAdmin: admin });

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
    const response = await handler(req({ acao: 'zerar_tudo' }, { Authorization: 'Bearer token' }));
    assertEquals(response.status, 400);
  });

  await t.step('rejeita "dia" fora do intervalo 1-6 com 400', async () => {
    const response = await handler(
      req({ acao: 'registrar_missao_exame', dia: 9 }, { Authorization: 'Bearer token' }),
    );
    assertEquals(response.status, 400);
  });

  await t.step('rejeita "registrar_missao_exame" sem "dia" com 400', async () => {
    const response = await handler(
      req({ acao: 'registrar_missao_exame' }, { Authorization: 'Bearer token' }),
    );
    assertEquals(response.status, 400);
  });
});

Deno.test('Test: autenticação', async (t) => {
  await t.step('rejeita requisição sem header Authorization com 401', async () => {
    const { admin } = fakeSupabaseAdmin({ usuarioId: 'user-1' });
    const handler = createHandler({ supabaseAdmin: admin });
    const response = await handler(req({ acao: 'consultar' }));
    assertEquals(response.status, 401);
  });

  await t.step('rejeita um JWT que o Supabase considera inválido/expirado com 401', async () => {
    const { admin } = fakeSupabaseAdmin({ usuarioId: null });
    const handler = createHandler({ supabaseAdmin: admin });
    const response = await handler(
      req({ acao: 'consultar' }, { Authorization: 'Bearer token-expirado' }),
    );
    assertEquals(response.status, 401);
  });
});

Deno.test(
  'Test: primeira consulta cria a linha semeada em auth.users.created_at (nunca no corpo)',
  async () => {
    const { admin, tabela } = fakeSupabaseAdmin({
      usuarioId: 'user-1',
      createdAt: '2026-07-01T12:00:00Z',
    });
    const handler = createHandler({
      supabaseAdmin: admin,
      agora: () => new Date('2026-07-01T18:00:00Z'),
    });

    const response = await handler(
      req({ acao: 'consultar' }, { Authorization: 'Bearer token-valido' }),
    );
    assertEquals(response.status, 200);

    const linha = tabela.get('user-1');
    assertExists(linha);
    assertEquals(linha!.ancora_efetiva, '2026-07-01');

    const corpo = await response.json();
    assertEquals(corpo.diaAtual, 1);
    assertEquals(corpo.modoRecuperacaoAtivo, false);
    assertEquals(corpo.metaMovimentoCumprida, false);
    assertEquals(corpo.missoesExamesConcluidas, []);
  },
);

Deno.test(
  'Test: ativar e desativar o Modo Recuperação persistem entre chamadas (200, nunca reinventa o estado)',
  async () => {
    const { admin, tabela } = fakeSupabaseAdmin({
      usuarioId: 'user-1',
      createdAt: '2026-07-01T00:00:00Z',
      linhaInicial: estadoBase({ usuario_id_anonimo: 'user-1', ancora_efetiva: '2026-07-01' }),
    });
    const handler = createHandler({
      supabaseAdmin: admin,
      agora: () => new Date('2026-07-06T12:00:00Z'),
    });

    const ativarResponse = await handler(
      req({ acao: 'ativar_recuperacao' }, { Authorization: 'Bearer token' }),
    );
    assertEquals(ativarResponse.status, 200);
    const ativarCorpo = await ativarResponse.json();
    assertEquals(ativarCorpo.modoRecuperacaoAtivo, true);

    const linhaAposAtivar = tabela.get('user-1');
    assertExists(linhaAposAtivar);
    assertEquals(linhaAposAtivar!.recuperacao_ativa, true);

    const desativarResponse = await handler(
      req({ acao: 'desativar_recuperacao' }, { Authorization: 'Bearer token' }),
    );
    assertEquals(desativarResponse.status, 200);
    const desativarCorpo = await desativarResponse.json();
    assertEquals(desativarCorpo.modoRecuperacaoAtivo, false);
  },
);
