import { useCallback, useEffect, useState } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { LoginPage } from './components/LoginPage';
import {
  obterProfissionalAtual,
  onAuthStateChange,
  signOutProfissional,
  type ProfissionalAutenticado,
} from '@/core/supabase';
import { PatientList } from './features/patients/components/PatientList';
import { PatientDetails } from './features/dashboard/components/PatientDetails';
import { GarminPrescriptionForm } from './features/prescriptions/components/GarminPrescriptionForm';

type EstadoAuth = 'carregando' | 'autenticado' | 'nao_autenticado';

/**
 * Casca do Painel Web: gate de autenticação + roteamento. Reavalia a
 * sessão a cada evento de `onAuthStateChange` (login/logout/refresh de
 * token) em vez de confiar num estado local que poderia ficar
 * dessincronizado do Supabase.
 */
export default function App() {
  const [estado, setEstado] = useState<EstadoAuth>('carregando');
  const [profissional, setProfissional] = useState<ProfissionalAutenticado | null>(null);

  const recarregarSessao = useCallback(async () => {
    const atual = await obterProfissionalAtual();
    setProfissional(atual);
    setEstado(atual ? 'autenticado' : 'nao_autenticado');
  }, []);

  useEffect(() => {
    void recarregarSessao();
    const unsubscribe = onAuthStateChange(() => {
      void recarregarSessao();
    });
    return unsubscribe;
  }, [recarregarSessao]);

  async function handleSignOut() {
    await signOutProfissional();
  }

  if (estado === 'carregando') {
    return (
      <div className="flex min-h-screen items-center justify-center bg-clinical-bg text-clinical-muted">
        Carregando...
      </div>
    );
  }

  if (estado === 'nao_autenticado' || !profissional) {
    return (
      <LoginPage
        onAutenticado={(novoProfissional) => {
          setProfissional(novoProfissional);
          setEstado('autenticado');
        }}
      />
    );
  }

  return (
    <div className="min-h-screen bg-clinical-bg">
      <header className="flex items-center justify-between border-b border-clinical-border px-6 py-4">
        <div>
          <p className="text-xs uppercase tracking-wide text-clinical-muted">Painel Profissional</p>
          <p className="font-medium text-slate-100">
            {profissional.nome ?? profissional.tipoProfissional}
          </p>
        </div>
        <button
          type="button"
          onClick={handleSignOut}
          className="rounded-lg border border-clinical-border px-3 py-1.5 text-sm text-clinical-muted transition hover:border-clinical-primary hover:text-slate-100"
        >
          Sair
        </button>
      </header>

      <main className="mx-auto max-w-6xl px-6 py-8">
        <Routes>
          <Route path="/" element={<PatientList profissional={profissional} />} />
          <Route
            path="/pacientes/:pacienteId"
            element={<PatientDetails profissional={profissional} />}
          />
          <Route
            path="/pacientes/:pacienteId/prescricao"
            element={<GarminPrescriptionForm profissional={profissional} />}
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}
