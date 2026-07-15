import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase, type ProfissionalAutenticado } from '@/core/supabase';

interface DashboardProps {
  profissional: ProfissionalAutenticado;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * Home do painel profissional — primeira tela após o login. A contagem usa
 * `perfis_pacientes_vinculados` (não `vinculos_profissional_paciente`
 * diretamente, que não tem policy de SELECT ampla para o cliente e nem tipo
 * gerado aqui): é a mesma view, já filtrada por vínculo ATIVO, que
 * `PatientList` consome.
 */
export function Dashboard({ profissional }: DashboardProps) {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [totalPacientes, setTotalPacientes] = useState(0);

  useEffect(() => {
    let cancelado = false;

    async function carregar() {
      setEstado('carregando');
      const { count, error } = await supabase
        .from('perfis_pacientes_vinculados')
        .select('id', { count: 'exact', head: true });

      if (cancelado) return;
      if (error) {
        setEstado('erro');
        return;
      }
      setTotalPacientes(count ?? 0);
      setEstado('sucesso');
    }

    void carregar();
    return () => {
      cancelado = true;
    };
  }, []);

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">
          Olá, {profissional.nome ?? profissional.tipoProfissional ?? 'Profissional'}
        </h1>
        <p className="text-sm text-clinical-muted">Resumo rápido da sua prática no painel.</p>
      </header>

      {estado === 'erro' ? (
        <div
          role="alert"
          className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical"
        >
          Não foi possível carregar o resumo.
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <StatCard
            titulo="Pacientes vinculados"
            valor={estado === 'carregando' ? '—' : String(totalPacientes)}
            descricao="Vínculos ativos com você"
          />
        </div>
      )}

      <div className="mt-8 flex flex-wrap gap-3">
        <Link
          to="/pacientes"
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
        >
          Ver Meus Pacientes/Alunos
        </Link>
      </div>
    </div>
  );
}

function StatCard({
  titulo,
  valor,
  descricao,
}: {
  titulo: string;
  valor: string;
  descricao: string;
}) {
  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
      <p className="text-xs uppercase tracking-wide text-clinical-muted">{titulo}</p>
      <p className="mt-2 text-3xl font-semibold text-slate-100">{valor}</p>
      <p className="mt-1 text-xs text-clinical-muted">{descricao}</p>
    </div>
  );
}
