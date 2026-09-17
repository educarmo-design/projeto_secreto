import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import type { Database } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';

type TipoAtividade = Database['public']['Tables']['tipos_atividades_fisicas']['Row'];
type ObjetivoCodigo = 'emagrecimento' | 'manutencao' | 'hipertrofia' | 'outro';

interface AnamneseProfissionalViewProps {
  pacienteId: string;
  /** Chamado após salvar com sucesso — o pai (`PatientDetails`) usa isto
   * pra incrementar o gatilho de recálculo do `MotorMetabolicoV1Card`,
   * mesmo padrão já estabelecido para `InserirMedicaoModal`. */
  onSalvo?: () => void;
}

const ROTULO_OBJETIVO: Record<ObjetivoCodigo, string> = {
  emagrecimento: 'Emagrecimento',
  manutencao: 'Manutenção',
  hipertrofia: 'Hipertrofia',
  outro: 'Outro',
};

const DIAS_SEMANA: { valor: number; rotulo: string }[] = [
  { valor: 1, rotulo: 'Segunda' },
  { valor: 2, rotulo: 'Terça' },
  { valor: 3, rotulo: 'Quarta' },
  { valor: 4, rotulo: 'Quinta' },
  { valor: 5, rotulo: 'Sexta' },
  { valor: 6, rotulo: 'Sábado' },
  { valor: 0, rotulo: 'Domingo' },
];

interface LinhaAtividade {
  chave: string;
  diaSemana: number;
  atividadeId: string;
  minutos: string;
}

function linhaVazia(): LinhaAtividade {
  return { chave: crypto.randomUUID(), diaSemana: 1, atividadeId: '', minutos: '' };
}

const FORM_VAZIO = {
  pesoKg: '',
  alturaCm: '',
  objetivoCodigo: 'manutencao' as ObjetivoCodigo,
  objetivoOutro: '',
  dataProximaAvaliacao: '',
};

/**
 * RELATÓRIO 20260917_0001 (item 2, ME-007) — Anamnese Profissional (Web
 * B2B): diferente da Anamnese self-service do App (`AnamneseSelfServicePage`,
 * RELATÓRIO 20260917_0001), esta tela é do profissional preenchendo PARA o
 * paciente, via a RPC `profissional_salvar_anamnese` (`security definer`,
 * checa vínculo ATIVO — RLS de `anamneses` não permite INSERT direto de
 * quem não é o dono). SEM TRAVA DE TEMPO: `data_proxima_avaliacao` é um
 * campo de texto livre, sem `min`/validação de carência — diferente da
 * regra fixa de 30 dias do fluxo self-service (que nem é uma coluna, é
 * calculada no cliente Flutter).
 *
 * Rotina por dia da semana é OPCIONAL (Motor V1 cai em PAL padrão nos dias
 * sem nenhuma linha — Seção "9. Não tratar ausência de atividade como
 * atividade zero" de docs/motor_metabolico.txt) — cada linha vira uma
 * `anamneses_atividades_dias`, mesma tabela que a Anamnese self-service já
 * usa (`20260915120000`).
 */
