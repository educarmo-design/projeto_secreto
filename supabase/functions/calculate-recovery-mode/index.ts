// calculate-recovery-mode — Etapa 1 (F21): cálculo real da Esteira dos 14
// Dias Free / Modo Recuperação Humano, server-side.
//
// Contexto (ver docs/auditoria/20260712_01.txt e PRD Mestre §0.5 — "Regra
// de arquitetura inegociável: toda regra de negócio sensível é calculada
// server-side"): até a Etapa 0.5, `EsteiraTrialController`
// (lib/features/gamification/presentation/controllers/
// esteira_trial_controller.dart) calculava o dia da Esteira e a janela do
// Modo Recuperação localmente, a partir de uma data-âncora persistida em
// `flutter_secure_storage` no próprio aparelho — manipulável por qualquer
// um com acesso de depuração ao dispositivo. A Etapa 0.5 moveu a chamada
// para cá, mas deixou esta função como stub (HTTP 501). Esta etapa
// implementa o cálculo de verdade.
//
// Algoritmo (espelho exato do que rodava no cliente antes da Etapa 0.5 —
// ver histórico do arquivo citado acima nesta branch):
//   - `esteira_trial_estado` (nova tabela, ver migration
//     20260712150000_esteira_trial_estado.sql) guarda só o estado BRUTO por
//     usuário: a data-âncora efetiva do trial e, se o Modo Recuperação está
//     ativo, desde quando. `diaAtual` nunca é armazenado pronto — é sempre
//     recalculado na hora a partir desses dois campos + a data corrente do
//     SERVIDOR (nunca do corpo da requisição).
//   - Regra de Congelamento: ativar trava a contagem na data em que foi
//     ativado; desativar empurra a âncora para frente pelo número exato de
//     dias que ficou congelado — o contador retoma de onde parou, sem
//     pular nem zerar, e o trial de 14 dias se estende pelo mesmo tanto.
//   - A data de início do trial (`ancora_efetiva`) é semeada, na primeira
//     consulta de cada usuário, a partir de `auth.users.created_at` — a
//     data real de criação da conta, gerida pelo próprio GoTrue — e NUNCA
//     a partir de um campo enviado pelo cliente. Isso fecha um vetor de
//     manipulação que o contrato antigo (Etapa 0.5) ainda tinha: um cliente
//     malicioso podia declarar um `dataCadastro` falso para nunca sair do
//     trial. Por isso o payload de entrada não tem mais `dataCadastro`.
//
// Fora de escopo aqui, de propósito (Isolamento de Holds — PRD Mestre
// Parte 4): nenhum cálculo de pontuação/score para seguradoras ou planos
// de saúde. O "Modo Recuperação" do streak diário de gamificação
// (`progresso_gamificacao`, PRD Mestre Parte 7) é um mecanismo *diferente*
// deste (ainda calculado a partir de `UiProfileSwitcher` no cliente) —
// mover aquele para o servidor é trabalho separado, não desta função.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const DIAS_TOTAL_TRIAL = 14;
const DIA_MISSAO_MIN = 1;
const DIA_MISSAO_MAX = 6;

const ACOES_VALIDAS = [
  'consultar',
  'ativar_recuperacao',
  'desativar_recuperacao',
  'registrar_meta_movimento',
  'registrar_missao_exame',
] as const;

type AcaoEsteiraTrial = (typeof ACOES_VALIDAS)[number];

interface CalculateRecoveryModeRequest {
  acao: AcaoEsteiraTrial;
  dia?: number;
}

function validarRequisicao(corpo: unknown): CalculateRecoveryModeRequest {
  if (typeof corpo !== 'object' || corpo === null) {
    throw new Error('Corpo da requisição deve ser um objeto JSON.');
  }
  const { acao, dia } = corpo as Record<string, unknown>;

  if (typeof acao !== 'string' || !ACOES_VALIDAS.includes(acao as AcaoEsteiraTrial)) {
    throw new Error(`"acao" deve ser um dos valores: ${ACOES_VALIDAS.join(', ')}.`);
  }
  if (dia !== undefined && (typeof dia !== 'number' || dia < DIA_MISSAO_MIN || dia > DIA_MISSAO_MAX)) {
    throw new Error(`"dia", quando presente, deve ser um número entre ${DIA_MISSAO_MIN} e ${DIA_MISSAO_MAX}.`);
  }
  if (acao === 'registrar_missao_exame' && dia === undefined) {
    throw new Error('"dia" é obrigatório para a ação "registrar_missao_exame".');
  }

  return { acao: acao as AcaoEsteiraTrial, dia: dia as number | undefined };
}

// ============================================================================
// Aritmética de data — sempre "somente data" (sem componente de hora), em
// UTC, para casar exatamente com `_dataOnly()` do controller Flutter que
// esta função substitui.
// ============================================================================
function dataSomenteISO(data: Date): string {
  return data.toISOString().slice(0, 10);
}

