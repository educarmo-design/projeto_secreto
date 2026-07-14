import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js';
import type { Database, StatusAprovacaoUsuario, TipoProfissionalSaude } from './types/database';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// Zero Trust: falha alto e cedo em vez de deixar o painel subir apontando
// para um projeto Supabase inexistente/errado — mesma regra já aplicada em
// `AppConfig.hasValidSupabaseCredentials` no app mobile.
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY não configuradas. Copie .env.example para .env e preencha.',
  );
}

/**
 * Cliente Supabase do Painel Web — só a anon key pública, nunca uma
 * service role key. Toda autorização real acontece via RLS no Postgres
 * (ver a migration `*_painel_web_profissional_rls.sql`): esta instância só
 * consegue ler o que as policies explicitamente permitem para a sessão
 * autenticada, exatamente como o app mobile.
 */
export const supabase: SupabaseClient<Database> = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    storageKey: 'painel-profissional-auth',
  },
});

export interface ProfissionalAutenticado {
  id: string;
  nome: string | null;
  /** `null` só é possível para um Admin puro, sem prática clínica (ver `isAdmin` abaixo) — todo profissional aprovado normalmente tem isto preenchido. */
  tipoProfissional: TipoProfissionalSaude | null;
  /** `true` só para o papel de Auditoria de Seguradora — ver Regra de Blindagem LGPD em `PatientList.tsx`. */
  ehSeguradora: boolean;
  /** Sala de Espera (20260714100000) — só quem tem isto vê/aciona `/admin`. Nunca a única barreira: a RLS de `perfis_usuarios_update_admin` reforça o mesmo no banco. */
  isAdmin: boolean;
}

export class AcessoNaoAutorizadoError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AcessoNaoAutorizadoError';
  }
}

/** Lançado quando a conta existe e a senha está correta, mas `status_aprovacao` ainda não foi decidido por um Admin. */
export class SolicitacaoPendenteError extends Error {
  constructor() {
    super('A sua solicitação está em análise pela nossa equipa.');
    this.name = 'SolicitacaoPendenteError';
  }
}

/**
 * Login estrito para Profissionais de Saúde (Médicos/Nutricionistas) e
 * Auditoria de Seguradoras — nunca para pacientes comuns do app mobile,
 * mesmo que a credencial seja válida.
 *
 * Zero Trust em duas camadas: o Supabase Auth só prova QUEM a pessoa é
 * (credenciais corretas). A autorização de acesso ao painel — QUE ela pode
 * ver — é sempre reforçada aqui em seguida, lendo
 * `perfis_usuarios.eh_profissional`/`tipo_profissional`. Se a conta não for
 * profissional, a sessão recém-criada é encerrada imediatamente
 * (`signOut`) antes do erro ser lançado — nunca fica uma sessão "meio
 * autenticada" no localStorage do navegador só porque a senha estava
 * certa.
 */
export async function signInProfissional(
  email: string,
  senha: string,
): Promise<ProfissionalAutenticado> {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password: senha,
  });

  if (error || !data.session) {
    throw new AcessoNaoAutorizadoError(error?.message ?? 'Credenciais inválidas.');
  }

  // Rede de segurança: se `solicitarAcesso` não conseguiu gravar o perfil no
  // momento do cadastro (ex.: projeto com confirmação de e-mail habilitada,
  // sem sessão ainda naquele instante), este é o primeiro momento em que uma
  // sessão real existe para satisfazer `auth.uid() = id` — garante a linha
  // pendente aqui antes de decidir o resultado do login.
  await garantirPerfilPendente(data.session.user);

  const perfil = await buscarPerfilBruto(data.session.user.id);

  if (!perfil || perfil.status_aprovacao === 'rejeitado') {
    await supabase.auth.signOut();
    throw new AcessoNaoAutorizadoError(
      'Esta conta não tem acesso ao Painel Profissional.',
    );
  }

  if (perfil.status_aprovacao === 'pendente') {
    await supabase.auth.signOut();
    throw new SolicitacaoPendenteError();
  }

  // Admin sempre entra, mesmo sem prática clínica própria (`eh_profissional`/
  // `tipo_profissional` nulos) — descoberto na prática ao testar o bootstrap
  // do primeiro Admin: exigir o gate profissional completo aqui bloquearia
  // justamente a conta que só existe para aprovar as outras. `is_admin` só
  // chega a `true` pela policy `perfis_usuarios_update_admin`/bootstrap
  // manual (nunca pelo próprio usuário, ver trigger em
  // `perfis_usuarios_bloquear_auto_promocao`), então confiar nele aqui não
  // abre nenhuma porta nova.
  if (!perfil.is_admin && (!perfil.eh_profissional || !perfil.tipo_profissional)) {
    await supabase.auth.signOut();
    throw new AcessoNaoAutorizadoError(
      'Esta conta não tem acesso ao Painel Profissional.',
    );
  }

  return paraProfissionalAutenticado(perfil);
}

