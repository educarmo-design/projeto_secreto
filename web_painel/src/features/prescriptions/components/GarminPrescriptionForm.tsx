import { useState, type FormEvent } from 'react';
import { useParams } from 'react-router-dom';
import { supabase, type ProfissionalAutenticado } from '@/core/supabase';
import type { PlanoTreinoEstrutura } from '@/core/types/database';
import { dispatchTrainingBlockToGarmin } from '../services/garminApi';

interface GarminPrescriptionFormProps {
  profissional: ProfissionalAutenticado;
}

type EstadoEnvio = 'idle' | 'salvando' | 'despachando' | 'sucesso' | 'erro';

const GARMIN_ENDPOINT = import.meta.env.VITE_GARMIN_DISPATCH_ENDPOINT;

/**
 * Prescrição estruturada de treino + integração Garmin. O fluxo tem duas
 * etapas distintas, cada uma com seu próprio estado defensivo — a
 * prescrição em si (`planejamento_clinico`, sempre persistida primeiro,
 * sob RLS já existente) e o despacho Server-to-Server para a Garmin
 * (best-effort: se falhar, a prescrição já está salva e pode ser
 * redespachada depois, `sincronizado_garmin` continua `false`).
 */
export function GarminPrescriptionForm({ profissional }: GarminPrescriptionFormProps) {
  const { pacienteId } = useParams<{ pacienteId: string }>();

  const [tipoTreino, setTipoTreino] = useState<PlanoTreinoEstrutura['tipoTreino']>('corrida');
  const [duracaoMinutos, setDuracaoMinutos] = useState(30);
  const [zonaFcAlvoMin, setZonaFcAlvoMin] = useState(120);
  const [zonaFcAlvoMax, setZonaFcAlvoMax] = useState(150);
  const [dataAgenda, setDataAgenda] = useState('');
  const [observacoes, setObservacoes] = useState('');

  const [estado, setEstado] = useState<EstadoEnvio>('idle');
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [garminWorkoutId, setGarminWorkoutId] = useState<string | null>(null);

  const erroValidacao = validar({ duracaoMinutos, zonaFcAlvoMin, zonaFcAlvoMax, dataAgenda });
  const enviando = estado === 'salvando' || estado === 'despachando';

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!pacienteId || erroValidacao) return;

    setMensagemErro(null);
    setGarminWorkoutId(null);
    setEstado('salvando');

    const estrutura: PlanoTreinoEstrutura = {
      tipoTreino,
      duracaoMinutos,
      zonaFcAlvoMin,
      zonaFcAlvoMax,
      dataAgenda,
      ...(observacoes.trim() ? { observacoes: observacoes.trim() } : {}),
    };

    const { data: planoInserido, error: erroInsercao } = await supabase
      .from('planejamento_clinico')
      .insert({
        profissional_id: profissional.id,
        paciente_id_anonimo: pacienteId,
        tipo_plano: 'treino_garmin',
        estrutura_plano_jsonb: estrutura,
        data_limite: dataAgenda,
        sincronizado_garmin: false,
      })
      .select('id')
      .single();

    if (erroInsercao || !planoInserido) {
      setEstado('erro');
      setMensagemErro(erroInsercao?.message ?? 'Não foi possível salvar a prescrição.');
      return;
    }

    if (!GARMIN_ENDPOINT) {
      // Prescrição já está salva e visível ao paciente/painel — só o
      // despacho automático para o relógio não está configurado neste
      // ambiente. Não é um erro fatal do fluxo de prescrição.
      setEstado('sucesso');
      return;
    }

    setEstado('despachando');
    const { data: sessionData } = await supabase.auth.getSession();
    const accessToken = sessionData.session?.access_token;

    if (!accessToken) {
      setEstado('erro');
      setMensagemErro('Sessão expirada — a prescrição foi salva, mas não pôde ser despachada à Garmin.');
      return;
    }

    const resultado = await dispatchTrainingBlockToGarmin(
      {
        planejamentoClinicoId: planoInserido.id,
        pacienteIdAnonimo: pacienteId,
        estrutura,
      },
      accessToken,
      GARMIN_ENDPOINT,
    );

    if (!resultado.success) {
      setEstado('erro');
      setMensagemErro(
        `Prescrição salva, mas o despacho à Garmin falhou: ${resultado.errorMessage ?? 'erro desconhecido'}.`,
      );
      return;
    }

    await supabase
      .from('planejamento_clinico')
      .update({ sincronizado_garmin: true })
      .eq('id', planoInserido.id);

    setGarminWorkoutId(resultado.garminWorkoutId ?? null);
    setEstado('sucesso');
  }

  if (!pacienteId) {
    return <p className="text-clinical-critical">Paciente não especificado.</p>;
  }

  return (
    <div className="max-w-xl">
      <header className="mb-6">
        <p className="text-xs uppercase tracking-wide text-clinical-muted">Nova prescrição</p>
        <h1 className="text-lg font-semibold text-slate-100">Planilha de Treino — Garmin</h1>
        <p className="mt-1 font-mono text-xs text-clinical-muted">Paciente: {pacienteId}</p>
      </header>

      <form onSubmit={handleSubmit} className="space-y-5 rounded-2xl border border-clinical-border bg-clinical-surface p-6">
        <div>
          <span className="block text-sm font-medium text-slate-300">Tipo de Treino</span>
          <div className="mt-2 flex gap-3">
            {(['corrida', 'ciclismo'] as const).map((opcao) => (
              <label
                key={opcao}
                className={`flex-1 cursor-pointer rounded-lg border px-4 py-2 text-center text-sm capitalize transition ${
                  tipoTreino === opcao
                    ? 'border-clinical-primary bg-clinical-primary/10 text-slate-100'
                    : 'border-clinical-border text-clinical-muted'
                }`}
              >
                <input
                  type="radio"
                  name="tipoTreino"
                  value={opcao}
                  checked={tipoTreino === opcao}
                  onChange={() => setTipoTreino(opcao)}
                  className="sr-only"
                />
                {opcao}
              </label>
            ))}
          </div>
        </div>

        <div>
          <label htmlFor="duracao" className="block text-sm font-medium text-slate-300">
            Duração (minutos)
          </label>
          <input
            id="duracao"
            type="number"
            min={1}
            max={600}
            required
            value={duracaoMinutos}
            onChange={(event) => setDuracaoMinutos(Number(event.target.value))}
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label htmlFor="fcMin" className="block text-sm font-medium text-slate-300">
              Zona FC alvo — mín. (bpm)
            </label>
            <input
              id="fcMin"
              type="number"
              min={40}
              max={220}
              required
              value={zonaFcAlvoMin}
              onChange={(event) => setZonaFcAlvoMin(Number(event.target.value))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
            />
          </div>
          <div>
            <label htmlFor="fcMax" className="block text-sm font-medium text-slate-300">
              Zona FC alvo — máx. (bpm)
            </label>
            <input
              id="fcMax"
              type="number"
              min={40}
              max={220}
              required
              value={zonaFcAlvoMax}
              onChange={(event) => setZonaFcAlvoMax(Number(event.target.value))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
            />
          </div>
        </div>

        <div>
          <label htmlFor="dataAgenda" className="block text-sm font-medium text-slate-300">
            Data da Agenda
          </label>
          <input
            id="dataAgenda"
            type="date"
            required
            value={dataAgenda}
            onChange={(event) => setDataAgenda(event.target.value)}
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>

        <div>
          <label htmlFor="observacoes" className="block text-sm font-medium text-slate-300">
            Observações (opcional)
          </label>
          <textarea
            id="observacoes"
            rows={3}
            value={observacoes}
            onChange={(event) => setObservacoes(event.target.value)}
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>

        {erroValidacao && <p className="text-sm text-clinical-warning">{erroValidacao}</p>}
        {estado === 'erro' && mensagemErro && (
          <p role="alert" className="text-sm text-clinical-critical">
            {mensagemErro}
          </p>
        )}
        {estado === 'sucesso' && (
          <p role="status" className="text-sm text-clinical-success">
            Prescrição salva{garminWorkoutId ? ` e despachada à Garmin (workout ${garminWorkoutId})` : ''}.
          </p>
        )}

        <button
          type="submit"
          disabled={enviando || Boolean(erroValidacao)}
          className="w-full rounded-lg bg-clinical-primary py-2 font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {estado === 'salvando' && 'Salvando prescrição...'}
          {estado === 'despachando' && 'Despachando para a Garmin...'}
          {(estado === 'idle' || estado === 'erro' || estado === 'sucesso') && 'Prescrever e Sincronizar'}
        </button>
      </form>
    </div>
  );
}

function validar(campos: {
  duracaoMinutos: number;
  zonaFcAlvoMin: number;
  zonaFcAlvoMax: number;
  dataAgenda: string;
}): string | null {
  if (campos.duracaoMinutos <= 0) return 'A duração deve ser maior que zero.';
  if (campos.zonaFcAlvoMin <= 0 || campos.zonaFcAlvoMax <= 0) {
    return 'As zonas de frequência cardíaca devem ser maiores que zero.';
  }
  if (campos.zonaFcAlvoMin >= campos.zonaFcAlvoMax) {
    return 'A zona de FC mínima deve ser menor que a máxima.';
  }
  if (!campos.dataAgenda) return 'Selecione a data da agenda.';
  return null;
}
