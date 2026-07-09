import { useState, type FormEvent } from 'react';
import { AcessoNaoAutorizadoError, signInProfissional, type ProfissionalAutenticado } from '@/core/supabase';

interface LoginPageProps {
  onAutenticado: (profissional: ProfissionalAutenticado) => void;
}

/**
 * Login estrito de Profissionais de Saúde — rejeita explicitamente
 * qualquer credencial de paciente comum (ver `signInProfissional`), então
 * a mensagem de erro é intencionalmente genérica: nunca revela se o e-mail
 * existe, se a senha estava certa, ou se a conta só não é profissional —
 * qualquer uma dessas distinções ajudaria um invasor a enumerar contas.
 */
export function LoginPage({ onAutenticado }: LoginPageProps) {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErro(null);
    setCarregando(true);

    try {
      const profissional = await signInProfissional(email, senha);
      onAutenticado(profissional);
    } catch (err) {
      const mensagem =
        err instanceof AcessoNaoAutorizadoError
          ? 'Credenciais inválidas ou conta sem acesso ao Painel Profissional.'
          : 'Não foi possível entrar. Tente novamente.';
      setErro(mensagem);
    } finally {
      setCarregando(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-clinical-bg px-4">
      <div className="w-full max-w-sm rounded-2xl border border-clinical-border bg-clinical-surface p-8 shadow-xl">
        <h1 className="text-xl font-semibold text-slate-100">Painel Profissional</h1>
        <p className="mt-1 text-sm text-clinical-muted">
          Acesso restrito a Médicos, Nutricionistas e Auditoria de Seguradoras.
        </p>

        <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-slate-300">
              E-mail
            </label>
            <input
              id="email"
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
            />
          </div>

          <div>
            <label htmlFor="senha" className="block text-sm font-medium text-slate-300">
              Senha
            </label>
            <input
              id="senha"
              type="password"
              required
              autoComplete="current-password"
              value={senha}
              onChange={(event) => setSenha(event.target.value)}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
            />
          </div>

          {erro && (
            <p role="alert" className="text-sm text-clinical-critical">
              {erro}
            </p>
          )}

          <button
            type="submit"
            disabled={carregando}
            className="w-full rounded-lg bg-clinical-primary py-2 font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {carregando ? 'Entrando...' : 'Entrar'}
          </button>
        </form>
      </div>
    </div>
  );
}