export interface SolicitarAcessoInput {
  email: string;
  senha: string;
  nome: string;
  tipoProfissional: TipoProfissionalSaude;
}

export interface SolicitarAcessoResultado {
  /** `false` quando o projeto exige confirmação de e-mail: o perfil pendente só é gravado no primeiro login, ver `signInProfissional`. */
  perfilCriadoImediatamente: boolean;
}

/**
 * "Solicitar Acesso" — cadastra a conta no Supabase Auth e cria o perfil já
 * como `pendente`. Nunca confia no que o formulário manda para decidir se a
 * conta vira profissional: `eh_profissional`/`status_aprovacao`/`is_admin`
 * são sempre os defaults seguros (reforçado no banco pelo `with check` de
 * `perfis_usuarios_insert_own`, 20260714100000) — só um Admin muda isso, e só
 * depois pelo `AdminDashboard`.
 *
 * Termina sempre com `signOut()` quando `signUp` devolveu sessão — descoberto
 * na prática (teste de navegador ponta a ponta) que deixar essa sessão viva
 * corre contra `App.tsx`: `onAuthStateChange` reage a QUALQUER login, inclusive
 * este, e dispara `obterProfissionalAtual` → `signOut()` de forma assíncrona e
 * desacoplada por já ver `status_aprovacao = 'pendente'`. Se um login legítimo
 * for tentado logo em seguida, esse `signOut()` tardio pode correr contra o
 * `signInWithPassword` novo e derrubar a sessão certa por baixo. Fechar a
 * sessão aqui, de forma síncrona ao fluxo de cadastro, elimina a corrida:
 * "Solicitar Acesso" nunca deixa o usuário autenticado, só cadastrado.
 */
export async function solicitarAcesso(
  input: SolicitarAcessoInput,
): Promise<SolicitarAcessoResultado> {
  const { data, error } = await supabase.auth.signUp({
    email: input.email,
    password: input.senha,
    options: {
      // Espelhado em `user_metadata` mesmo sem sessão imediata (confirmação
      // de e-mail pendente) — é daqui que `garantirPerfilPendente` lê
      // nome/tipo_profissional no primeiro login pós-confirmação, já que
      // `perfis_usuarios` ainda não pôde ser gravada nesse instante.
      data: { nome: input.nome, tipo_profissional: input.tipoProfissional },
    },
  });

  if (error) {
    throw new AcessoNaoAutorizadoError(error.message);
  }
  if (!data.user) {
    throw new AcessoNaoAutorizadoError('Não foi possível criar a conta. Tente novamente.');
  }

  // Sem `data.session` (confirmação de e-mail exigida pelo projeto), ainda
  // não há JWT que satisfaça `auth.uid() = id` — a escrita fica retida até o
  // primeiro login pós-confirmação (`garantirPerfilPendente`), mesmo
  // raciocínio já documentado no app mobile (`cadastro_controller.dart`).
  if (!data.session) {
    return { perfilCriadoImediatamente: false };
  }

  try {
    await inserirPerfilPendente(data.user.id, {
      email: input.email,
      nome: input.nome,
      tipoProfissional: input.tipoProfissional,
    });
  } finally {
    await supabase.auth.signOut();
  }

  return { perfilCriadoImediatamente: true };
}

/**
 * Sessão atual já revalidada contra `perfis_usuarios` — nunca confie
 * apenas em `supabase.auth.getSession()` isolado para decidir se a UI do
 * painel pode renderizar; um token válido não implica papel profissional.
 */
