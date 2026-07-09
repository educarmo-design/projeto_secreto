// Motor de Agendamento de Treinos — ponto de entrada da Edge Function
// `garmin-gateway`. Recebe POSTs do Painel Web
// (web_painel/src/features/prescriptions/services/garminApi.ts), valida o
// payload, autentica o profissional chamador, confirma que ele é dono da
// prescrição, localiza o token Garmin do aluno e despacha duas chamadas
// Server-to-Server sequenciais à Garmin Training API:
//
//   Ação 1 — Criar Workout: monta os blocos de corrida/ciclismo com as
//   zonas de FC prescritas e captura o `workoutId` que a Garmin devolve.
//   Ação 2 — Agendar na Agenda do Relógio: associa esse `workoutId` ao
//   `garminUserId` do aluno e à data exata da prescrição.
//
// Custo Zero (PRD Mestre §3): a Garmin Training API do Health API Partner
// Program não cobra por chamada nem por integração homologada — não há
// nenhum provedor pago no meio deste caminho. Rejeitar payloads inválidos
// ANTES de tocar a rede (ver `types.ts`) é o que evita gastar as duas
// chamadas Garmin (e a banda/latência que elas custam) com uma prescrição
// malformada.
//
// Zero Trust: as credenciais de app (`GARMIN_CONSUMER_KEY`/
// `GARMIN_CONSUMER_SECRET`) e a service role key do Supabase só existem
// nas variáveis de ambiente desta função — nunca chegam ao navegador do
// profissional nem ao app do aluno.
//
// Testabilidade (ver index_test.ts): a lógica de tratamento da requisição
// vive em `createHandler`, não direto num `Deno.serve` de topo de arquivo —
// isso permite que os testes chamem o handler como uma função comum, com
// um `supabaseAdmin` falso injetado, sem precisar abrir uma porta de rede
// de verdade. `Deno.serve` só roda quando este arquivo é o módulo de
// entrada de fato (`import.meta.main`), nunca quando é apenas importado
// por um teste.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { OAuth1Signer, type GarminCredentials } from './oauth_helper.ts';
import {
  PayloadInvalidoError,
  validarGarminDispatchRequest,
  type GarminCreateWorkoutResponse,
  type GarminDispatchRequest,
  type GarminWorkoutRequest,
  type WorkoutStep,
} from './types.ts';

const GARMIN_API_BASE_URL = Deno.env.get('GARMIN_API_BASE_URL') ?? 'https://apis.garmin.com';
// Caminhos documentados como placeholder do Garmin Training API Partner
// Program — este ambiente não tem acesso à documentação de parceiro real
// da Garmin para confirmar os paths literais; confirme contra a doc oficial
// antes de apontar para produção. A mecânica de assinatura/despacho abaixo
// (o que de fato importa revisar) não depende desses valores exatos.
const GARMIN_CREATE_WORKOUT_PATH = '/training-api/rest/workout';
const GARMIN_SCHEDULE_WORKOUT_PATH = '/training-api/rest/schedule';

const GARMIN_REQUEST_TIMEOUT_MS = 15_000;

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export class TimeoutError extends Error {
  constructor(message = 'Tempo esgotado ao contatar a Garmin.') {
    super(message);
    this.name = 'TimeoutError';
  }
}

// ============================================================================
// Contrato mínimo do cliente Supabase que este handler precisa — não o
// `SupabaseClient` inteiro (que traz storage/realtime/functions/rpc
// irrelevantes aqui). Isso é o que permite `index_test.ts` injetar um
// objeto falso minúsculo em vez de precisar simular a SDK inteira.
// ============================================================================
interface ConsultaEncadeada<T> {
  eq(coluna: string, valor: string): ConsultaComSegundoEq<T> & { maybeSingle(): Promise<ResultadoConsulta<T>> };
}
interface ConsultaComSegundoEq<T> {
  eq(coluna: string, valor: string): { maybeSingle(): Promise<ResultadoConsulta<T>> };
}
interface ResultadoConsulta<T> {
  data: T | null;
  error: { message: string } | null;
}

