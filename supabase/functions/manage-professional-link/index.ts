// manage-professional-link — Motor de Vínculos (SaaS multi-assento, Adendo v4
// seção F).
//
// Contexto: `vinculos_profissional_paciente` não tem policy de INSERT/UPDATE
// (20260713100000). É deliberado — o vínculo é a unidade de FATURAMENTO (F.2:
// "o vínculo consome 1 slot do pacote do profissional"), e se o cliente pudesse
// gravar a própria linha via REST, um profissional emitiria slots ilimitados
// sem passar pelo teto do pacote que paga. Toda escrita entra por aqui, com a
// service role (que ignora RLS).
//
// Por isso esta função é a superfície mais sensível do backend: ela tem a chave
// mestra na mão. As três regras que a mantêm honesta:
//
//   1. `profissional_id` e `paciente_id` NUNCA saem do corpo da requisição para
//      dentro de um privilégio. O ator é sempre `auth.getUser(jwt).id` — o
//      corpo só diz QUEM é o outro lado, nunca quem é o autor.
//   2. Criar vínculo NÃO dá acesso a nada. O vínculo nasce `pendente`, e todas
//      as policies de terceiro exigem `status = 'ativo'`. Sem isso, um
//      profissional autenticado que conhecesse o UUID de qualquer usuário
//      passaria a ler os exames e a telemetria dele — pela API, sem o titular
//      saber (F.3: "você decide exatamente o que cada profissional vê").
//   3. Só o PACIENTE promove pendente -> ativo (`aceitar_vinculo`). É o
//      consentimento, e é o que separa "convite" de "invasão".
//
// Fora de escopo (iteração futura, registrado aqui de propósito): a verificação
// do TETO DE SLOTS do pacote do profissional. Hoje todo profissional tem slots
// ilimitados porque a tabela de assinatura/pacote (F.2) ainda não existe. O
// lugar de checar isso é `criar_vinculo`, antes do insert — ver TODO abaixo.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const TABELA_VINCULOS = 'vinculos_profissional_paciente';
const TABELA_PERFIS = 'perfis_usuarios';

/// Colunas do vínculo devolvidas ao cliente. `select('*')` seria um contrato
/// frouxo: qualquer coluna futura (faturamento, por exemplo) vazaria sozinha.
const COLUNAS_VINCULO =
  'id, profissional_id, paciente_id, status, tipo_pagador, tipo_produto, data_inicio, data_saida, fim_carencia';

/// Status que ocupam o par (profissional, paciente) — os mesmos cobertos pelo
/// índice único parcial `uniq_vinculo_vivo_por_par` (`where status <>
/// 'encerrado'`). Um par com vínculo VIVO não pode receber outro.
const STATUS_VIVOS = ['pendente', 'ativo', 'em_carencia'] as const;

/// F.5: ao ficar sem acesso, o usuário ganha 30 dias de acesso completo antes do
/// bloqueio. Gravado no vínculo que se encerra; quem decide se a carência de
/// fato começa é a verificação de "acesso ativo" (F41), que olha se sobrou
/// algum outro vínculo pago ou plano individual.
const DIAS_DE_CARENCIA = 30;

const ACOES_VALIDAS = ['criar_vinculo', 'aceitar_vinculo', 'encerrar_vinculo'] as const;
type AcaoVinculo = (typeof ACOES_VALIDAS)[number];

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface ManageLinkRequest {
  acao: AcaoVinculo;
  paciente_id?: string;
  paciente_email?: string;
  vinculo_id?: string;
}

export interface VinculoRow {
  id: string;
  profissional_id: string;
  paciente_id: string;
  status: string;
  tipo_pagador: string;
  tipo_produto: string;
  data_inicio: string;
  data_saida: string | null;
  fim_carencia: string | null;
}