function parseDataSomente(iso: string): Date {
  return new Date(`${iso}T00:00:00.000Z`);
}

function diferencaEmDias(a: Date, b: Date): number {
  const MS_POR_DIA = 24 * 60 * 60 * 1000;
  return Math.round((a.getTime() - b.getTime()) / MS_POR_DIA);
}

function somarDias(iso: string, dias: number): string {
  const data = parseDataSomente(iso);
  data.setUTCDate(data.getUTCDate() + dias);
  return dataSomenteISO(data);
}

// ============================================================================
// Estado persistido + algoritmo puro (sem I/O) — separado do handler HTTP
// para poder ser testado diretamente em index_test.ts sem precisar montar
// uma Request/Response para cada cenário.
// ============================================================================
export interface EsteiraTrialEstadoRow {
  usuario_id_anonimo: string;
  ancora_efetiva: string;
  recuperacao_ativa: boolean;
  congelado_desde: string | null;
  meta_movimento_cumprida: boolean;
  missoes_exames_concluidas: number[];
}

export function aplicarAcao(
  estado: EsteiraTrialEstadoRow,
  acao: AcaoEsteiraTrial,
  hoje: string,
  dia?: number,
): EsteiraTrialEstadoRow {
  switch (acao) {
    case 'consultar':
      return estado;

    case 'ativar_recuperacao': {
      if (estado.recuperacao_ativa) return estado;
      return { ...estado, recuperacao_ativa: true, congelado_desde: hoje };
    }

    case 'desativar_recuperacao': {
      if (!estado.recuperacao_ativa || !estado.congelado_desde) return estado;
      const diasCongelado = diferencaEmDias(
        parseDataSomente(hoje),
        parseDataSomente(estado.congelado_desde),
      );
      return {
        ...estado,
        ancora_efetiva: somarDias(estado.ancora_efetiva, diasCongelado),
        recuperacao_ativa: false,
        congelado_desde: null,
      };
    }

    case 'registrar_meta_movimento':
      if (estado.meta_movimento_cumprida) return estado;
      return { ...estado, meta_movimento_cumprida: true };

    case 'registrar_missao_exame': {
      if (dia === undefined || estado.missoes_exames_concluidas.includes(dia)) {
        return estado;
      }
      return {
        ...estado,
        missoes_exames_concluidas: [...estado.missoes_exames_concluidas, dia].sort(
          (a, b) => a - b,
        ),
      };
    }
  }
}

/// Dia 1-14, clamped. Enquanto `recuperacao_ativa` é true, a referência
/// fica travada em `congelado_desde` em vez de avançar com "hoje" — mesma
/// regra de `EsteiraTrialController._recalcular()` antes da Etapa 0.5.
export function calcularDiaAtual(estado: EsteiraTrialEstadoRow, hoje: string): number {
  const referencia =
    estado.recuperacao_ativa && estado.congelado_desde ? estado.congelado_desde : hoje;
  const diasDecorridos = diferencaEmDias(
    parseDataSomente(referencia),
    parseDataSomente(estado.ancora_efetiva),
  );
  return Math.min(Math.max(diasDecorridos + 1, 1), DIAS_TOTAL_TRIAL);
}

// ============================================================================
// Contrato mínimo do cliente Supabase que este handler precisa — mesmo
// padrão de supabase/functions/garmin-gateway/index.ts: permite
// index_test.ts injetar um `supabaseAdmin` falso sem simular a SDK inteira.
// ============================================================================
interface ConsultaEstado {
  eq(
    coluna: string,
    valor: string,
  ): { maybeSingle(): Promise<{ data: EsteiraTrialEstadoRow | null; error: { message: string } | null }> };
}

export interface SupabaseAdminLike {
  auth: {
    getUser(jwt: string): Promise<{
      data: { user: { id: string; created_at?: string } | null };
      error: { message: string } | null;
    }>;
  };
  from(tabela: string): {
    select(colunas: string): ConsultaEstado;
    upsert(
      valores: EsteiraTrialEstadoRow,
      opcoes: { onConflict: string },
    ): Promise<{ error: { message: string } | null }>;
  };
}

interface HandlerDeps {
  supabaseAdmin?: SupabaseAdminLike;
  /// Injetável em teste para datas determinísticas — mesmo espírito da
  /// injeção de `supabaseAdmin` acima. Em produção (`import.meta.main`)
  /// nunca é passado, e o handler usa o relógio real do servidor.
  agora?: () => Date;
}

