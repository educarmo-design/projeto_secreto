import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { useParams } from 'react-router-dom';
import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { supabase, type ProfissionalAutenticado } from '@/core/supabase';
import type { Database } from '@/core/types/database';

type MetricaDiariaRow = Database['public']['Tables']['metricas_saude_diarias']['Row'];
type EventoAnomaliaRow = Database['public']['Tables']['eventos_anomalias_saude']['Row'];

interface PatientDetailsProps {
  profissional: ProfissionalAutenticado;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro' | 'sem_acesso';

const DIAS_HISTORICO = 90;

const tooltipStyle = {
  backgroundColor: '#111827',
  border: '1px solid #1F2937',
  borderRadius: 8,
  fontSize: 12,
};

/**
 * Clinical Analytics — visão bruta e real do paciente para o profissional.
 *
 * Regra de Blindagem ANVISA (PRD Mestre §3/§5): a versão CONSUMIDORA (app
 * mobile) nunca pode apresentar estes mesmos números como "score de
 * saúde"/"risco clínico" — só como pontos/metas de jogo (ver
 * `HealthScoreResult` no app Flutter). Esta tela é o oposto por desenho:
 * sua audiência (Médico/Nutricionista com vínculo ATIVO em
 * `vinculos_profissional_paciente`) é exatamente o público para quem a
 * leitura clínica direta é apropriada — não reaproveite estes componentes
 * na experiência do app mobile.
 */
export function PatientDetails({ profissional }: PatientDetailsProps) {
  const { pacienteId } = useParams<{ pacienteId: string }>();
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [metricas, setMetricas] = useState<MetricaDiariaRow[]>([]);
  const [anomalias, setAnomalias] = useState<EventoAnomaliaRow[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  useEffect(() => {
    if (!pacienteId) return;
    const idPaciente = pacienteId;
    let cancelado = false;

    async function carregar() {
      setEstado('carregando');
      setMensagemErro(null);

      const desde = new Date();
      desde.setDate(desde.getDate() - DIAS_HISTORICO);
      const desdeDataReferencia = desde.toISOString().split('T')[0] ?? '';

      const [metricasResult, anomaliasResult, vinculoResult] = await Promise.all([
        supabase
          .from('metricas_saude_diarias')
          .select('*')
          .eq('usuario_id_anonimo', idPaciente)
          .gte('data_referencia', desdeDataReferencia)
          .order('data_referencia', { ascending: true }),
        supabase
          .from('eventos_anomalias_saude')
          .select('*')
          .eq('usuario_id_anonimo', idPaciente)
          .gte('detectado_em', desde.toISOString())
          .order('detectado_em', { ascending: false }),
        // Correção (mesmo achado do PatientList, ver RELATÓRIO): o vínculo
        // real, desde a unificação do Zero Trust (20260713140000), é
        // `vinculos_profissional_paciente` com `status = 'ativo'` — não
        // `planejamento_clinico`. RLS de `metricas_saude_diarias`/
        // `eventos_anomalias_saude` já usa essa fonte; ler daqui a mesma
        // fonte evita o "sem_acesso" falso-negativo que a tabela antiga
        // causava para quem tinha vínculo mas nunca teve prescrição.
        supabase
          .from('vinculos_profissional_paciente')
          .select('id')
          .eq('profissional_id', profissional.id)
          .eq('paciente_id', idPaciente)
          .eq('status', 'ativo')
          .limit(1),
      ]);

      if (cancelado) return;

      if (metricasResult.error || anomaliasResult.error || vinculoResult.error) {
        setEstado('erro');
        setMensagemErro(
          metricasResult.error?.message ??
            anomaliasResult.error?.message ??
            vinculoResult.error?.message ??
            'Erro desconhecido.',
        );
        return;
      }

      // Auditoria de Seguradora não tem vínculo individual em
      // `vinculos_profissional_paciente` (não é uma relação de cuidado
      // pessoa-a-pessoa) — só Médico/Nutricionista precisam desse vínculo
      // para ver dados brutos de um paciente específico.
      const temVinculo = profissional.ehSeguradora || (vinculoResult.data?.length ?? 0) > 0;
      if (!temVinculo) {
        setEstado('sem_acesso');
        return;
      }

      setMetricas(metricasResult.data ?? []);
      setAnomalias(anomaliasResult.data ?? []);
      setEstado('sucesso');
    }

    void carregar();
    return () => {
      cancelado = true;
    };
  }, [pacienteId, profissional.id, profissional.ehSeguradora]);

  const dadosGlicemia = useMemo(
    () =>
      metricas
        .filter((m) => m.glicose_jejum !== null)
        .map((m) => ({ data: formatarDataCurta(m.data_referencia), valor: m.glicose_jejum })),
    [metricas],
  );

  const dadosPressao = useMemo(
    () =>
      metricas
        .filter((m) => m.pressao_sistolica !== null || m.pressao_diastolica !== null)
        .map((m) => ({
          data: formatarDataCurta(m.data_referencia),
          sistolica: m.pressao_sistolica,
          diastolica: m.pressao_diastolica,
        })),
    [metricas],
  );

  const dadosHrv = useMemo(
    () =>
      metricas
        .filter((m) => m.hrv_medio !== null)
        .map((m) => ({ data: formatarDataCurta(m.data_referencia), valor: m.hrv_medio })),
    [metricas],
  );

  const mediaHrv = useMemo(() => {
    const validos = dadosHrv.map((d) => d.valor).filter((v): v is number => v !== null);
    if (validos.length === 0) return null;
    return validos.reduce((total, atual) => total + atual, 0) / validos.length;
  }, [dadosHrv]);

  if (!pacienteId) {
    return <p className="text-clinical-critical">Paciente não especificado.</p>;
  }

  if (estado === 'carregando') {
    return <p className="text-clinical-muted">Carregando dados clínicos...</p>;
  }

  if (estado === 'erro') {
    return (
      <div
        role="alert"
        className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical"
      >
        Erro ao carregar dados do paciente: {mensagemErro}
      </div>
    );
  }

  if (estado === 'sem_acesso') {
    return (
      <div className="rounded-xl border border-clinical-warning/40 bg-clinical-warning/10 p-4 text-clinical-warning">
        Você não tem um vínculo clínico ativo (prescrição registrada) com este paciente.
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <header>
        <p className="text-xs uppercase tracking-wide text-clinical-muted">Paciente (UUID anônimo)</p>
        <h1 className="font-mono text-lg text-slate-100">{pacienteId}</h1>
        <p className="mt-1 text-sm text-clinical-muted">
          Últimos {DIAS_HISTORICO} dias · {metricas.length} registros · {anomalias.length} eventos na
          Caixa Preta
        </p>
        <p className="mt-1 text-xs text-clinical-muted">
          Visualizado por {profissional.nome ?? profissional.tipoProfissional ?? 'Administrador'} em{' '}
          {formatarDataHoraExata(new Date().toISOString())}
        </p>
      </header>

      <section className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <ChartCard titulo="Evolução da Glicemia" subtitulo="Glicose em jejum (mg/dL)">
          {dadosGlicemia.length === 0 ? (
            <EstadoVazioGrafico />
          ) : (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={dadosGlicemia}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1F2937" />
                <XAxis dataKey="data" stroke="#94A3B8" fontSize={12} />
                <YAxis stroke="#94A3B8" fontSize={12} domain={['auto', 'auto']} />
                <Tooltip contentStyle={tooltipStyle} />
                <Line
                  type="monotone"
                  dataKey="valor"
                  stroke="#0EA5E9"
                  strokeWidth={2}
                  dot={false}
                  name="Glicose (mg/dL)"
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </ChartCard>

        <ChartCard titulo="Tendência de Pressão Arterial" subtitulo="Sistólica / Diastólica (mmHg)">
          {dadosPressao.length === 0 ? (
            <EstadoVazioGrafico />
          ) : (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={dadosPressao}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1F2937" />
                <XAxis dataKey="data" stroke="#94A3B8" fontSize={12} />
                <YAxis stroke="#94A3B8" fontSize={12} domain={['auto', 'auto']} />
                <Tooltip contentStyle={tooltipStyle} />
                <Legend />
                <Line
                  type="monotone"
                  dataKey="sistolica"
                  stroke="#DC2626"
                  strokeWidth={2}
                  dot={false}
                  name="Sistólica"
                />
                <Line
                  type="monotone"
                  dataKey="diastolica"
                  stroke="#F59E0B"
                  strokeWidth={2}
                  dot={false}
                  name="Diastólica"
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </ChartCard>

        <ChartCard
          titulo="Média de HRV"
          subtitulo={
            mediaHrv !== null ? `Média do período: ${mediaHrv.toFixed(1)} ms` : 'Sem dados suficientes'
          }
        >
          {dadosHrv.length === 0 ? (
            <EstadoVazioGrafico />
          ) : (
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={dadosHrv}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1F2937" />
                <XAxis dataKey="data" stroke="#94A3B8" fontSize={12} />
                <YAxis stroke="#94A3B8" fontSize={12} domain={['auto', 'auto']} />
                <Tooltip contentStyle={tooltipStyle} />
                <Line
                  type="monotone"
                  dataKey="valor"
                  stroke="#16A34A"
                  strokeWidth={2}
                  dot={false}
                  name="HRV (ms)"
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </ChartCard>

        <ChartCard titulo="Histórico de Eventos de Exceção" subtitulo="Caixa Preta — carimbo de data/hora exato">
          {anomalias.length === 0 ? (
            <EstadoVazioGrafico mensagem="Nenhuma anomalia registrada no período." />
          ) : (
            <div className="max-h-60 overflow-y-auto">
              <table className="w-full text-left text-sm">
                <thead className="sticky top-0 bg-clinical-surface text-xs uppercase text-clinical-muted">
                  <tr>
                    <th className="py-2 pr-3">Data/Hora</th>
                    <th className="py-2 pr-3">Tipo</th>
                    <th className="py-2 pr-3">Parâmetro</th>
                    <th className="py-2 pr-3">Valor</th>
                    <th className="py-2">Severidade</th>
                  </tr>
                </thead>
                <tbody>
                  {anomalias.map((evento) => (
                    <tr key={evento.id} className="border-t border-clinical-border">
                      <td className="py-2 pr-3 font-mono text-xs text-slate-300">
                        {formatarDataHoraExata(evento.detectado_em)}
                      </td>
                      <td className="py-2 pr-3 text-slate-200">{evento.tipo_anomalia}</td>
                      <td className="py-2 pr-3 text-slate-300">{evento.parametro}</td>
                      <td className="py-2 pr-3 text-slate-300">{evento.valor_detectado}</td>
                      <td className="py-2">
                        <SeveridadeBadge severidade={evento.severidade} />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </ChartCard>
      </section>
    </div>
  );
}

interface ChartCardProps {
  titulo: string;
  subtitulo: string;
  children: ReactNode;
}

function ChartCard({ titulo, subtitulo, children }: ChartCardProps) {
  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-5">
      <h2 className="text-sm font-semibold text-slate-100">{titulo}</h2>
      <p className="mb-3 text-xs text-clinical-muted">{subtitulo}</p>
      {children}
    </div>
  );
}

function EstadoVazioGrafico({ mensagem = 'Sem dados no período.' }: { mensagem?: string }) {
  return (
    <div className="flex h-60 items-center justify-center text-sm text-clinical-muted">{mensagem}</div>
  );
}

function SeveridadeBadge({ severidade }: { severidade: string }) {
  const critico = severidade === 'critico';
  return (
    <span
      className={`rounded-full px-2 py-0.5 text-xs font-medium ${
        critico
          ? 'bg-clinical-critical/20 text-clinical-critical'
          : 'bg-clinical-warning/20 text-clinical-warning'
      }`}
    >
      {severidade}
    </span>
  );
}

function formatarDataCurta(dataIso: string): string {
  const data = new Date(`${dataIso}T00:00:00`);
  return data.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
}

function formatarDataHoraExata(dataIso: string): string {
  return new Date(dataIso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}