// ============================================================================
// Validação do payload — estrita, e antes de qualquer I/O.
// ============================================================================
export function validarRequisicao(corpo: unknown): ManageLinkRequest {
  if (typeof corpo !== 'object' || corpo === null) {
    throw new Error('Corpo da requisição deve ser um objeto JSON.');
  }
  const { acao, paciente_id, paciente_email, vinculo_id } = corpo as Record<string, unknown>;

  if (typeof acao !== 'string' || !ACOES_VALIDAS.includes(acao as AcaoVinculo)) {
    throw new Error(`"acao" deve ser um dos valores: ${ACOES_VALIDAS.join(', ')}.`);
  }

  if (acao === 'criar_vinculo') {
    // Aceita exatamente um dos dois: `paciente_id` (UUID — uso futuro/interno)
    // ou `paciente_email` (o painel web B2B só conhece o e-mail do paciente;
    // ver `resolverPacienteIdPorEmail` abaixo, que resolve o UUID
    // internamente contra `auth.users`, nunca contra `perfis_usuarios.email`
    // — essa coluna sai cifrada AES-256-GCM no cliente e nunca bateria com o
    // texto plano digitado no formulário).
    const temId = typeof paciente_id === 'string' && paciente_id.length > 0;
    const temEmail = typeof paciente_email === 'string' && paciente_email.length > 0;
    if (temId === temEmail) {
      throw new Error('Informe exatamente um entre "paciente_id" e "paciente_email".');
    }
    if (temId) {
      if (!UUID_REGEX.test(paciente_id as string)) {
        throw new Error('"paciente_id" deve ser um UUID válido.');
      }
      return { acao, paciente_id: paciente_id as string };
    }
    if (!EMAIL_REGEX.test(paciente_email as string)) {
      throw new Error('"paciente_email" deve ser um e-mail válido.');
    }
    return { acao, paciente_email: (paciente_email as string).trim().toLowerCase() };
  }

  if (typeof vinculo_id !== 'string' || !UUID_REGEX.test(vinculo_id)) {
    throw new Error('"vinculo_id" deve ser um UUID válido.');
  }
  return { acao: acao as AcaoVinculo, vinculo_id };
}

// ============================================================================
// Contrato mínimo do cliente Supabase que este handler usa — mesmo padrão de
// garmin-gateway/calculate-recovery-mode: permite ao index_test.ts injetar um
// admin falso em memória sem simular a SDK inteira.
// ============================================================================
type ErroSupabase = { message: string } | null;
type Registro = Record<string, unknown>;

interface RespostaUnica {
  data: Registro | null;
  error: ErroSupabase;
}

interface FiltroSelect {
  eq(coluna: string, valor: string): FiltroSelect;
  in(coluna: string, valores: readonly string[]): FiltroSelect;
  maybeSingle(): Promise<RespostaUnica>;
}

interface RetornoUnico {
  single(): Promise<RespostaUnica>;
}

interface FiltroUpdate {
  eq(coluna: string, valor: string): FiltroUpdate;
  select(colunas: string): RetornoUnico;
}

interface TabelaLike {
  select(colunas: string): FiltroSelect;
  insert(valores: Registro): { select(colunas: string): RetornoUnico };
  update(valores: Registro): FiltroUpdate;
}

export interface SupabaseAdminLike {
  auth: {
    getUser(jwt: string): Promise<{
      data: { user: { id: string } | null };
      error: ErroSupabase;
    }>;
  };
  from(tabela: string): TabelaLike;
  /// Só usado para `resolver_usuario_id_por_email` (ver
  /// `resolverPacienteIdPorEmail`) — a função SQL que traduz o e-mail do
  /// paciente para o UUID de `auth.users`, restrita ao papel `service_role`
  /// (20260713210000_resolver_usuario_id_por_email.sql).
  rpc(fn: string, params: Record<string, unknown>): Promise<{ data: unknown; error: ErroSupabase }>;
}