export async function obterProfissionalAtual(): Promise<ProfissionalAutenticado | null> {
  const { data } = await supabase.auth.getSession();
  const userId = data.session?.user.id;
  if (!userId) return null;

  const perfil = await buscarPerfilBruto(userId);

  // Sessão válida (token não expirou) mas sem acesso ao painel — mesma regra
  // de `signInProfissional`: nunca deixa uma sessão "meio autenticada" viva
  // no localStorage. A próxima renderização cai no formulário de login
  // normal, onde uma nova tentativa já devolve a mensagem certa (pendente/
  // rejeitada/sem acesso).
  if (
    !perfil ||
    (!perfil.is_admin &&
      (perfil.status_aprovacao !== 'aprovado' || !perfil.eh_profissional || !perfil.tipo_profissional))
  ) {
    await supabase.auth.signOut();
    return null;
  }

  return paraProfissionalAutenticado(perfil);
}

export async function signOutProfissional(): Promise<void> {
  await supabase.auth.signOut();
}

/** Callback disparado em login/logout/refresh de token — usado por App.tsx para manter o estado de autenticação em sincronia com o Supabase. Retorna a função de `unsubscribe`. */
export function onAuthStateChange(callback: (session: Session | null) => void): () => void {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => {
    callback(session);
  });
  return () => data.subscription.unsubscribe();
}

/**
 * Nota de arquitetura (por que `nome` nunca aparece nas telas de paciente):
 * `perfis_usuarios.nome` de um PACIENTE cadastrado pelo app mobile é
 * gravado como ciphertext AES-256-GCM (`CryptoStorageService`,
 * `cadastro_controller.dart`) — a chave de decriptação vive presa ao
 * Keystore/Keychain do aparelho do paciente e nunca sai dele. Mesmo que
 * uma tela deste painel selecionasse essa coluna, o navegador exibiria
 * apenas o blob cifrado, ilegível. As telas de paciente (`PatientDetails`,
 * `PatientList`) são desenhadas em torno do UUID anônimo por essa razão
 * estrutural, não só por escolha de produto — não há decriptação possível
 * fora do dispositivo original.
 */
interface PerfilBruto {
  id: string;
  nome: string | null;
  eh_profissional: boolean;
  tipo_profissional: TipoProfissionalSaude | null;
  status_aprovacao: StatusAprovacaoUsuario;
  is_admin: boolean;
}

async function buscarPerfilBruto(userId: string): Promise<PerfilBruto | null> {
  const { data, error } = await supabase
    .from('perfis_usuarios')
    .select('id, nome, eh_profissional, tipo_profissional, status_aprovacao, is_admin')
    .eq('id', userId)
    .maybeSingle();

  if (error || !data) return null;
  return data;
}

function paraProfissionalAutenticado(perfil: PerfilBruto): ProfissionalAutenticado {
  return {
    id: perfil.id,
    nome: perfil.nome,
    tipoProfissional: perfil.tipo_profissional,
    ehSeguradora: perfil.tipo_profissional === 'Auditoria_Seguradora',
    isAdmin: perfil.is_admin,
  };
}

async function inserirPerfilPendente(
  userId: string,
  perfil: { email: string; nome: string; tipoProfissional: TipoProfissionalSaude },
): Promise<void> {
  const { error } = await supabase.from('perfis_usuarios').insert({
    id: userId,
    email: perfil.email,
    nome: perfil.nome,
    tipo_profissional: perfil.tipoProfissional,
    eh_profissional: false,
    status_aprovacao: 'pendente',
    is_admin: false,
  });

  if (error) {
    throw new AcessoNaoAutorizadoError(error.message);
  }
}

/**
 * Garante que existe uma linha pendente para este usuário sem nunca
 * sobrescrever uma linha que já exista — `ignoreDuplicates` vira `ON CONFLICT
 * (id) DO NOTHING` no Postgres. Sem isso, um profissional já `aprovado` que
 * loga de novo seria silenciosamente revertido para `pendente`/
 * `eh_profissional: false` a cada login, porque o payload deste "ensure" usa
 * sempre os valores seguros de cadastro.
 */
async function garantirPerfilPendente(user: {
  id: string;
  email?: string;
  user_metadata: Record<string, unknown>;
}): Promise<void> {
  await supabase.from('perfis_usuarios').upsert(
    {
      id: user.id,
      email: user.email ?? null,
      nome: (user.user_metadata.nome as string | undefined) ?? null,
      tipo_profissional: (user.user_metadata.tipo_profissional as TipoProfissionalSaude | undefined) ?? null,
      eh_profissional: false,
      status_aprovacao: 'pendente',
      is_admin: false,
    },
    { onConflict: 'id', ignoreDuplicates: true },
  );
}
