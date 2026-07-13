import { useEffect } from 'react';

export type ToastVariant = 'success' | 'error';

export interface ToastMessage {
  variant: ToastVariant;
  text: string;
}

interface ToastProps {
  toast: ToastMessage;
  onDismiss: () => void;
  durationMs?: number;
}

/**
 * Notificação transitória mínima — não há lib de toast neste painel
 * (sonner/react-hot-toast/notistack: nenhuma no package.json), e introduzir
 * uma dependência nova só para uma tela não se justifica aqui. Auto-descarta
 * depois de [durationMs]; também pode ser fechada a mão. Mesma paleta
 * clinical e mesmos `role="status"`/`role="alert"` já usados inline no resto
 * do painel (ver GarminPrescriptionForm.tsx) — só que fixada no canto da
 * tela, para não depender de o formulário que a disparou ainda estar
 * montado (o modal de convite fecha antes da notificação sumir).
 */
export function Toast({ toast, onDismiss, durationMs = 5000 }: ToastProps) {
  useEffect(() => {
    const timeoutId = setTimeout(onDismiss, durationMs);
    return () => clearTimeout(timeoutId);
  }, [toast, onDismiss, durationMs]);

  const isError = toast.variant === 'error';

  return (
    <div
      role={isError ? 'alert' : 'status'}
      className={`fixed bottom-6 right-6 z-50 flex max-w-sm items-start gap-3 rounded-xl border p-4 ${
        isError
          ? 'border-clinical-critical/40 bg-clinical-critical/10 text-clinical-critical'
          : 'border-clinical-success/40 bg-clinical-success/10 text-clinical-success'
      }`}
    >
      <p className="flex-1 text-sm">{toast.text}</p>
      <button
        type="button"
        onClick={onDismiss}
        className="text-xs uppercase tracking-wide opacity-70 transition hover:opacity-100"
        aria-label="Fechar notificação"
      >
        Fechar
      </button>
    </div>
  );
}
