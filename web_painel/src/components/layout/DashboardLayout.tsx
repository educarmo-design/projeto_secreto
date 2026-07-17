import { useState } from 'react';
import { Outlet } from 'react-router-dom';
import { Menu } from 'lucide-react';
import type { ProfissionalAutenticado } from '@/core/supabase';
import { Sidebar } from './Sidebar';

interface DashboardLayoutProps {
  profissional: ProfissionalAutenticado;
  onSignOut: () => void;
}

/**
 * Casca visual das rotas protegidas: Sidebar fixa em ecrãs `md+`, colapsável
 * em overlay nos menores. `Outlet` renderiza a rota filha ativa — ver
 * App.tsx pela árvore de rotas envolvida por este layout.
 */
export function DashboardLayout({ profissional, onSignOut }: DashboardLayoutProps) {
  const [menuAberto, setMenuAberto] = useState(false);

  return (
    <div className="flex min-h-screen bg-clinical-bg">
      <Sidebar
        profissional={profissional}
        onSignOut={onSignOut}
        aberta={menuAberto}
        onFechar={() => setMenuAberto(false)}
      />

      <div className="flex min-h-screen flex-1 flex-col">
        <header className="flex items-center gap-3 border-b border-clinical-border px-4 py-3 md:hidden">
          <button
            type="button"
            onClick={() => setMenuAberto(true)}
            className="rounded-lg border border-clinical-border p-2 text-clinical-muted transition hover:text-slate-100"
            aria-label="Abrir menu"
          >
            <Menu size={20} />
          </button>
          <p className="text-sm font-medium text-slate-100">Painel B2B</p>
        </header>

        <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
