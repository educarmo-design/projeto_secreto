import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import type { Database } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';

type ObjetivoAlimentar = Database['public']['Tables']['objetivos_alimentares']['Row'];

interface PrescricaoViewProps {
  pacienteId: string;
}

type Estado = 'carregando' | 'sucesso' | 'erro';

/** Mesmos códigos que `validar_e_salvar_meta` devolve em `avisos` (ver
 * migration `20260812110000`) — traduzidos para o profissional ler. */
const ROTULO_AVISO: Record<string, string> = {
  gordura_abaixo_do_minimo_0_6g_por_kg: 'Gordura abaixo do mínimo recomendado (0,6 g/kg de peso corporal)',
  calorias_abaixo_da_tmb: 'Calorias abaixo da Taxa Metabólica Basal (TMB) do paciente',
  calorias_acima_de_2_5x_tmb: 'Calorias acima de 2,5× a TMB do paciente',
  validacao_parcial_dados_insuficientes_para_tmb_ou_peso:
    'Validação clínica parcial — faltam peso/TMB do paciente para avaliar as faixas de segurança',
};

const CAMPOS_VAZIOS = {
  tipoDia: 'PADRAO',
  caloriasAlvo: '',
  proteinaG: '',
  carboG: '',
  gorduraG: '',
  vencimentoEm: dataMaisSeteDias(),
};

function dataMaisSeteDias(): string {
  const data = new Date();
  data.setDate(data.getDate() + 7);
  return data.toISOString().split('T')[0] ?? '';
}

/**
 * N10 (RELATÓRIO 20260812_0010) — Prescrição Profissional: formulário +
 * cards de metas ativas + histórico, tudo passando pela RPC
 * `validar_e_salvar_meta` (Motor de Exceções N08) com
 * `p_is_profissional: true` — nunca um `.insert()` direto (a tabela não
 * tem policy de escrita para `authenticated`, ver a migration).
 *
 * Diferente da via do atleta (N11, App Flutter): aqui uma violação clínica
 * NUNCA impede o salvamento — a RPC devolve `violacao_clinica`/`avisos`
 * junto com `sucesso: true`, e esta tela vira isso num banner amarelo. O
 * profissional decide, o Motor só avisa.
 */