interface HandlerDeps {
  supabaseAdmin?: SupabaseAdminLike;
  /// Injetável em teste para datas determinísticas; em produção o handler usa
  /// o relógio real do servidor — nunca uma data vinda do cliente.
  agora?: () => Date;
}

class ErroHttp extends Error {
  constructor(readonly status: number, mensagem: string) {
    super(mensagem);
  }
}

function dataISO(data: Date): string {
  return data.toISOString().slice(0, 10);
}

function somarDias(data: Date, dias: number): string {
  const copia = new Date(data.getTime());
  copia.setUTCDate(copia.getUTCDate() + dias);
  return dataISO(copia);
}

/// Traduz o e-mail do paciente (digitado no painel web B2B) para o UUID de
/// `auth.users`, via a função SQL `resolver_usuario_id_por_email` — a única
/// que enxerga e-mail em texto plano neste sistema (o de `perfis_usuarios` é
/// cifrado no cliente). Não distingue "e-mail não existe" de "erro de rede"
/// no retorno (`null` nos dois casos até aqui) — quem decide o HTTP 404 é o
/// chamador, em `createHandler`.
async function resolverPacienteIdPorEmail(
  admin: SupabaseAdminLike,
  email: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc('resolver_usuario_id_por_email', {
    email_busca: email,
  });
  if (error) {
    throw new Error(`Erro ao resolver e-mail do paciente: ${error.message}`);
  }
  return (data as string | null) ?? null;
}

// ============================================================================
// Ações
// ============================================================================

/// O profissional convida um paciente. Nasce `pendente`: não libera nada até o
/// paciente aceitar.
async function criarVinculo(
  admin: SupabaseAdminLike,
  profissionalId: string,
  pacienteId: string,
  hoje: Date,
): Promise<{ vinculo: VinculoRow; criado: boolean }> {
  if (profissionalId === pacienteId) {
    throw new ErroHttp(400, 'Um profissional não pode vincular-se a si mesmo.');
  }

  // Quem chama precisa SER profissional. Sem esta checagem, qualquer usuário
  // autenticado se autodeclararia acompanhante de outro — a service role não
  // pergunta, ela obedece.
  const { data: perfilProfissional, error: erroPerfil } = await admin
    .from(TABELA_PERFIS)
    .select('id, eh_profissional')
    .eq('id', profissionalId)
    .maybeSingle();
  if (erroPerfil) {
    throw new Error(`Erro ao ler o perfil do profissional: ${erroPerfil.message}`);
  }
  if (!perfilProfissional || perfilProfissional.eh_profissional !== true) {
    throw new ErroHttp(403, 'Apenas um profissional pode criar vínculos.');
  }

  // O paciente precisa existir. Sem isto, um erro de digitação viraria um
  // vínculo órfão apontando para um UUID que nunca vai aceitar nada.
  const { data: perfilPaciente, error: erroPaciente } = await admin
    .from(TABELA_PERFIS)
    .select('id')
    .eq('id', pacienteId)
    .maybeSingle();
  if (erroPaciente) {
    throw new Error(`Erro ao ler o perfil do paciente: ${erroPaciente.message}`);
  }
  if (!perfilPaciente) {
    throw new ErroHttp(404, 'Paciente não encontrado.');
  }

  // Idempotência: se já existe vínculo VIVO (pendente/ativo/em_carencia) neste
  // par, devolve o que existe em vez de esbarrar no índice único e devolver 500
  // ao profissional que clicou duas vezes.
  const { data: existente, error: erroExistente } = await admin
    .from(TABELA_VINCULOS)
    .select(COLUNAS_VINCULO)
    .eq('profissional_id', profissionalId)
    .eq('paciente_id', pacienteId)
    .in('status', STATUS_VIVOS)
    .maybeSingle();
  if (erroExistente) {
    throw new Error(`Erro ao verificar vínculo existente: ${erroExistente.message}`);
  }
  if (existente) {
    return { vinculo: existente as unknown as VinculoRow, criado: false };
  }

  // TODO (faturamento): antes deste insert, checar o teto de slots do pacote do
  // profissional (F.2 — faixa de pacientes × tipo de produto) e devolver 402
  // quando a carteira estiver cheia. Hoje o teto é ilimitado porque a tabela de
  // assinatura ainda não existe. Este é o único ponto do sistema em que um slot
  // é consumido — a checagem tem de morar aqui, e em nenhum outro lugar.
  const { data: criado, error: erroInsert } = await admin
    .from(TABELA_VINCULOS)
    .insert({
      profissional_id: profissionalId,
      paciente_id: pacienteId,
      status: 'pendente',
      tipo_pagador: 'profissional',
      // Herdado do pacote do profissional quando o faturamento existir (F.2).
      // Até lá, o padrão conservador: sem Garmin é o plano mais barato, e dar de
      // graça o recurso caro é pior de reverter do que liberá-lo depois.
      tipo_produto: 'sem_garmin',
      data_inicio: dataISO(hoje),
    })
    .select(COLUNAS_VINCULO)
    .single();
  if (erroInsert || !criado) {
    throw new Error(`Erro ao criar o vínculo: ${erroInsert?.message ?? 'sem retorno'}`);
  }

  return { vinculo: criado as unknown as VinculoRow, criado: true };
}