export interface SupabaseAdminLike {
  auth: {
    getUser(jwt: string): Promise<{
      data: { user: { id: string } | null };
      error: { message: string } | null;
    }>;
  };
  from(tabela: string): {
    select(colunas: string): ConsultaEncadeada<Record<string, unknown>>;
  };
}

interface HandlerDeps {
  supabaseAdmin?: SupabaseAdminLike;
}

/**
 * Fábrica do handler — permite injetar um `supabaseAdmin` falso em teste
 * (`index_test.ts`) e usar o cliente real do Supabase em produção
 * (`import.meta.main`, abaixo). Nenhuma outra dependência de rede precisa
 * de injeção: as chamadas à Garmin usam `fetch` global diretamente, que
 * `index_test.ts` intercepta substituindo `globalThis.fetch` — exatamente
 * como pedido.
 */
export function createHandler(deps: HandlerDeps = {}) {
  return async function handleRequest(req: Request): Promise<Response> {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: CORS_HEADERS });
    }
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Método não suportado — use POST.' }, 405);
    }

    // ------------------------------------------------------------------
    // 1. Validação estrita do payload (Custo Zero: rejeita antes da rede)
    // ------------------------------------------------------------------
    let corpoBruto: unknown;
    try {
      corpoBruto = await req.json();
    } catch {
      return jsonResponse({ error: 'JSON inválido no corpo da requisição.' }, 400);
    }

    let requisicao: GarminDispatchRequest;
    try {
      requisicao = validarGarminDispatchRequest(corpoBruto);
    } catch (erro) {
      const mensagem = erro instanceof PayloadInvalidoError ? erro.message : 'Payload inválido.';
      return jsonResponse({ error: mensagem }, 400);
    }

    // ------------------------------------------------------------------
    // 2. Autenticação do profissional chamador (Bearer token do Painel Web)
    //    — checada antes de qualquer configuração de servidor: um token
    //    ausente é um erro do chamador (401), não deve depender de
    //    variáveis de ambiente estarem configuradas para ser detectado.
    // ------------------------------------------------------------------
    const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
    if (!jwt) {
      return jsonResponse({ error: 'Token de autenticação ausente.' }, 401);
    }

    // ------------------------------------------------------------------
    // 3. Credenciais Garmin — sempre necessárias, independente de qual
    //    supabaseAdmin está em uso.
    // ------------------------------------------------------------------
    const consumerKey = Deno.env.get('GARMIN_CONSUMER_KEY');
    const consumerSecret = Deno.env.get('GARMIN_CONSUMER_SECRET');
    if (!consumerKey || !consumerSecret) {
      console.error('garmin-gateway: GARMIN_CONSUMER_KEY/GARMIN_CONSUMER_SECRET não configuradas.');
      return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
    }

    // ------------------------------------------------------------------
    // 4. Cliente Supabase — o injetado (testes) ou o real (produção).
    //    Service role: esta função precisa ler `planejamento_clinico` e
    //    `garmin_conexoes` de QUALQUER usuário (para verificar o vínculo
    //    profissional-paciente-plano), não só as próprias linhas do
    //    chamador — por isso não usa a anon key quando cria o cliente
    //    real. A autorização de verdade é reforçada manualmente nos
    //    passos 4-5 abaixo, já que a service role ignora RLS.
    // ------------------------------------------------------------------
    let supabaseAdmin: SupabaseAdminLike;
    if (deps.supabaseAdmin) {
      supabaseAdmin = deps.supabaseAdmin;
    } else {
      const supabaseUrl = Deno.env.get('SUPABASE_URL');
      const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      if (!supabaseUrl || !serviceRoleKey) {
        console.error('garmin-gateway: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY não configuradas.');
        return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
      }
      supabaseAdmin = createClient(supabaseUrl, serviceRoleKey) as unknown as SupabaseAdminLike;
    }

    const { data: userData, error: erroAuth } = await supabaseAdmin.auth.getUser(jwt);
    if (erroAuth || !userData.user) {
      return jsonResponse({ error: 'Sessão inválida ou expirada.' }, 401);
    }
    const profissionalId = userData.user.id;

    // ------------------------------------------------------------------
    // 5. O profissional é realmente dono deste planejamento_clinico, e
    //    ele aponta mesmo para o paciente informado?
    // ------------------------------------------------------------------
    const { data: plano, error: erroPlano } = await supabaseAdmin
      .from('planejamento_clinico')
      .select('id, paciente_id_anonimo')
      .eq('id', requisicao.planejamentoClinicoId)
      .eq('profissional_id', profissionalId)
      .maybeSingle();

    if (erroPlano) {
      console.error('garmin-gateway: erro ao verificar planejamento_clinico:', erroPlano.message);
      return jsonResponse({ error: 'Erro ao verificar a prescrição.' }, 500);
    }
    if (!plano || plano.paciente_id_anonimo !== requisicao.pacienteIdAnonimo) {
      return jsonResponse(
        { error: 'Prescrição não encontrada ou não pertence a este profissional.' },
        403,
      );
    }

    // ------------------------------------------------------------------
    // 6. Token Garmin do aluno — tratamento defensivo explícito: o aluno
    //    pode nunca ter conectado a conta Garmin. Isto NÃO é um erro de
    //    servidor (500); é um estado esperado do negócio (422).
    // ------------------------------------------------------------------
    const { data: conexao, error: erroConexao } = await supabaseAdmin
      .from('garmin_conexoes')
      .select('garmin_user_id, access_token, access_token_secret')
      .eq('usuario_id_anonimo', requisicao.pacienteIdAnonimo)
      .maybeSingle();

    if (erroConexao) {
      console.error('garmin-gateway: erro ao buscar garmin_conexoes:', erroConexao.message);
      return jsonResponse({ error: 'Erro ao verificar a conexão Garmin do aluno.' }, 500);
    }
    if (!conexao) {
      return jsonResponse(
        { error: 'O aluno ainda não conectou a conta Garmin — despacho cancelado.' },
        422,
      );
    }

    const garminUserId = conexao.garmin_user_id as string;
    const credentials: GarminCredentials = {
      consumerKey,
      consumerSecret,
      accessToken: conexao.access_token as string,
      accessTokenSecret: conexao.access_token_secret as string,
    };

    // ------------------------------------------------------------------
    // 7. Ação 1 — Criar Workout
    // ------------------------------------------------------------------
    const workoutPayload = construirWorkoutRequest(requisicao.estrutura);

    let workoutId: string;
    try {
      workoutId = await criarWorkout(credentials, workoutPayload);
    } catch (erro) {
      console.error('garmin-gateway: falha ao criar workout na Garmin:', erro);
      return jsonResponse(
        { error: `Falha ao criar o treino na Garmin: ${mensagemDeErro(erro)}` },
        erro instanceof TimeoutError ? 504 : 502,
      );
    }

    // ------------------------------------------------------------------
    // 8. Ação 2 — Agendar na Agenda do Relógio
    // ------------------------------------------------------------------
    try {
      await agendarWorkout(credentials, {
        workoutId,
        garminUserId,
        scheduleDate: requisicao.estrutura.dataAgenda,
      });
    } catch (erro) {
      console.error('garmin-gateway: falha ao agendar workout na Garmin:', erro);
      // O workout já existe na conta Garmin do aluno mesmo que o
      // agendamento falhe — o erro reporta os dois estados (workoutId
      // presente + falha no passo seguinte), nunca esconde o sucesso
      // parcial nem finge que nada foi criado.
      return jsonResponse(
        {
          error: `Treino criado na Garmin (workoutId ${workoutId}), mas falhou ao agendar: ${mensagemDeErro(erro)}`,
        },
        erro instanceof TimeoutError ? 504 : 502,
      );
    }

    return jsonResponse({ garmin_workout_id: workoutId }, 200);
  };
}

