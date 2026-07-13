import { useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import { invitePatientByEmail } from '../services/vinculosApi';

interface InvitePatientModalProps {
  onClose: () => void;
  onSuccess: (pacienteEmail: string, alreadyInvited: boolean) => void;
}

type Estado = 'idle' | 'enviando' | 'erro';

const MANAGE_LINK_ENDPOINT = import.meta.env.VITE_MANAGE_PROFESSIONAL_LINK_ENDPOINT;

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Convite B2B (Adendo v4, F.2/F.3) — dispara `criar_vinculo` a partir do
 * e-mail do paciente. O vínculo nasce `pendente` no servidor: fechar este
 * modal com sucesso significa "o convite foi enviado", nunca "o profissional
 * já pode ver os dados deste paciente" — isso só acontece quando o próprio
 * paciente aceita, no app mobile (`aceitar_vinculo`).
 */
export function InvitePatientModal({ onClose, onSuccess }: InvitePatientModalProps) {
  const [email, setEmail] = useState('');
  const [estado, setEstado] = useState<Estado>('idle');
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  const emailValido = EMAIL_REGEX.test(email.trim());
  const enviando = estado === 'enviando';

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!emailValido || enviando) return;

    setEstado('enviando');
    setMensagemErro(null);

    if (!MANAGE_LINK_ENDPOINT) {
      setEstado('erro');
      setMensagemErro('Convite indisponível: endpoint não configurado neste ambiente.');
      return;
    }

    const { data: sessionData } = await supabase.auth.getSession();
    const accessToken = sessionData.session?.access_token;
    if (!accessToken) {
      setEstado('erro');
      setMensagemErro('Sessão expirada. Atualize a página e tente novamente.');
      return;
    }

    const resultado = await invitePatientByEmail(email.trim(), accessToken, MANAGE_LINK_ENDPOINT);

    if (!resultado.success) {
      setEstado('erro');
      setMensagemErro(resultado.errorMessage ?? 'Não foi possível enviar o convite.');
      return;
    }

    onSuccess(email.trim(), Boolean(resultado.alreadyInvited));
  }

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-clinical-bg/80 p-4">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="invite-patient-modal-title"
        className="w-full max-w-md rounded-2xl border border-clinical-border bg-clinical-surface p-6"
      >
        <header className="mb-5">
          <p className="text-xs uppercase tracking-wide text-clinical-muted">Novo vínculo</p>
          <h2 id="invite-patient-modal-title" className="text-lg font-semibold text-slate-100">
            Convidar Paciente
          </h2>
          <p className="mt-1 text-sm text-clinical-muted">
            O paciente recebe o convite no app e decide se aceita. Nenhum dado é compartilhado até lá.
          </p>
        </header>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor="paciente-email" className="block text-sm font-medium text-slate-300">
              E-mail do paciente
            </label>
            <input
              id="paciente-email"
              type="email"
              required
              autoFocus
              disabled={enviando}
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              placeholder="paciente@exemplo.com"
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          </div>

          {estado === 'erro' && mensagemErro && (
            <p role="alert" className="text-sm text-clinical-critical">
              {mensagemErro}
            </p>
          )}

          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              disabled={enviando}
              className="rounded-lg border border-clinical-border px-4 py-2 text-sm text-clinical-muted transition hover:text-slate-100 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Cancelar
            </button>
            <button
              type="submit"
              disabled={!emailValido || enviando}
              className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {enviando ? 'Enviando convite...' : 'Enviar Convite'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
