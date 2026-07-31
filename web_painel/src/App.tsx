import { useCallback, useEffect, useState } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { LoginPage } from './components/LoginPage';
import { UpdatePasswordPage } from './components/UpdatePasswordPage';
import { DashboardLayout } from './components/layout/DashboardLayout';
import { PlaceholderPage } from './components/layout/PlaceholderPage';
import {
  obterProfissionalAtual,
  onAuthStateChange,
  signOutProfissional,
  type ProfissionalAutenticado,
} from '@/core/supabase';
import { Dashboard } from './features/dashboard/components/Dashboard';
import { PatientList } from './features/patients/components/PatientList';
import { PatientDetails } from './features/dashboard/components/PatientDetails';
import { GarminPrescriptionForm } from './features/prescriptions/components/GarminPrescriptionForm';
import { AdminOverview } from './features/admin/components/AdminOverview';
import { AdminDashboard } from './features/admin/components/AdminDashboard';

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
      <Routes>
        {/* Rotas públicas: login e recuperação de senha */}
        <Route path="/login" element={
          <LoginPage
            onAutenticado={(novoProfissional) => {
              setProfissional(novoProfissional);
              setEstado('autenticado');
            }}
          />
        } />
        <Route path="/update-password" element={<UpdatePasswordPage />} />
        {/* Fallback para login em qualquer outra rota */}
        <Route path="*" element={<Navigate to="/login" replace />} />
      </Routes>
    );
  }

  // Admin puro (sem prática clínica própria): não há Dashboard profissional
  // para mostrar sem `tipoProfissional`, então a home dele é a Visão Geral do
  // backoffice — mesma exceção já documentada em `supabase.ts`/`signInProfissional`.
  const homeParaAdminPuro = profissional.isAdmin && !profissional.tipoProfissional;

  return (
    <Routes>
      <Route element={<DashboardLayout profissional={profissional} onSignOut={handleSignOut} />}>
        <Route
          path="/"
          element={
            homeParaAdminPuro ? (
              <Navigate to="/admin" replace />
            ) : (
              <Dashboard profissional={profissional} />
            )
          }
        />
        <Route path="/pacientes" element={<PatientList profissional={profissional} />} />
        <Route
          path="/pacientes/:pacienteId"
          element={<PatientDetails profissional={profissional} />}
        />
        <Route
          path="/pacientes/:pacienteId/prescricao"
          element={<GarminPrescriptionForm profissional={profissional} />}
        />
        <Route
          path="/prescricoes"
          element={
            <PlaceholderPage
              titulo="Prescrições"
              descricao='Em breve: lista consolidada de prescrições. Por agora, abra um paciente em "Meus Pacientes/Alunos" para prescrever.'
            />
          }
        />
        <Route
          path="/relatorios"
          element={
            <PlaceholderPage
              titulo="Relatórios & Gráficos"
              descricao="Em breve: relatórios agregados sobre a evolução dos seus pacientes."
            />
          }
        />
        <Route
          path="/insights"
          element={
            <PlaceholderPage
              titulo="Insights"
              descricao="Em breve: alertas e recomendações geradas a partir da telemetria dos seus pacientes."
            />
          }
        />
        <Route
          path="/configuracoes"
          element={
            <PlaceholderPage
              titulo="Configurações"
              descricao="Em breve: preferências da sua conta profissional."
            />
          }
        />
        {/* Rotas ocultas: sem link nenhum na Sidebar para quem não é admin
            (`Sidebar` só renderiza a seção "Administração" quando `isAdmin`),
            e mesmo que alguém digite a URL direto, os componentes abaixo não
            devolvem nenhuma linha — a RLS de `perfis_usuarios` já barra a
            query no banco antes de qualquer dado pendente aparecer. Este
            `Navigate` é só uma conveniência de UX, nunca a barreira real. */}
        <Route
          path="/admin"
          element={profissional.isAdmin ? <AdminOverview /> : <Navigate to="/" replace />}
        />
        <Route
          path="/admin/aprovacoes"
          element={profissional.isAdmin ? <AdminDashboard /> : <Navigate to="/" replace />}
        />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
