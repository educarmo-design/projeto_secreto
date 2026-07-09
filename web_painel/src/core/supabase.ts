import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js';
import type { Database, TipoProfissionalSaude } from './types/database';

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
  tipoProfissional: TipoProfissionalSaude;
  /** `true` só para o papel de Auditoria de Seguradora — ver Regra de Blindagem LGPD em `PatientList.tsx`. */
  ehSeguradora: boolean;
}

export class AcessoNaoAutorizadoError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AcessoNaoAutorizadoError';
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

  const profissional = await buscarPerfilProfissional(data.session.user.id);
  if (!profissional) {
    await supabase.auth.signOut();
    throw new AcessoNaoAutorizadoError(
      'Esta conta não tem acesso ao Painel Profissional.',
    );
  }

  return profissional;
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
  return buscarPerfilProfissional(userId);
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
async function buscarPerfilProfissional(
  userId: string,
): Promise<ProfissionalAutenticado | null> {
  const { data, error } = await supabase
    .from('perfis_usuarios')
    .select('id, nome, eh_profissional, tipo_profissional')
    .eq('id', userId)
    .maybeSingle();

  if (error || !data || !data.eh_profissional || !data.tipo_profissional) {
    return null;
  }

  return {
    id: data.id,
    nome: data.nome,
    tipoProfissional: data.tipo_profissional,
    ehSeguradora: data.tipo_profissional === 'Auditoria_Seguradora',
  };
}