/// O paciente aceita o convite: pendente -> ativo. É AQUI que a leitura dos
/// dados clínicos passa a ser liberada pela RLS — por isso só o titular pode.
async function aceitarVinculo(
  admin: SupabaseAdminLike,
  usuarioId: string,
  vinculoId: string,
  hoje: Date,
): Promise<VinculoRow> {
  const vinculo = await buscarVinculo(admin, vinculoId);

  if (vinculo.paciente_id !== usuarioId) {
    // Mesma resposta para "não é seu" e "não existe" (ver buscarVinculo): um
    // profissional não descobre, por tentativa e erro, quais vínculos existem.
    throw new ErroHttp(403, 'Apenas o paciente do vínculo pode aceitá-lo.');
  }
  if (vinculo.status === 'ativo') {
    return vinculo; // Idempotente: aceitar duas vezes não é erro.
  }
  if (vinculo.status !== 'pendente') {
    throw new ErroHttp(409, `Vínculo com status "${vinculo.status}" não pode ser aceito.`);
  }

  // `data_inicio` passa a ser o dia do ACEITE: é quando a relação de cuidado de
  // fato começou a valer. O dia do convite não é o dia do vínculo.
  return await atualizarVinculo(admin, vinculoId, {
    status: 'ativo',
    data_inicio: dataISO(hoje),
    atualizado_em: hoje.toISOString(),
  });
}

/// Qualquer um dos dois lados encerra: o profissional tira o paciente da
/// carteira (libera o slot), ou o paciente revoga o acesso (F.3 — revogável).
async function encerrarVinculo(
  admin: SupabaseAdminLike,
  usuarioId: string,
  vinculoId: string,
  hoje: Date,
): Promise<VinculoRow> {
  const vinculo = await buscarVinculo(admin, vinculoId);

  if (vinculo.profissional_id !== usuarioId && vinculo.paciente_id !== usuarioId) {
    throw new ErroHttp(403, 'Apenas as partes do vínculo podem encerrá-lo.');
  }
  if (vinculo.status === 'encerrado') {
    return vinculo; // Idempotente.
  }

  // `fim_carencia` é gravado como a data-limite dos 30 dias (F.5), mas quem
  // decide se o paciente ENTRA em carência é a verificação de acesso ativo
  // (F41): se ele ainda tem outro vínculo pago ou plano individual, não entra.
  // Este campo é o prazo, não a sentença.
  return await atualizarVinculo(admin, vinculoId, {
    status: 'encerrado',
    data_saida: dataISO(hoje),
    fim_carencia: somarDias(hoje, DIAS_DE_CARENCIA),
    atualizado_em: hoje.toISOString(),
  });
}

