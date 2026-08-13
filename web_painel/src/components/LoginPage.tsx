import { useState, type FormEvent } from 'react';
import {
  AcessoNaoAutorizadoError,
  SolicitacaoPendenteError,
  signInProfissional,
  solicitarAcesso,
  type ProfissionalAutenticado,
} from '@/core/supabase';
import type { TipoProfissionalSaude } from '@/core/types/database';

interface LoginPageProps {
  onAutenticado: (profissional: ProfissionalAutenticado) => void;
}

type Aba = 'entrar' | 'solicitar';

const OPCOES_TIPO_PROFISSIONAL: Array<{ value: TipoProfissionalSaude; label: string }> = [
  { value: 'Medico', label: 'Médico(a)' },
  { value: 'Nutricionista', label: 'Nutricionista' },
  { value: 'Fisioterapeuta', label: 'Fisioterapeuta' },
  { value: 'Personal_Trainer', label: 'Personal Trainer' },
];

/**
 * N03 (RELATÓRIO 20260811_0005) — mesma aritmética de `calcular_idade()` no
 * banco (`20260811190000_n03_trava_maioridade.sql`): anos completos entre
 * `dataNascimento` e hoje, sem depender de bibliotecas de data. Só UX — a
 * CHECK constraint `perfis_usuarios_maioridade` é a barreira real; ver
 * `inserirPerfilPendente` em `core/supabase.ts` para o que acontece se
 * alguém contornar esta validação.
 */
function calcularIdade(dataNascimentoISO: string): number {
  const nascimento = new Date(dataNascimentoISO);
  const hoje = new Date();
  let idade = hoje.getFullYear() - nascimento.getFullYear();
  const aindaNaoFezAniversarioEsteAno =
    hoje.getMonth() < nascimento.getMonth() ||
    (hoje.getMonth() === nascimento.getMonth() && hoje.getDate() < nascimento.getDate());
  if (aindaNaoFezAniversarioEsteAno) idade -= 1;
  return idade;
}

const IDADE_MINIMA_ANOS = 18;

/**
 * Login + Sala de Espera de Profissionais de Saúde — rejeita explicitamente
 * qualquer credencial de paciente comum (ver `signInProfissional`), então a
 * mensagem de erro genérica de "Entrar" é proposital: nunca revela se o
 * e-mail existe, se a senha estava certa, ou se a conta só não é
 * profissional — qualquer uma dessas distinções ajudaria um invasor a
 * enumerar contas. A aba "Solicitar Acesso" é o único jeito de uma conta
 * nova entrar nessa fila: mesmo que o cadastro tenha sucesso, `onAutenticado`
 * nunca é chamado a partir dela — o acesso real só chega depois de um Admin
 * aprovar em `/admin`.
 */
export function LoginPage({ onAutenticado }: LoginPageProps) {
  const [aba, setAba] = useState<Aba>('entrar');

  return (
    <div className="flex min-h-screen items-center justify-center bg-clinical-bg px-4">
      <div className="w-full max-w-sm rounded-2xl border border-clinical-border bg-clinical-surface p-8 shadow-xl">
        <h1 className="text-xl font-semibold text-slate-100">Painel Profissional</h1>
        <p className="mt-1 text-sm text-clinical-muted">
          Acesso restrito a Médicos, Nutricionistas e Auditoria de Seguradoras.
        </p>

        <div className="mt-6 flex rounded-lg border border-clinical-border bg-clinical-bg p-1 text-sm">
          <button
            type="button"
            onClick={() => setAba('entrar')}
            className={`flex-1 rounded-md py-1.5 font-medium transition ${
              aba === 'entrar' ? 'bg-clinical-primary text-white' : 'text-clinical-muted hover:text-slate-100'
            }`}
          >
            Entrar
          </button>
          <button
            type="button"
            onClick={() => setAba('solicitar')}
            className={`flex-1 rounded-md py-1.5 font-medium transition ${
              aba === 'solicitar' ? 'bg-clinical-primary text-white' : 'text-clinical-muted hover:text-slate-100'
            }`}
          >
            Solicitar Acesso
          </button>
        </div>

        {aba === 'entrar' ? (
          <FormularioEntrar onAutenticado={onAutenticado} />
        ) : (
          <FormularioSolicitarAcesso onSolicitado={() => setAba('entrar')} />
        )}
      </div>
    </div>
  );
}

function FormularioEntrar({ onAutenticado }: LoginPageProps) {
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
      if (err instanceof SolicitacaoPendenteError) {
        setErro(err.message);
      } else if (err instanceof AcessoNaoAutorizadoError) {
        setErro('Credenciais inválidas ou conta sem acesso ao Painel Profissional.');
      } else {
        setErro('Não foi possível entrar. Tente novamente.');
      }
    } finally {
      setCarregando(false);
    }
  }

  return (
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
  );
}

interface FormularioSolicitarAcessoProps {
  /** Chamado após o cadastro ser aceito — a tela volta para "Entrar" com uma mensagem de sucesso. */
  onSolicitado: () => void;
}

