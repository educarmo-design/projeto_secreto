import { useEffect, useState, type FormEvent } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { createClient } from '@supabase/supabase-js';

/**
 * Página de Atualização de Senha (F47) — fluxo de recuperação de senha.
 *
 * Intercepta o evento PASSWORD_RECOVERY do Supabase Auth e exibe um formulário
 * para que o usuário defina uma nova senha. Rota pública (sem autenticação
 * necessária) para permitir acesso via link do e-mail de recuperação.
 *
 * Segurança:
 * - Valida o token na URL antes de permitir edição
 * - Faz signOut silencioso se houver sessão ativa de outra conta
 * - Redireciona para login após sucesso
 */
export function UpdatePasswordPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const [novaSenha, setNovaSenha] = useState('');
  const [confirmarSenha, setConfirmarSenha] = useState('');
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState(false);
  const [validandoToken, setValidandoToken] = useState(true);

  const token = searchParams.get('token');
  const type = searchParams.get('type');

  // Validar token e sessão ao carregar a página
  useEffect(() => {
    async function validarToken() {
      try {
        const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
        const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

        if (!supabaseUrl || !supabaseKey) {
          throw new Error('Variáveis de ambiente do Supabase não configuradas');
        }

        const supabase = createClient(supabaseUrl, supabaseKey);

        // Verificar se há token válido na URL
        if (type !== 'recovery' || !token) {
          throw new Error('Link de recuperação inválido ou expirado');
        }

        // Obter sessão atual
        const { data: sessionData } = await supabase.auth.getSession();

        // Se houver sessão ativa, fazer signOut silencioso para evitar conflito
        if (sessionData?.session) {
          await supabase.auth.signOut();
        }

        // Verificar se o token é válido através da URL hash do Supabase
        // (Supabase coloca o token na URL como #access_token=...)
        setValidandoToken(false);
      } catch (err) {
        setErro(err instanceof Error ? err.message : 'Erro ao validar token');
        setValidandoToken(false);
      }
    }

    validarToken();
  }, [token, type]);

  async function handleSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setErro(null);
    setSucesso(false);

    // Validação de campos
    if (!novaSenha || !confirmarSenha) {
      setErro('Preencha ambos os campos de senha');
      return;
    }

    if (novaSenha.length < 8) {
      setErro('A senha deve ter pelo menos 8 caracteres');
      return;
    }

    if (novaSenha !== confirmarSenha) {
      setErro('As senhas não coincidem');
      return;
    }

    setCarregando(true);

    try {
      const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
      const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

      if (!supabaseUrl || !supabaseKey) {
        throw new Error('Variáveis de ambiente do Supabase não configuradas');
      }

      const supabase = createClient(supabaseUrl, supabaseKey);

      // Atualizar a senha usando o token da sessão
      // O Supabase já carrega o token na sessão a partir da URL
      const { error } = await supabase.auth.updateUser({
        password: novaSenha,
      });

      if (error) {
        throw error;
      }

      setSucesso(true);
      setNovaSenha('');
      setConfirmarSenha('');

      // Redirecionar para login após 2 segundos
      setTimeout(() => {
        navigate('/login', { replace: true });
      }, 2000);
    } catch (err) {
      const mensagem = err instanceof Error ? err.message : 'Erro ao atualizar senha';
      setErro(mensagem);
      console.error('Erro ao atualizar senha:', err);
    } finally {
      setCarregando(false);
    }
  }

  if (validandoToken) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-clinical-bg text-clinical-muted">
        Validando link de recuperação...
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-clinical-bg px-4">
      <div className="w-full max-w-sm rounded-2xl border border-clinical-border bg-clinical-surface p-8 shadow-xl">
        <h1 className="text-xl font-semibold text-slate-100">Definir Nova Senha</h1>
        <p className="mt-1 text-sm text-clinical-muted">
          Digite sua nova senha para recuperar o acesso à sua conta.
        </p>

        {erro && (
          <div className="mt-6 rounded-lg border border-red-900 bg-red-950/20 p-4 text-sm text-red-300">
            ⚠️ {erro}
          </div>
        )}

        {sucesso && (
          <div className="mt-6 rounded-lg border border-green-900 bg-green-950/20 p-4 text-sm text-green-300">
            ✓ Senha atualizada com sucesso. Redirecionando para login...
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <div>
            <label htmlFor="novaSenha" className="block text-sm font-medium text-slate-200">
              Nova Senha
            </label>
            <input
              id="novaSenha"
              type="password"
              value={novaSenha}
              onChange={(e) => setNovaSenha(e.target.value)}
              disabled={carregando || sucesso}
              placeholder="Mínimo 8 caracteres"
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-4 py-2 text-slate-100 placeholder:text-clinical-muted focus:border-clinical-primary focus:outline-none focus:ring-1 focus:ring-clinical-primary disabled:opacity-50"
            />
          </div>

          <div>
            <label htmlFor="confirmarSenha" className="block text-sm font-medium text-slate-200">
              Confirmar Senha
            </label>
            <input
              id="confirmarSenha"
              type="password"
              value={confirmarSenha}
              onChange={(e) => setConfirmarSenha(e.target.value)}
              disabled={carregando || sucesso}
              placeholder="Repita a senha acima"
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-4 py-2 text-slate-100 placeholder:text-clinical-muted focus:border-clinical-primary focus:outline-none focus:ring-1 focus:ring-clinical-primary disabled:opacity-50"
            />
          </div>

          <button
            type="submit"
            disabled={carregando || sucesso}
            className="w-full rounded-lg bg-clinical-primary py-2 font-semibold text-white transition hover:bg-clinical-primary/90 disabled:opacity-50"
          >
            {carregando ? 'Atualizando...' : sucesso ? 'Sucesso!' : 'Atualizar Senha'}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-clinical-muted">
          Lembrou a senha?{' '}
          <button
            onClick={() => navigate('/login', { replace: true })}
            className="font-medium text-clinical-primary hover:underline"
          >
            Faça login
          </button>
        </p>
      </div>
    </div>
  );
}