async function buscarVinculo(admin: SupabaseAdminLike, vinculoId: string): Promise<VinculoRow> {
  const { data, error } = await admin
    .from(TABELA_VINCULOS)
    .select(COLUNAS_VINCULO)
    .eq('id', vinculoId)
    .maybeSingle();
  if (error) {
    throw new Error(`Erro ao ler o vínculo: ${error.message}`);
  }
  if (!data) {
    throw new ErroHttp(404, 'Vínculo não encontrado.');
  }
  return data as unknown as VinculoRow;
}

async function atualizarVinculo(
  admin: SupabaseAdminLike,
  vinculoId: string,
  patch: Registro,
): Promise<VinculoRow> {
  const { data, error } = await admin
    .from(TABELA_VINCULOS)
    .update(patch)
    .eq('id', vinculoId)
    .select(COLUNAS_VINCULO)
    .single();
  if (error || !data) {
    throw new Error(`Erro ao atualizar o vínculo: ${error?.message ?? 'sem retorno'}`);
  }
  return data as unknown as VinculoRow;
}

// ============================================================================
// Handler HTTP
// ============================================================================
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

    let requisicao: ManageLinkRequest;
    try {
      requisicao = validarRequisicao(corpoBruto);
    } catch (erro) {
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
        console.error(
          'manage-professional-link: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY não configuradas.',
        );
        return jsonResponse({ error: 'Configuração do servidor incompleta.' }, 500);
      }
      // A service role vive só aqui dentro, no processo da Edge Function. Ela
      // nunca é devolvida na resposta nem chega ao app/painel.
      admin = createClient(supabaseUrl, serviceRoleKey) as unknown as SupabaseAdminLike;
    }

    const { data: userData, error: erroAuth } = await admin.auth.getUser(jwt);
    if (erroAuth || !userData.user) {
      return jsonResponse({ error: 'Sessão inválida ou expirada.' }, 401);
    }
    const usuarioId = userData.user.id;
    const hoje = (deps.agora ?? (() => new Date()))();

    try {
      switch (requisicao.acao) {
        case 'criar_vinculo': {
          let pacienteId = requisicao.paciente_id;
          if (!pacienteId) {
            // validarRequisicao já garante que, chegando aqui sem paciente_id,
            // existe paciente_email — o "!" abaixo é seguro por essa garantia.
            pacienteId = (await resolverPacienteIdPorEmail(admin, requisicao.paciente_email!)) ?? undefined;
            if (!pacienteId) {
              // Mesma mensagem do 404 de `criarVinculo` (perfil inexistente
              // por UUID) — um só texto para "e-mail não corresponde a
              // ninguém", não importa em qual dos dois pontos a busca falhou.
              return jsonResponse({ error: 'Paciente não encontrado.' }, 404);
            }
          }

          const { vinculo, criado } = await criarVinculo(admin, usuarioId, pacienteId, hoje);
          return jsonResponse({ vinculo }, criado ? 201 : 200);
        }
        case 'aceitar_vinculo': {
          const vinculo = await aceitarVinculo(admin, usuarioId, requisicao.vinculo_id!, hoje);
          return jsonResponse({ vinculo }, 200);
        }
        case 'encerrar_vinculo': {
          const vinculo = await encerrarVinculo(admin, usuarioId, requisicao.vinculo_id!, hoje);
          return jsonResponse({ vinculo }, 200);
        }
      }
    } catch (erro) {
      if (erro instanceof ErroHttp) {
        return jsonResponse({ error: erro.message }, erro.status);
      }
      // Erro de banco/inesperado: loga o detalhe no servidor e devolve genérico
      // ao cliente — mensagem de Postgres pode revelar schema.
      console.error('manage-professional-link:', mensagemDeErro(erro));
      return jsonResponse({ error: 'Erro ao processar o vínculo.' }, 500);
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