// ============================================================================
// Chamadas assinadas à Garmin
// ============================================================================

async function criarWorkout(
  credentials: GarminCredentials,
  workout: GarminWorkoutRequest,
): Promise<string> {
  const url = `${GARMIN_API_BASE_URL}${GARMIN_CREATE_WORKOUT_PATH}`;
  const response = await chamarGarminAssinado(credentials, url, workout);

  if (!response.ok) {
    throw new Error(`Garmin recusou a criação do treino (HTTP ${response.status}).`);
  }

  const data = (await response.json()) as GarminCreateWorkoutResponse;
  if (!data.workoutId) {
    throw new Error('Resposta da Garmin não trouxe um workoutId.');
  }
  return data.workoutId;
}

async function agendarWorkout(
  credentials: GarminCredentials,
  agendamento: { workoutId: string; garminUserId: string; scheduleDate: string },
): Promise<void> {
  const url = `${GARMIN_API_BASE_URL}${GARMIN_SCHEDULE_WORKOUT_PATH}`;
  const response = await chamarGarminAssinado(credentials, url, agendamento);

  if (!response.ok) {
    throw new Error(`Garmin recusou o agendamento (HTTP ${response.status}).`);
  }
}

/**
 * POST assinado (OAuth 1.0a) com timeout — todo o tráfego de saída à
 * Garmin passa por aqui, então o timeout defensivo só precisa existir uma
 * vez. Usa `fetch` global diretamente (não injetado) — é isso que permite
 * `index_test.ts` interceptar substituindo `globalThis.fetch`.
 */
