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
 *
 * Padrão clássico de dashboard: o contêiner ocupa exatamente `h-screen` e
 * corta overflow; só o `<main>` rola (`overflow-y-auto`) — evita o duplo
 * scroll de página+sidebar que o `min-h-screen` anterior podia produzir.
 */
export function DashboardLayout({ profissional, onSignOut }: DashboardLayoutProps) {
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);

  return (
    <div className="flex h-screen w-full overflow-hidden bg-clinical-bg">
      <Sidebar
        profissional={profissional}
        onSignOut={onSignOut}
        isOpen={isSidebarOpen}
        onClose={() => setIsSidebarOpen(false)}
      />

      {isSidebarOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 md:hidden"
          onClick={() => setIsSidebarOpen(false)}
          aria-hidden="true"
        />
      )}

      <div className="flex flex-1 flex-col overflow-hidden">
        <header className="flex shrink-0 items-center justify-between border-b border-clinical-border bg-clinical-surface px-4 py-3 md:hidden">
          <p className="text-sm font-medium text-slate-100">Painel B2B</p>
          <button
            type="button"
            onClick={() => setIsSidebarOpen(true)}
            className="rounded-lg border border-clinical-border p-2 text-clinical-muted transition hover:text-slate-100"
            aria-label="Abrir menu"
          >
            <Menu size={20} />
          </button>
        </header>

        <main className="flex-1 overflow-y-auto p-4 md:p-8">
          <div className="mx-auto w-full max-w-6xl">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}