/// Lê a linha do usuário em `esteira_trial_estado`; se ainda não existir
/// (primeira consulta de sempre), cria com a âncora semeada a partir de
/// [dataCadastroReal] — nunca de um valor vindo do corpo da requisição.
async function obterOuCriarEstado(
  supabaseAdmin: SupabaseAdminLike,
  usuarioId: string,
  dataCadastroReal: string,
): Promise<EsteiraTrialEstadoRow> {
  const { data, error } = await supabaseAdmin
    .from('esteira_trial_estado')
    .select(
      'usuario_id_anonimo, ancora_efetiva, recuperacao_ativa, congelado_desde, meta_movimento_cumprida, missoes_exames_concluidas',
    )
    .eq('usuario_id_anonimo', usuarioId)
    .maybeSingle();

  if (error) {
    throw new Error(`Erro ao ler esteira_trial_estado: ${error.message}`);
  }
  if (data) return data;

  const novaLinha: EsteiraTrialEstadoRow = {
    usuario_id_anonimo: usuarioId,
    ancora_efetiva: dataCadastroReal,
    recuperacao_ativa: false,
    congelado_desde: null,
    meta_movimento_cumprida: false,
    missoes_exames_concluidas: [],
  };

  const { error: erroUpsert } = await supabaseAdmin
    .from('esteira_trial_estado')
    .upsert(novaLinha, { onConflict: 'usuario_id_anonimo' });
  if (erroUpsert) {
    throw new Error(`Erro ao criar esteira_trial_estado: ${erroUpsert.message}`);
  }

  return novaLinha;
}

export function createHandler(deps: HandlerDeps = {}) {
  return async function handleRequest(req: Request): Promise<Response> {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: CORS_HEADERS });
    }
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Método não suportado — use POST.' }, 405);
    }

    // ------------------------------------------------------------------
    // 1. Validação estrita do payload — rejeita antes de gastar uma
    //    chamada de autenticação com uma requisição malformada.
    // ------------------------------------------------------------------
    let corpoBruto: unknown;
    try {
      corpoBruto = await req.json();
    } catch {
      return jsonResponse({ error: 'JSON inválido no corpo da requisição.' }, 400);
    }

    let requisicao: CalculateRecoveryModeRequest;
    try {
      requisicao = validarRequisicao(corpoBruto);
    } catch (erro) {
      return jsonResponse({ error: mensagemDeErro(erro) }, 400);
    }

    // ------------------------------------------------------------------
    // 2. Autenticação do usuário chamador (Bearer token do app mobile).
    // ------------------------------------------------------------------
    const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!jwt) {
      return jsonResponse({ error: 'Token de autenticação ausente.' }, 401);
    }

    let supabaseAdmin: SupabaseAdminLike;
    if (deps.supabaseAdmin) {
      supabaseAdmin = deps.supabaseAdmin;
    } else {
      const supabaseUrl = Deno.env.get('SUPABASE_URL');
      const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      if (!supabaseUrl || !serviceRoleKey) {
        console.error(
          'calculate-recovery-mode: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY não configuradas.',
        );
        return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
      }
      supabaseAdmin = createClient(supabaseUrl, serviceRoleKey) as unknown as SupabaseAdminLike;
    }

    const { data: userData, error: erroAuth } = await supabaseAdmin.auth.getUser(jwt);
    if (erroAuth || !userData.user) {
      return jsonResponse({ error: 'Sessão inválida ou expirada.' }, 401);
    }
    const usuarioId = userData.user.id;

    // ------------------------------------------------------------------
    // 3. Estado atual (cria com a âncora semeada em auth.users.created_at
    //    se esta for a primeira consulta do usuário) + aplica a ação.
    // ------------------------------------------------------------------
    const agora = deps.agora ?? (() => new Date());
    const hoje = dataSomenteISO(agora());
    const dataCadastroReal = userData.user.created_at
      ? dataSomenteISO(new Date(userData.user.created_at))
      : hoje;

    let estado: EsteiraTrialEstadoRow;
    try {
      estado = await obterOuCriarEstado(supabaseAdmin, usuarioId, dataCadastroReal);
    } catch (erro) {
      console.error('calculate-recovery-mode:', mensagemDeErro(erro));
      return jsonResponse({ error: 'Erro ao carregar o estado da Esteira.' }, 500);
    }

    const estadoAtualizado = aplicarAcao(estado, requisicao.acao, hoje, requisicao.dia);

    if (estadoAtualizado !== estado) {
      const { error: erroUpdate } = await supabaseAdmin
        .from('esteira_trial_estado')
        .upsert(estadoAtualizado, { onConflict: 'usuario_id_anonimo' });
      if (erroUpdate) {
        console.error('calculate-recovery-mode: erro ao persistir estado:', erroUpdate.message);
        return jsonResponse({ error: 'Erro ao salvar o estado da Esteira.' }, 500);
      }
      estado = estadoAtualizado;
    }

    return jsonResponse(
      {
        diaAtual: calcularDiaAtual(estado, hoje),
        modoRecuperacaoAtivo: estado.recuperacao_ativa,
        metaMovimentoCumprida: estado.meta_movimento_cumprida,
        missoesExamesConcluidas: estado.missoes_exames_concluidas,
      },
      200,
    );
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