async function chamarGarminAssinado(
  credentials: GarminCredentials,
  url: string,
  body: unknown,
): Promise<Response> {
  const authorizationHeader = await OAuth1Signer.buildAuthorizationHeader({
    method: 'POST',
    url,
    credentials,
  });

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), GARMIN_REQUEST_TIMEOUT_MS);

  try {
    return await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: authorizationHeader,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (erro) {
    if (erro instanceof DOMException && erro.name === 'AbortError') {
      throw new TimeoutError();
    }
    throw erro;
  } finally {
    clearTimeout(timeoutId);
  }
}

// ============================================================================
// Montagem do payload de treino
// ============================================================================

/**
 * Hoje monta um único bloco `ACTIVE` cobrindo a duração inteira com a
 * zona de FC prescrita — suficiente para a prescrição simples do
 * formulário atual (tipo/duração/zona/data). Séries com aquecimento,
 * intervalos e volta à calma usariam múltiplos `WorkoutStep`, já suportado
 * pelo tipo `GarminWorkoutRequest.steps: WorkoutStep[]`; não implementado
 * porque `GarminPrescriptionForm.tsx` ainda não coleta esses blocos.
 */
function construirWorkoutRequest(estrutura: GarminDispatchRequest['estrutura']): GarminWorkoutRequest {
  const sportType = estrutura.tipoTreino === 'corrida' ? 'RUNNING' : 'CYCLING';

  const blocoPrincipal: WorkoutStep = {
    stepOrder: 1,
    intensityType: 'ACTIVE',
    durationType: 'TIME',
    durationValue: estrutura.duracaoMinutos * 60,
    target: {
      targetType: 'HEART_RATE',
      targetValueLow: estrutura.zonaFcAlvoMin,
      targetValueHigh: estrutura.zonaFcAlvoMax,
    },
  };

  return {
    workoutName: `Prescrição ${estrutura.tipoTreino} — ${estrutura.dataAgenda}`,
    sportType,
    steps: [blocoPrincipal],
  };
}

// ============================================================================
// Utilitários de resposta
// ============================================================================

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

function mensagemDeErro(erro: unknown): string {
  return erro instanceof Error ? erro.message : 'Erro desconhecido.';
}

// ============================================================================
// Entrypoint real — só roda quando este arquivo é o módulo carregado pelo
// Supabase Edge Runtime diretamente, nunca quando index_test.ts o importa.
// ============================================================================
if (import.meta.main) {
  Deno.serve(createHandler());
}
