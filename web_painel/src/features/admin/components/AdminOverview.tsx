import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '@/core/supabase';

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/** Home do Admin: contagem rápida da fila de aprovação + atalho para a Sala de Espera (`AdminDashboard`) + fila de revisão do catálogo de alimentos (RELATÓRIO 20260824_0001). */
export function AdminOverview() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [totalPendentes, setTotalPendentes] = useState(0);
  const [totalAlimentosRevisao, setTotalAlimentosRevisao] = useState(0);
  const [totalMedidasRevisao, setTotalMedidasRevisao] = useState(0);

  useEffect(() => {
    let cancelado = false;

    async function carregar() {
      setEstado('carregando');

      const [pendentesResp, alimentosResp, medidasResp] = await Promise.all([
        supabase
          .from('perfis_usuarios')
          .select('id', { count: 'exact', head: true })
          .eq('status_aprovacao', 'pendente'),
        supabase
          .from('alimentos_referencia')
          .select('id', { count: 'exact', head: true })
          .eq('revisao_necessaria', true),
        supabase
          .from('alimentos_medidas_caseiras')
          .select('id', { count: 'exact', head: true })
          .eq('revisao_necessaria', true),
      ]);

      if (cancelado) return;
      if (pendentesResp.error || alimentosResp.error || medidasResp.error) {
        setEstado('erro');
        return;
      }
      setTotalPendentes(pendentesResp.count ?? 0);
      setTotalAlimentosRevisao(alimentosResp.count ?? 0);
      setTotalMedidasRevisao(medidasResp.count ?? 0);
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
        <h1 className="text-lg font-semibold text-slate-100">Visão Geral</h1>
        <p className="text-sm text-clinical-muted">Estado atual da plataforma.</p>
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
          <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
            <p className="text-xs uppercase tracking-wide text-clinical-muted">
              Solicitações pendentes
            </p>
            <p className="mt-2 text-3xl font-semibold text-slate-100">
              {estado === 'carregando' ? '—' : totalPendentes}
            </p>
            <Link
              to="/admin/aprovacoes"
              className="mt-3 inline-block text-xs text-clinical-primary hover:underline"
            >
              Ir para a Sala de Espera →
            </Link>
          </div>

          <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
            <p className="text-xs uppercase tracking-wide text-clinical-muted">
              Alimentos em revisão
            </p>
            <p className="mt-2 text-3xl font-semibold text-slate-100">
              {estado === 'carregando' ? '—' : totalAlimentosRevisao}
            </p>
            <Link
              to="/admin/revisao/alimentos"
              className="mt-3 inline-block text-xs text-clinical-primary hover:underline"
            >
              Ver fila de revisão →
            </Link>
          </div>

          <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
            <p className="text-xs uppercase tracking-wide text-clinical-muted">
              Medidas caseiras em revisão
            </p>
            <p className="mt-2 text-3xl font-semibold text-slate-100">
              {estado === 'carregando' ? '—' : totalMedidasRevisao}
            </p>
            <Link
              to="/admin/revisao/medidas-caseiras"
              className="mt-3 inline-block text-xs text-clinical-primary hover:underline"
            >
              Ver fila de revisão →
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