export function PrescricaoView({ pacienteId }: PrescricaoViewProps) {
  const [estado, setEstado] = useState<Estado>('carregando');
  const [objetivos, setObjetivos] = useState<ObjetivoAlimentar[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [salvando, setSalvando] = useState(false);
  const [ultimoAviso, setUltimoAviso] = useState<{ violacaoClinica: boolean; avisos: string[] } | null>(null);

  const [form, setForm] = useState(CAMPOS_VAZIOS);

  useEffect(() => {
    void carregar();
    // `carregar` também é chamado de `handleSubmit` (não só aqui), então
    // fica em escopo de componente em vez de inline no efeito (diferente
    // de `AdminAlimentos.tsx`) — o disable é o caminho correto pro mesmo
    // motivo já documentado lá.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pacienteId]);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase
      .from('objetivos_alimentares')
      .select('*')
      .eq('usuario_id', pacienteId)
      .order('data_criacao', { ascending: false });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setObjetivos(data ?? []);
    setEstado('sucesso');
  }

  const ativos = objetivos.filter((o) => o.status_vigencia === 'ativo');
  const historico = objetivos.filter((o) => o.status_vigencia === 'historico').slice(0, 10);
  const ativoDoTipoSelecionado = ativos.find((o) => o.tipo_dia === form.tipoDia) ?? null;

  function copiarUltimo(objetivo: ObjetivoAlimentar) {
    setForm({
      tipoDia: objetivo.tipo_dia,
      caloriasAlvo: String(objetivo.calorias_alvo),
      proteinaG: objetivo.proteina_g !== null ? String(objetivo.proteina_g) : '',
      carboG: objetivo.carbo_g !== null ? String(objetivo.carbo_g) : '',
      gorduraG: objetivo.gordura_g !== null ? String(objetivo.gordura_g) : '',
      vencimentoEm: dataMaisSeteDias(),
    });
    setUltimoAviso(null);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);
    setUltimoAviso(null);

    const { data, error } = await supabase.rpc('validar_e_salvar_meta', {
      p_payload: {
        usuario_id: pacienteId,
        tipo_dia: form.tipoDia.trim().toUpperCase() || 'PADRAO',
        calorias_alvo: Number(form.caloriasAlvo),
        proteina_g: form.proteinaG.trim() ? Number(form.proteinaG) : null,
        carbo_g: form.carboG.trim() ? Number(form.carboG) : null,
        gordura_g: form.gorduraG.trim() ? Number(form.gorduraG) : null,
        vencimento_em: form.vencimentoEm ? `${form.vencimentoEm}T00:00:00Z` : null,
      },
      p_is_profissional: true,
    });

    setSalvando(false);

    if (error) {
      // N08_SEM_VINCULO é o único caso plausível aqui — a tela só é
      // acessível com vínculo ativo (RLS já barra a leitura antes), mas
      // Zero Trust: a RPC re-valida no servidor de qualquer forma.
      setToast({ variant: 'error', text: `Não foi possível salvar: ${error.message}` });
      return;
    }

    setUltimoAviso({ violacaoClinica: data.violacao_clinica, avisos: data.avisos });
    setToast({
      variant: data.violacao_clinica ? 'error' : 'success',
      text: data.violacao_clinica
        ? 'Meta salva — fora da faixa de segurança clínica (ver aviso abaixo).'
        : 'Meta salva com sucesso.',
    });
    setForm({ ...CAMPOS_VAZIOS, tipoDia: form.tipoDia });
    void carregar();
  }

  return (
    <div className="space-y-6">
      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <div>
        <h2 className="text-sm font-semibold text-slate-100">Prescrição — Metas Alimentares</h2>
        <p className="text-xs text-clinical-muted">
          Passa pelo Motor de Exceções (N08) — fora da faixa clínica não bloqueia, só avisa.
        </p>
      </div>

      {estado === 'carregando' && <p className="text-sm text-clinical-muted">Carregando...</p>}
      {estado === 'erro' && (
        <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-sm text-clinical-critical">
          Erro ao carregar metas: {mensagemErro}
        </div>
      )}

      {estado === 'sucesso' && (
        <>
          {/* Cards de metas ATIVAS */}
          <div>
            <p className="mb-2 text-xs font-medium uppercase tracking-wide text-clinical-muted">
              Metas ativas ({ativos.length})
            </p>
            {ativos.length === 0 ? (
              <p className="text-sm text-clinical-muted">Nenhuma meta ativa ainda.</p>
            ) : (
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {ativos.map((objetivo) => (
                  <CardMeta key={objetivo.id} objetivo={objetivo} onCopiar={() => copiarUltimo(objetivo)} />
                ))}
              </div>
            )}
          </div>

          {/* Formulário N10 */}
          <form
            onSubmit={(event) => void handleSubmit(event)}
            className="space-y-4 rounded-2xl border border-clinical-border bg-clinical-surface p-5"
          >
            <div className="flex flex-wrap items-end justify-between gap-3">
              <div className="min-w-[160px]">
                <label htmlFor="prescricao-tipo-dia" className="block text-xs font-medium text-slate-300">
                  Tipo de dia
                </label>
                <input
                  id="prescricao-tipo-dia"
                  type="text"
                  required
                  disabled={salvando}
                  value={form.tipoDia}
                  onChange={(event) => setForm((atual) => ({ ...atual, tipoDia: event.target.value }))}
                  placeholder="PADRAO, TREINO, DESCANSO..."
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                />
              </div>

              {ativoDoTipoSelecionado && (
                <button
                  type="button"
                  onClick={() => copiarUltimo(ativoDoTipoSelecionado)}
                  className="rounded-lg border border-clinical-border px-3 py-2 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary"
                >
                  Copiar Último ({ativoDoTipoSelecionado.tipo_dia})
                </button>
              )}
            </div>

            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <CampoNumerico
                id="prescricao-calorias"
                label="Calorias (kcal)"
                value={form.caloriasAlvo}
                required
                disabled={salvando}
                onChange={(valor) => setForm((atual) => ({ ...atual, caloriasAlvo: valor }))}
              />
              <CampoNumerico
                id="prescricao-proteina"
                label="Proteína (g)"
                value={form.proteinaG}
                disabled={salvando}
                onChange={(valor) => setForm((atual) => ({ ...atual, proteinaG: valor }))}
              />
              <CampoNumerico
                id="prescricao-carbo"
                label="Carboidrato (g)"
                value={form.carboG}
                disabled={salvando}
                onChange={(valor) => setForm((atual) => ({ ...atual, carboG: valor }))}
              />
              <CampoNumerico
                id="prescricao-gordura"
                label="Gordura (g)"
                value={form.gorduraG}
                disabled={salvando}
                onChange={(valor) => setForm((atual) => ({ ...atual, gorduraG: valor }))}
              />
            </div>

            <div className="max-w-[200px]">
              <label htmlFor="prescricao-vencimento" className="block text-xs font-medium text-slate-300">
                Vencimento
              </label>
              <input
                id="prescricao-vencimento"
                type="date"
                disabled={salvando}
                value={form.vencimentoEm}
                onChange={(event) => setForm((atual) => ({ ...atual, vencimentoEm: event.target.value }))}
                className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
              <p className="mt-1 text-[10px] text-clinical-muted">Padrão: +7 dias.</p>
            </div>

            {/* Banner amarelo de Atenção — NUNCA desabilita o botão de
                Salvar (a RPC já salvou; isso só sinaliza que a prescrição
                está fora da faixa clínica). */}
            {ultimoAviso && ultimoAviso.violacaoClinica && (
              <div role="alert" className="rounded-xl border border-clinical-warning/40 bg-clinical-warning/10 p-4">
                <p className="mb-1 text-sm font-medium text-clinical-warning">
                  Atenção — meta salva fora da faixa de segurança clínica
                </p>
                <ul className="list-inside list-disc text-xs text-clinical-warning">
                  {ultimoAviso.avisos.map((aviso) => (
                    <li key={aviso}>{ROTULO_AVISO[aviso] ?? aviso}</li>
                  ))}
                </ul>
              </div>
            )}

            <div className="flex justify-end">
              <button
                type="submit"
                disabled={salvando}
                className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {salvando ? 'Salvando...' : 'Salvar Prescrição'}
              </button>
            </div>
          </form>

          {/* Histórico */}
          {historico.length > 0 && (
            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-clinical-muted">
                Histórico (últimas {historico.length})
              </p>
              <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
                <table className="w-full text-left text-sm">
                  <thead className="text-xs uppercase text-clinical-muted">
                    <tr>
                      <th className="px-4 py-2">Tipo de dia</th>
                      <th className="px-4 py-2">Calorias</th>
                      <th className="px-4 py-2">P / C / G</th>
                      <th className="px-4 py-2">Criada em</th>
                      <th className="px-4 py-2">Origem</th>
                    </tr>
                  </thead>
                  <tbody>
                    {historico.map((objetivo) => (
                      <tr key={objetivo.id} className="border-t border-clinical-border">
                        <td className="px-4 py-2 font-mono text-xs text-slate-300">{objetivo.tipo_dia}</td>
                        <td className="px-4 py-2 text-slate-300">{objetivo.calorias_alvo} kcal</td>
                        <td className="px-4 py-2 text-slate-300">
                          {objetivo.proteina_g ?? '—'} / {objetivo.carbo_g ?? '—'} / {objetivo.gordura_g ?? '—'} g
                        </td>
                        <td className="px-4 py-2 text-slate-300">
                          {new Date(objetivo.data_criacao).toLocaleDateString('pt-BR')}
                        </td>
                        <td className="px-4 py-2 text-slate-300">
                          {objetivo.profissional_id ? 'Profissional' : 'Self-service'}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function CardMeta({ objetivo, onCopiar }: { objetivo: ObjetivoAlimentar; onCopiar: () => void }) {
  const vencida = objetivo.vencimento_em !== null && new Date(objetivo.vencimento_em) < new Date();
  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-4">
      <div className="mb-2 flex items-center justify-between">
        <span className="rounded-full bg-clinical-primary/15 px-2 py-0.5 text-xs font-medium text-clinical-primary">
          {objetivo.tipo_dia}
        </span>
        {vencida && (
          <span className="rounded-full bg-clinical-warning/15 px-2 py-0.5 text-xs font-medium text-clinical-warning">
            Vencida
          </span>
        )}
      </div>
      <p className="text-lg font-semibold text-slate-100">{objetivo.calorias_alvo} kcal</p>
      <p className="text-xs text-clinical-muted">
        P {objetivo.proteina_g ?? '—'}g · C {objetivo.carbo_g ?? '—'}g · G {objetivo.gordura_g ?? '—'}g
      </p>
      <p className="mt-2 text-[10px] text-clinical-muted">
        {objetivo.profissional_id ? 'Prescrita por profissional' : 'Self-service'} ·{' '}
        {new Date(objetivo.data_criacao).toLocaleDateString('pt-BR')}
        {objetivo.vencimento_em && ` · vence ${new Date(objetivo.vencimento_em).toLocaleDateString('pt-BR')}`}
      </p>
      <button
        type="button"
        onClick={onCopiar}
        className="mt-3 w-full rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary"
      >
        Copiar Último
      </button>
    </div>
  );
}

function CampoNumerico({
  id,
  label,
  value,
  onChange,
  required = false,
  disabled,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (valor: string) => void;
  required?: boolean;
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
        step="1"
        required={required}
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
      />
    </div>
  );
}