function FormularioSolicitarAcesso({ onSolicitado }: FormularioSolicitarAcessoProps) {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [nome, setNome] = useState('');
  const [tipoProfissional, setTipoProfissional] = useState<TipoProfissionalSaude>('Medico');
  const [telefone, setTelefone] = useState('');
  const [registroProfissional, setRegistroProfissional] = useState('');
  const [dataNascimento, setDataNascimento] = useState('');
  const [carregando, setCarregando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErro(null);
    setSucesso(null);

    // N03 (RELATÓRIO 20260811_0005): trava de 18+ client-side — só UX, a
    // CHECK constraint `perfis_usuarios_maioridade` no banco é a barreira
    // real (ver `inserirPerfilPendente`, core/supabase.ts).
    if (calcularIdade(dataNascimento) < IDADE_MINIMA_ANOS) {
      setErro(`É necessário ter ${IDADE_MINIMA_ANOS} anos ou mais para solicitar acesso.`);
      return;
    }

    setCarregando(true);

    try {
      const resultado = await solicitarAcesso({
        email,
        senha,
        nome,
        tipoProfissional,
        telefone,
        registroProfissional,
        dataNascimento,
      });
      setSucesso(
        resultado.perfilCriadoImediatamente
          ? 'Solicitação enviada com sucesso. A nossa equipa foi notificada e vai analisar o seu acesso em breve.'
          : 'Quase lá: enviámos um e-mail de confirmação. Depois de confirmar, a sua solicitação segue para análise da nossa equipa.',
      );
      setTimeout(onSolicitado, 3500);
    } catch (err) {
      setErro(
        err instanceof AcessoNaoAutorizadoError
          ? err.message
          : 'Não foi possível enviar a sua solicitação. Tente novamente.',
      );
    } finally {
      setCarregando(false);
    }
  }

  if (sucesso) {
    return (
      <p
        role="status"
        className="mt-6 rounded-lg border border-clinical-success/40 bg-clinical-success/10 p-4 text-sm text-clinical-success"
      >
        {sucesso}
      </p>
    );
  }

  return (
    <form className="mt-6 space-y-4" onSubmit={handleSubmit}>
      <div>
        <label htmlFor="solicitar-nome" className="block text-sm font-medium text-slate-300">
          Nome
        </label>
        <input
          id="solicitar-nome"
          type="text"
          required
          autoComplete="name"
          value={nome}
          onChange={(event) => setNome(event.target.value)}
          className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
        />
      </div>

      <div>
        <label htmlFor="solicitar-tipo" className="block text-sm font-medium text-slate-300">
          Área de atuação
        </label>
        <select
          id="solicitar-tipo"
          required
          value={tipoProfissional}
          onChange={(event) => setTipoProfissional(event.target.value as TipoProfissionalSaude)}
          className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
        >
          {OPCOES_TIPO_PROFISSIONAL.map((opcao) => (
            <option key={opcao.value} value={opcao.value}>
              {opcao.label}
            </option>
          ))}
        </select>
      </div>

      <div>
        <label htmlFor="solicitar-registro" className="block text-sm font-medium text-slate-300">
          Registro Profissional (CRM/CRN/CREFITO/CREF)
        </label>
        <input
          id="solicitar-registro"
          type="text"
          required
          value={registroProfissional}
          onChange={(event) => setRegistroProfissional(event.target.value)}
          placeholder="Ex.: CRM-SP 123456"
          className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
        />
        <p className="mt-1 text-xs text-clinical-muted">
          Visível ao Admin durante a aprovação — sem validação de formato (cada conselho tem o seu).
        </p>
      </div>

      <div>
        <label htmlFor="solicitar-nascimento" className="block text-sm font-medium text-slate-300">
          Data de nascimento
        </label>
        <input
          id="solicitar-nascimento"
          type="date"
          required
          autoComplete="bday"
          value={dataNascimento}
          onChange={(event) => setDataNascimento(event.target.value)}
          className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
        />
        <p className="mt-1 text-xs text-clinical-muted">É necessário ter 18 anos ou mais.</p>
      </div>

      <div>
        <label htmlFor="solicitar-telefone" className="block text-sm font-medium text-slate-300">
          Telefone
        </label>
        <input
          id="solicitar-telefone"
          type="tel"
          required
          autoComplete="tel"
          value={telefone}
          onChange={(event) => setTelefone(event.target.value)}
          placeholder="(11) 90000-0000"
          className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
        />
      </div>

      <div>
        <label htmlFor="solicitar-email" className="block text-sm font-medium text-slate-300">
          E-mail
        </label>
        <input
          id="solicitar-email"
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
        />
      </div>

      <div>
        <label htmlFor="solicitar-senha" className="block text-sm font-medium text-slate-300">
          Senha
        </label>
        <input
          id="solicitar-senha"
          type="password"
          required
          minLength={6}
          autoComplete="new-password"
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
        {carregando ? 'Enviando...' : 'Solicitar Acesso'}
      </button>
    </form>
  );
}
