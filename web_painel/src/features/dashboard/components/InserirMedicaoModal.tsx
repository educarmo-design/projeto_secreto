import { useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import type { Database } from '@/core/types/database';

type MetricaDiariaInsert = Database['public']['Tables']['metricas_saude_diarias']['Insert'];

interface InserirMedicaoModalProps {
  pacienteId: string;
  onClose: () => void;
  onSalvo: () => void;
}

type Estado = 'formulario' | 'confirmando_sobrescrita' | 'salvando' | 'erro';

function hojeISO(): string {
  return new Date().toISOString().split('T')[0] ?? '';
}

/**
 * N07 (RELATÓRIO 20260812_0008) — "Inserir Medição Clínica": o profissional
 * grava Peso/Massa Magra manualmente para um dia específico, insumo direto
 * do Motor Metabólico (`calcular_motor_metabolico`).
 *
 * Proteção de sobrescrita (pedido explícito do fundador): antes do
 * `.upsert()`, um `SELECT` verifica se `metricas_saude_diarias` já tem
 * QUALQUER dado naquele dia (não só peso/massa magra — um dia com passos/FC
 * vindos do smartwatch também conta) para aquele paciente. Se sim, a tela
 * troca pra um passo de confirmação explícito ("Já existem dados... Deseja
 * sobrescrever?") — só prossegue com o `.upsert()` depois do profissional
 * clicar em "Sobrescrever". Sem dado prévio, salva direto.
 *
 * `.upsert()` de UMA linha por vez (não um lote) — o payload só inclui
 * `peso_kg`/`massa_magra_kg`/`origem`/`atualizado_em`; em conflito, o
 * PostgREST faz `ON CONFLICT DO UPDATE SET` só dessas colunas, preservando
 * o que o smartwatch já tiver gravado no resto da linha (passos, FC,
 * sono...). Diferente do bug histórico de "upsert destrutivo" (RELATÓRIO
 * 20260811_0001), que era especificamente sobre MÚLTIPLAS linhas
 * heterogêneas num único `.upsert()` de lote — aqui é sempre uma linha.
 *
 * Escrita autorizada por `metricas_saude_diarias_insert_profissional_
 * vinculado`/`_update_profissional_vinculado` (`20260812100000`) — exige
 * vínculo ATIVO com o paciente; sem isso, o Postgres recusa antes mesmo do
 * `.upsert()` chegar perto de qualquer linha alheia.
 */
export function InserirMedicaoModal({ pacienteId, onClose, onSalvo }: InserirMedicaoModalProps) {
  const [data, setData] = useState(hojeISO());
  const [pesoKg, setPesoKg] = useState('');
  const [massaMagraKg, setMassaMagraKg] = useState('');
  const [estado, setEstado] = useState<Estado>('formulario');
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

  const pesoValido = pesoKg.trim() ? Number(pesoKg) > 0 : true;
  const massaMagraValida = massaMagraKg.trim() ? Number(massaMagraKg) > 0 : true;
  const temAlgumValor = pesoKg.trim() !== '' || massaMagraKg.trim() !== '';

  async function verificarConflitoEEnviar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!temAlgumValor || !pesoValido || !massaMagraValida) return;

    setEstado('salvando');
    setMensagemErro(null);

    const { data: existente, error: erroSelect } = await supabase
      .from('metricas_saude_diarias')
      .select('id')
      .eq('usuario_id_anonimo', pacienteId)
      .eq('data_referencia', data)
      .maybeSingle();

    if (erroSelect) {
      setEstado('erro');
      setMensagemErro(erroSelect.message);
      return;
    }

    if (existente) {
      setEstado('confirmando_sobrescrita');
      return;
    }

    await salvar();
  }

  async function salvar() {
    setEstado('salvando');
    setMensagemErro(null);

    const payload: MetricaDiariaInsert = {
      usuario_id_anonimo: pacienteId,
      data_referencia: data,
      origem: 'manual_profissional',
      atualizado_em: new Date().toISOString(),
      ...(pesoKg.trim() ? { peso_kg: Number(pesoKg) } : {}),
      ...(massaMagraKg.trim() ? { massa_magra_kg: Number(massaMagraKg) } : {}),
    };

    const { error } = await supabase
      .from('metricas_saude_diarias')
      .upsert(payload, { onConflict: 'usuario_id_anonimo,data_referencia' });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    onSalvo();
  }

  const salvando = estado === 'salvando';

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-clinical-bg/80 p-4">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="inserir-medicao-titulo"
        className="w-full max-w-md rounded-2xl border border-clinical-border bg-clinical-surface p-6"
      >
        {estado === 'confirmando_sobrescrita' ? (
          <>
            <header className="mb-5">
              <p className="text-xs uppercase tracking-wide text-clinical-warning">Atenção</p>
              <h2 className="text-lg font-semibold text-slate-100">Sobrescrever dados existentes?</h2>
            </header>
            <p className="text-sm text-clinical-muted">
              Já existem dados de telemetria para{' '}
              <span className="font-mono text-slate-200">{formatarDataCurta(data)}</span> — podem ter vindo de um
              smartwatch sincronizado. Sobrescrever grava só peso/massa magra; os demais campos (passos, FC, sono...)
              não são tocados.
            </p>
            <div className="mt-6 flex justify-end gap-3">
              <button
                type="button"
                onClick={() => setEstado('formulario')}
                className="rounded-lg border border-clinical-border px-4 py-2 text-sm text-clinical-muted transition hover:text-slate-100"
              >
                Cancelar
              </button>
              <button
                type="button"
                onClick={() => void salvar()}
                className="rounded-lg bg-clinical-warning px-4 py-2 text-sm font-medium text-clinical-bg transition hover:opacity-90"
              >
                Sobrescrever
              </button>
            </div>
          </>
        ) : (
          <>
            <header className="mb-5">
              <p className="text-xs uppercase tracking-wide text-clinical-muted">Telemetria manual</p>
              <h2 id="inserir-medicao-titulo" className="text-lg font-semibold text-slate-100">
                Inserir Medição Clínica
              </h2>
              <p className="mt-1 text-sm text-clinical-muted">
                Grava direto em <code className="font-mono text-xs">metricas_saude_diarias</code> — mesma tabela do
                smartwatch. Insumo do Motor Metabólico (N07).
              </p>
            </header>

            <form onSubmit={(event) => void verificarConflitoEEnviar(event)} className="space-y-4">
              <div>
                <label htmlFor="medicao-data" className="block text-sm font-medium text-slate-300">
                  Data
                </label>
                <input
                  id="medicao-data"
                  type="date"
                  required
                  max={hojeISO()}
                  disabled={salvando}
                  value={data}
                  onChange={(event) => setData(event.target.value)}
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                />
              </div>

              <div>
                <label htmlFor="medicao-peso" className="block text-sm font-medium text-slate-300">
                  Peso (kg)
                </label>
                <input
                  id="medicao-peso"
                  type="number"
                  min="0"
                  step="0.1"
                  disabled={salvando}
                  value={pesoKg}
                  onChange={(event) => setPesoKg(event.target.value)}
                  placeholder="Ex.: 80.0"
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                />
              </div>

              <div>
                <label htmlFor="medicao-massa-magra" className="block text-sm font-medium text-slate-300">
                  Massa Magra (kg)
                </label>
                <input
                  id="medicao-massa-magra"
                  type="number"
                  min="0"
                  step="0.1"
                  disabled={salvando}
                  value={massaMagraKg}
                  onChange={(event) => setMassaMagraKg(event.target.value)}
                  placeholder="Ex.: 65.0 (bioimpedância)"
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                />
              </div>

              {!temAlgumValor && (
                <p className="text-xs text-clinical-muted">Informe pelo menos Peso ou Massa Magra.</p>
              )}
              {estado === 'erro' && mensagemErro && (
                <p role="alert" className="text-sm text-clinical-critical">
                  {mensagemErro}
                </p>
              )}

              <div className="flex justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={onClose}
                  disabled={salvando}
                  className="rounded-lg border border-clinical-border px-4 py-2 text-sm text-clinical-muted transition hover:text-slate-100 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  Cancelar
                </button>
                <button
                  type="submit"
                  disabled={salvando || !temAlgumValor || !pesoValido || !massaMagraValida}
                  className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {salvando ? 'Verificando...' : 'Salvar'}
                </button>
              </div>
            </form>
          </>
        )}
      </div>
    </div>
  );
}

function formatarDataCurta(dataISO: string): string {
  return new Date(`${dataISO}T00:00:00`).toLocaleDateString('pt-BR');
}
