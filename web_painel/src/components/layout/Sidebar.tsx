import { NavLink } from 'react-router-dom';
import { X } from 'lucide-react';
import type { ProfissionalAutenticado } from '@/core/supabase';

interface NavItem {
  to: string;
  label: string;
  end?: boolean;
}

const ITENS_PROFISSIONAL: NavItem[] = [
  { to: '/', label: 'Dashboard', end: true },
  { to: '/pacientes', label: 'Meus Pacientes/Alunos' },
  { to: '/prescricoes', label: 'Prescrições' },
  { to: '/relatorios', label: 'Relatórios & Gráficos' },
  { to: '/insights', label: 'Insights' },
  { to: '/configuracoes', label: 'Configurações' },
];

const ITENS_ADMIN: NavItem[] = [
  { to: '/admin', label: 'Visão Geral', end: true },
  { to: '/admin/aprovacoes', label: 'Aprovação de Profissionais' },
  // N06 (RELATÓRIO 20260811_0005) — telas de manutenção administrativa.
  { to: '/admin/usuarios', label: 'Usuários' },
  { to: '/admin/profissionais', label: 'Profissionais' },
  { to: '/admin/atividades-fisicas', label: 'Atividades Físicas' },
  { to: '/admin/alergias', label: 'Alergias' },
  { to: '/admin/alimentos', label: 'Alimentos' },
  { to: '/admin/configuracoes', label: 'Configurações do Sistema' },
  // D3 (RELATÓRIO 20260811_0005) — Matriz de Permissões dinâmica.
  { to: '/admin/permissoes', label: 'Matriz de Permissões' },
];

interface SidebarProps {
  profissional: ProfissionalAutenticado;
  onSignOut: () => void;
  isOpen: boolean;
  onClose: () => void;
}

/**
 * Navegação lateral do Painel — visibilidade condicional por papel: a seção
 * "Profissional" só aparece para quem tem prática clínica própria
 * (`tipoProfissional` preenchido; um Admin puro, sem prática, não a vê), e a
 * seção "Administração" só para `isAdmin`. As duas podem coexistir para uma
 * conta que acumula os dois papéis. Nunca a barreira real de acesso — isso é
 * sempre RLS/checagem de rota (ver App.tsx); esconder um item aqui é só UX.
 *
 * O backdrop mobile é responsabilidade do `DashboardLayout` (que já tem o
 * estado `isSidebarOpen`); este componente só é a gaveta em si.
 */
export function Sidebar({ profissional, onSignOut, isOpen, onClose }: SidebarProps) {
  const mostrarProfissional = Boolean(profissional.tipoProfissional);

  return (
    <aside
      className={`fixed inset-y-0 left-0 z-50 flex w-64 shrink-0 flex-col border-r border-clinical-border bg-clinical-surface transform transition-transform duration-300 ease-in-out md:relative md:translate-x-0 ${
        isOpen ? 'translate-x-0' : '-translate-x-full'
      }`}
    >
      <div className="flex items-center justify-between border-b border-clinical-border px-5 py-4">
        <div>
          <p className="text-sm font-semibold tracking-wide text-slate-100">Painel B2B</p>
          <p className="text-xs text-clinical-muted">Área Profissional</p>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="rounded-lg p-1 text-clinical-muted transition hover:text-slate-100 md:hidden"
          aria-label="Fechar menu"
        >
          <X size={18} />
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-4">
        {mostrarProfissional && (
          <NavSection titulo="Profissional" itens={ITENS_PROFISSIONAL} onNavigate={onClose} />
        )}
        {profissional.isAdmin && (
          <NavSection titulo="Administração" itens={ITENS_ADMIN} onNavigate={onClose} />
        )}
      </nav>

      <div className="border-t border-clinical-border px-3 py-4">
        <div className="mb-3 px-2">
          <p className="truncate text-sm font-medium text-slate-100">
            {profissional.nome ?? profissional.tipoProfissional ?? 'Administrador'}
          </p>
          <p className="text-xs text-clinical-muted">
            {profissional.isAdmin ? 'Admin' : (profissional.tipoProfissional ?? 'Profissional')}
          </p>
        </div>
        <button
          type="button"
          onClick={onSignOut}
          className="w-full rounded-lg border border-clinical-border px-3 py-2 text-left text-sm text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical"
        >
          Sair
        </button>
      </div>
    </aside>
  );
}

function NavSection({
  titulo,
  itens,
  onNavigate,
}: {
  titulo: string;
  itens: NavItem[];
  onNavigate: () => void;
}) {
  return (
    <div className="mb-6">
      <p className="mb-2 px-2 text-xs font-semibold uppercase tracking-wide text-clinical-muted">
        {titulo}
      </p>
      <ul className="space-y-1">
        {itens.map((item) => (
          <li key={item.to}>
            <NavLink
              to={item.to}
              end={item.end}
              onClick={onNavigate}
              className={({ isActive }) =>
                `block rounded-lg px-3 py-2 text-sm transition ${
                  isActive
                    ? 'bg-clinical-primary/15 font-medium text-clinical-primary'
                    : 'text-slate-300 hover:bg-white/5 hover:text-slate-100'
                }`
              }
            >
              {item.label}
            </NavLink>
          </li>
        ))}
      </ul>
    </div>
  );
}