export function AnamneseProfissionalView({ pacienteId, onSalvo }: AnamneseProfissionalViewProps) {
  const [form, setForm] = useState(FORM_VAZIO);
  const [linhas, setLinhas] = useState<LinhaAtividade[]>([]);
  const [atividades, setAtividades] = useState<TipoAtividade[]>([]);
  const [salvando, setSalvando] = useState(false);
  const [toast, setToast] = useState<ToastMessage | null>(null);

  useEffect(() => {
    void carregarAtividades();
  }, []);

  async function carregarAtividades() {
    const { data, error } = await supabase.from('tipos_atividades_fisicas').select('*').order('nome_exibicao');
    if (!error) setAtividades(data ?? []);
    // Erro aqui não impede o resto da tela — a rotina por dia é opcional
    // (fallback PAL padrão), só o seletor de atividades ficaria vazio.
  }

  function adicionarLinha() {
    setLinhas((atual) => [...atual, linhaVazia()]);
  }

  function removerLinha(chave: string) {
    setLinhas((atual) => atual.filter((l) => l.chave !== chave));
  }

  function atualizarLinha(chave: string, campo: keyof LinhaAtividade, valor: string | number) {
    setLinhas((atual) => atual.map((l) => (l.chave === chave ? { ...l, [campo]: valor } : l)));
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const linhasValidas = linhas.filter((l) => l.atividadeId && l.minutos.trim());
    if (linhas.some((l) => (l.atividadeId && !l.minutos.trim()) || (!l.atividadeId && l.minutos.trim()))) {
      setSalvando(false);
      setToast({ variant: 'error', text: 'Cada linha de rotina precisa de atividade E minutos preenchidos (ou remova a linha).' });
      return;
    }

    const { data, error } = await supabase.rpc('profissional_salvar_anamnese', {
      p_paciente_id: pacienteId,
      p_payload: {
        objetivo_codigo: form.objetivoCodigo,
        objetivo_outro: form.objetivoCodigo === 'outro' ? form.objetivoOutro.trim() || null : null,
        peso_kg: form.pesoKg.trim() ? Number(form.pesoKg) : null,
        altura_cm: form.alturaCm.trim() ? Number(form.alturaCm) : null,
        data_proxima_avaliacao: form.dataProximaAvaliacao ? `${form.dataProximaAvaliacao}T00:00:00Z` : null,
        atividades: linhasValidas.map((l) => ({
          atividade_id: Number(l.atividadeId),
          dia_semana: l.diaSemana,
          minutos: Number(l.minutos),
        })),
      },
    });

    setSalvando(false);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar a anamnese: ${error.message}` });
      return;
    }

    setToast({ variant: 'success', text: 'Anamnese salva com sucesso.' });
    setForm(FORM_VAZIO);
    setLinhas([]);
    void data; // { sucesso: true, anamnese_id }
    onSalvo?.();
  }

  return (
    <div className="space-y-4 rounded-2xl border border-clinical-border bg-clinical-surface p-5">
      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <div>
        <h2 className="text-sm font-semibold text-slate-100">Anamnese Profissional</h2>
        <p className="text-xs text-clinical-muted">
          Sem trava de tempo — defina a próxima avaliação livremente. Sempre cria uma nova versão (histórico preservado).
        </p>
      </div>

      <form onSubmit={(event) => void handleSubmit(event)} className="space-y-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <CampoNumerico
            id="anamnese-prof-peso"
            label="Peso (kg)"
            value={form.pesoKg}
            disabled={salvando}
            onChange={(valor) => setForm((atual) => ({ ...atual, pesoKg: valor }))}
          />
          <CampoNumerico
            id="anamnese-prof-altura"
            label="Altura (cm)"
            value={form.alturaCm}
            disabled={salvando}
            onChange={(valor) => setForm((atual) => ({ ...atual, alturaCm: valor }))}
          />
          <div className="col-span-2">
            <label htmlFor="anamnese-prof-proxima-avaliacao" className="block text-xs font-medium text-slate-300">
              Data da Próxima Avaliação
            </label>
            <input
              id="anamnese-prof-proxima-avaliacao"
              type="date"
              disabled={salvando}
              value={form.dataProximaAvaliacao}
              onChange={(event) => setForm((atual) => ({ ...atual, dataProximaAvaliacao: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
            <p className="mt-1 text-[10px] text-clinical-muted">Livre — sem trava de 30 dias (essa regra é só para o preenchimento self-service).</p>
          </div>
        </div>

        <div>
          <p className="mb-1.5 text-xs font-medium text-slate-300">Objetivo</p>
          <div className="flex flex-wrap gap-2">
            {(Object.keys(ROTULO_OBJETIVO) as ObjetivoCodigo[]).map((codigo) => (
              <label
                key={codigo}
                className={`cursor-pointer rounded-lg border px-3 py-1.5 text-xs font-medium transition ${
                  form.objetivoCodigo === codigo
                    ? 'border-clinical-primary bg-clinical-primary/15 text-clinical-primary'
                    : 'border-clinical-border text-clinical-muted hover:text-slate-100'
                }`}
              >
                <input
                  type="radio"
                  name="anamnese-prof-objetivo"
                  className="sr-only"
                  checked={form.objetivoCodigo === codigo}
                  disabled={salvando}
                  onChange={() => setForm((atual) => ({ ...atual, objetivoCodigo: codigo }))}
                />
                {ROTULO_OBJETIVO[codigo]}
              </label>
            ))}
          </div>
          {form.objetivoCodigo === 'outro' && (
            <input
              type="text"
              required
              disabled={salvando}
              value={form.objetivoOutro}
              onChange={(event) => setForm((atual) => ({ ...atual, objetivoOutro: event.target.value }))}
              placeholder="Outros objetivos personalizados..."
              className="mt-2 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          )}
        </div>

        <div>
          <div className="mb-1.5 flex items-center justify-between">
            <p className="text-xs font-medium text-slate-300">Rotina de atividades por dia da semana (opcional)</p>
            <button
              type="button"
              onClick={adicionarLinha}
              disabled={salvando}
              className="rounded-lg border border-clinical-border px-2.5 py-1 text-[11px] font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary"
            >
              + Adicionar linha
            </button>
          </div>
          <p className="mb-2 text-[10px] text-clinical-muted">
            Dias sem nenhuma linha usam o PAL padrão (sedentário) no Motor Metabólico — não é tratado como "sem atividade nenhuma".
          </p>
          {linhas.length === 0 ? (
            <p className="text-xs text-clinical-muted">Nenhuma linha adicionada.</p>
          ) : (
            <div className="space-y-2">
              {linhas.map((linha) => (
                <div key={linha.chave} className="flex flex-wrap items-end gap-2">
                  <select
                    disabled={salvando}
                    value={linha.diaSemana}
                    onChange={(event) => atualizarLinha(linha.chave, 'diaSemana', Number(event.target.value))}
                    className="rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                  >
                    {DIAS_SEMANA.map((d) => (
                      <option key={d.valor} value={d.valor}>
                        {d.rotulo}
                      </option>
                    ))}
                  </select>
                  <select
                    disabled={salvando}
                    value={linha.atividadeId}
                    onChange={(event) => atualizarLinha(linha.chave, 'atividadeId', event.target.value)}
                    className="min-w-[160px] flex-1 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                  >
                    <option value="">Selecione a atividade...</option>
                    {atividades.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.nome_exibicao}
                      </option>
                    ))}
                  </select>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    placeholder="min"
                    disabled={salvando}
                    value={linha.minutos}
                    onChange={(event) => atualizarLinha(linha.chave, 'minutos', event.target.value)}
                    className="w-20 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1.5 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                  />
                  <button
                    type="button"
                    onClick={() => removerLinha(linha.chave)}
                    disabled={salvando}
                    className="rounded-lg border border-clinical-border px-2 py-1.5 text-xs text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical"
                  >
                    Remover
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="flex justify-end">
          <button
            type="submit"
            disabled={salvando}
            className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {salvando ? 'Salvando...' : 'Salvar Anamnese'}
          </button>
        </div>
      </form>
    </div>
  );
}

function CampoNumerico({
  id,
  label,
  value,
  onChange,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (valor: string) => void;
  disabled: boolean;
}) {
  return (
    <div>
      <label htmlFor={id} className="block text-xs font-medium text-slate-300">
        {label}
      </label>
      <input
        id={id}
        type="number"
        min="0"
        step="0.1"
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
      />
    </div>
  );
}
