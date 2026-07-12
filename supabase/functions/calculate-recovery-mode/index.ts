// calculate-recovery-mode — Edge Function stub (Etapa 0.5, F21).
//
// Contexto (ver docs/auditoria/20260712_01.txt e PRD Mestre §0.5 — "Regra
// de arquitetura inegociável: toda regra de negócio sensível é calculada
// server-side"): até esta etapa, `EsteiraTrialController`
// (lib/features/gamification/presentation/controllers/
// esteira_trial_controller.dart) calculava o dia da Esteira dos 14 Dias
// Free e a janela do "Modo Recuperação Humano" localmente, a partir de uma
// data-âncora persistida em `flutter_secure_storage` no próprio aparelho —
// manipulável por qualquer um com acesso de depuração ao dispositivo.
//
// Esta função é o novo destino server-side dessa lógica. Por ora é
// deliberadamente um STUB: autentica o chamador e valida o formato da
// requisição (infraestrutura real, já funcional), mas devolve HTTP 501 em
// vez de calcular o estado de verdade — a Flutter app (ver
// EsteiraTrialGatewayService/EsteiraTrialController) já está cabeada para
// consumir o contrato de resposta abaixo assim que ele existir.
//
// TODO (próxima sessão): implementar o cálculo real.
//   1. Criar uma tabela (ex.: `esteira_trial_estado`, RLS
//      `auth.uid() = usuario_id_anonimo`) para persistir, por usuário, a
//      âncora efetiva do trial e o timestamp de início do congelamento —
//      espelho exato de `_ancoraEfetiva`/`_congeladoDesde` que existiam no
//      controller antes desta etapa, só que do lado do servidor.
//   2. Para `acao: "consultar"`: ler a linha do usuário (criando com
//      `dataCadastro` se ainda não existir) e devolver o estado calculado.
//   3. Para `acao: "ativar_recuperacao"` / `"desativar_recuperacao"`:
//      replicar exatamente a Regra de Congelamento que vivia em
//      `EsteiraTrialController.ativarModoRecuperacao` /
//      `desativarModoRecuperacao` (git blame nesta branch para o algoritmo
//      original), mas escrevendo o resultado nesta tabela em vez de no
//      secure storage do aparelho.
//   4. Para `acao: "registrar_meta_movimento"` / `"registrar_missao_exame"`:
//      idem, persistindo os dois novos campos (incluindo a idempotência que
//      o controller antigo garantia no cliente — aqui precisa ser garantida
//      no servidor).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

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
  dataCadastro: string;
  dia?: number;
}

function validarRequisicao(corpo: unknown): CalculateRecoveryModeRequest {
  if (typeof corpo !== 'object' || corpo === null) {
    throw new Error('Corpo da requisição deve ser um objeto JSON.');
  }
  const { acao, dataCadastro, dia } = corpo as Record<string, unknown>;

  if (typeof acao !== 'string' || !ACOES_VALIDAS.includes(acao as AcaoEsteiraTrial)) {
    throw new Error(`"acao" deve ser um dos valores: ${ACOES_VALIDAS.join(', ')}.`);
  }
  if (typeof dataCadastro !== 'string' || Number.isNaN(Date.parse(dataCadastro))) {
    throw new Error('"dataCadastro" deve ser uma data ISO-8601 válida.');
  }
  if (dia !== undefined && (typeof dia !== 'number' || dia < 1 || dia > 6)) {
    throw new Error('"dia", quando presente, deve ser um número entre 1 e 6.');
  }

  return { acao: acao as AcaoEsteiraTrial, dataCadastro, dia };
}

// ============================================================================
// Contrato mínimo do cliente Supabase que este handler precisa — mesmo
// padrão de supabase/functions/garmin-gateway/index.ts: permite
// index_test.ts injetar um `supabaseAdmin` falso sem simular a SDK inteira.
// ============================================================================
export interface SupabaseAdminLike {
  auth: {
    getUser(jwt: string): Promise<{
      data: { user: { id: string } | null };
      error: { message: string } | null;
    }>;
  };
}

interface HandlerDeps {
  supabaseAdmin?: SupabaseAdminLike;
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

    // ------------------------------------------------------------------
    // 3. STUB — autenticação e validação acima já são reais; o cálculo do
    //    estado da Esteira ainda não foi implementado (ver TODO no topo
    //    deste arquivo). Devolve 501 em vez de inventar um resultado.
    // ------------------------------------------------------------------
    return jsonResponse(
      {
        error:
          'calculate-recovery-mode ainda não está implementada — ver TODO em ' +
          'supabase/functions/calculate-recovery-mode/index.ts.',
        acaoRecebida: requisicao.acao,
      },
      501,
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
