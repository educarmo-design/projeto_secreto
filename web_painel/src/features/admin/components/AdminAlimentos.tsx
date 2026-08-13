import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface Alimento {
  id: string;
  nomeTaco: string;
  fonte: string;
  caloriasKcal100g: number;
  proteinasG100g: number;
  carboidratosG100g: number;
  gordurasG100g: number;
}

interface Porcao {
  id: number;
  medida: string;
  gramas: number;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

const LIMITE_RESULTADOS = 50;

/** Campos do formulário do modal — strings mesmo para os números, porque
 * `<input type="number">` controlado precisa de string vazia como estado
 * intermediário válido (digitar "1", depois apagar, deve mostrar campo
 * vazio, não "0"). Convertidos para `number` só no submit. */
interface FormularioAlimento {
  nomeTaco: string;
  fonte: 'taco' | 'usda';
  aliases: string;
  caloriasKcal100g: string;
  proteinasG100g: string;
  carboidratosG100g: string;
  gordurasG100g: string;
}

const FORMULARIO_VAZIO: FormularioAlimento = {
  nomeTaco: '',
  fonte: 'taco',
  aliases: '',
  caloriasKcal100g: '',
  proteinasG100g: '',
  carboidratosG100g: '',
  gordurasG100g: '',
};

/**
 * N06 (RELATÓRIO 20260811_0006) — manutenção COMPLETA de `alimentos_referencia`.
 *
 * Até a tarefa anterior (RELATÓRIO 20260811_0005) esta tela era só busca —
 * a tabela tinha uma trava de escrita deliberada ("curadoria é migration/
 * service role"). Esta tarefa pede explicitamente que o Admin consiga
 * gerenciar o catálogo, então a trava foi revertida por instrução do
 * fundador (`20260811230000_n06_escrita_admin_alimentos_e_vinculos.sql`).
 *
 * RESSALVA que continua verdadeira e é mostrada no modal: `nome_taco`/
 * `aliases` alimentam embeddings semânticos (`cache_sinonimos_alimentos`,
 * busca por sinônimo via Edge Function `search-food`) que este CRUD NÃO
 * recalcula — o alimento entra no cálculo de calorias na hora, mas só
 * aparece na busca por sinônimo depois do job de re-embed rodar (fora do
 * escopo desta tela).
 */
export function AdminAlimentos() {
  const [estado, setEstado] = useState<EstadoTela>('sucesso');
  const [busca, setBusca] = useState('');
  const [alimentos, setAlimentos] = useState<Alimento[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [totalAproximado, setTotalAproximado] = useState<number | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());

  // null = modal fechado. `alimentoId` presente = editando (e a seção de
  // Porções fica disponível); ausente = criando um alimento novo.
  const [modal, setModal] = useState<{ alimentoId: string | null } | null>(null);

  useEffect(() => {
    void buscar('');
  }, []);

  async function buscar(termo: string) {
    setEstado('carregando');

    let query = supabase
      .from('alimentos_referencia')
      .select(
        'id, nome_taco, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g',
        { count: 'exact' },
      )
      .order('nome_taco', { ascending: true })
      .limit(LIMITE_RESULTADOS);

    if (termo.trim()) {
      query = query.ilike('nome_taco', `%${termo.trim()}%`);
    }

    const { data, error, count } = await query;

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setAlimentos(
      (data ?? []).map((linha) => ({
        id: linha.id,
        nomeTaco: linha.nome_taco,
        fonte: linha.fonte,
        caloriasKcal100g: linha.calorias_kcal_100g,
        proteinasG100g: linha.proteinas_g_100g,
        carboidratosG100g: linha.carboidratos_g_100g,
        gordurasG100g: linha.gorduras_g_100g,
      })),
    );
    setTotalAproximado(count);
    setEstado('sucesso');
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void buscar(busca);
  }

  async function remover(alimento: Alimento) {
    if (!window.confirm(`Remover "${alimento.nomeTaco}" do catálogo? As porções cadastradas dele também somem.`)) {
      return;
    }
    setIdsEmAcao((atual) => new Set(atual).add(alimento.id));
    const { error } = await supabase.from('alimentos_referencia').delete().eq('id', alimento.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(alimento.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível remover "${alimento.nomeTaco}": ${error.message}` });
      return;
    }

    setAlimentos((atual) => atual.filter((item) => item.id !== alimento.id));
    setToast({ variant: 'success', text: `"${alimento.nomeTaco}" removido.` });
  }

  return (
    <div>
      <header className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-lg font-semibold text-slate-100">Alimentos</h1>
          <p className="text-sm text-clinical-muted">
            Catálogo de referência (TACO/USDA) — {totalAproximado ?? '—'} no total, busca por nome.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setModal({ alimentoId: null })}
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
        >
          + Novo Alimento
        </button>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <form onSubmit={handleSubmit} className="mb-6 flex gap-3">
        <input
          type="search"
          value={busca}
          onChange={(event) => setBusca(event.target.value)}
          placeholder="Buscar por nome (ex.: arroz)"
          className="flex-1 rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
        />
        <button
          type="submit"
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
        >
          Buscar
        </button>
      </form>

      {estado === 'carregando' && <p className="text-clinical-muted">Buscando...</p>}
      {estado === 'erro' && (
        <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical">
          Erro ao buscar: {mensagemErro}
        </div>
      )}
      {estado === 'sucesso' && (
        <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-clinical-muted">
              <tr>
                <th className="px-4 py-3">Nome</th>
                <th className="px-4 py-3">Fonte</th>
                <th className="px-4 py-3">kcal/100g</th>
                <th className="px-4 py-3">Proteína g/100g</th>
                <th className="px-4 py-3">Carbo g/100g</th>
                <th className="px-4 py-3">Gordura g/100g</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {alimentos.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum alimento encontrado.
                  </td>
                </tr>
              ) : (
                alimentos.map((alimento) => (
                  <tr key={alimento.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 text-slate-200">{alimento.nomeTaco}</td>
                    <td className="px-4 py-3 uppercase text-slate-300">{alimento.fonte}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.caloriasKcal100g}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.proteinasG100g}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.carboidratosG100g}</td>
                    <td className="px-4 py-3 text-slate-300">{alimento.gordurasG100g}</td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => setModal({ alimentoId: alimento.id })}
                          className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary"
                        >
                          Editar
                        </button>
                        <button
                          type="button"
                          disabled={idsEmAcao.has(alimento.id)}
                          onClick={() => void remover(alimento)}
                          className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
                        >
                          Remover
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
          {alimentos.length === LIMITE_RESULTADOS && (
            <p className="border-t border-clinical-border px-4 py-3 text-xs text-clinical-muted">
              Mostrando os primeiros {LIMITE_RESULTADOS} resultados — refine a busca para ver mais.
            </p>
          )}
        </div>
      )}

      {modal && (
        <AlimentoModal
          alimentoId={modal.alimentoId}
          onClose={() => setModal(null)}
          onSalvo={(alimentoIdCriado) => {
            void buscar(busca);
            // Alimento recém-criado: reabre o modal já em modo "editar" pra
            // permitir cadastrar as porções na sequência, sem re-navegar.
            if (alimentoIdCriado) {
              setModal({ alimentoId: alimentoIdCriado });
            } else {
              setModal(null);
            }
          }}
          onToast={setToast}
        />
      )}
    </div>
  );
}

function AlimentoModal({
  alimentoId,
  onClose,
  onSalvo,
  onToast,
}: {
  alimentoId: string | null;
  onClose: () => void;
  onSalvo: (alimentoIdCriado: string | null) => void;
  onToast: (toast: ToastMessage) => void;
}) {
  const ehEdicao = alimentoId !== null;
  const [carregando, setCarregando] = useState(ehEdicao);
  const [salvando, setSalvando] = useState(false);
  const [form, setForm] = useState<FormularioAlimento>(FORMULARIO_VAZIO);
  const [porcoes, setPorcoes] = useState<Porcao[]>([]);
  const [novaMedida, setNovaMedida] = useState('');
  const [novosGramas, setNovosGramas] = useState('');
  const [adicionandoPorcao, setAdicionandoPorcao] = useState(false);
  const [idsPorcaoEmAcao, setIdsPorcaoEmAcao] = useState<Set<number>>(new Set());

  // A busca roda inline dentro do effect (não como função nomeada do
  // componente) de propósito: só é chamada aqui, e uma função nomeada
  // recriada a cada render obrigaria a escolher entre incluí-la nas deps
  // (loop infinito, já que ela nunca é `===` à instância anterior) ou
  // desabilitar o lint — nenhuma das duas é necessária quando o corpo mora
  // dentro do próprio `useEffect`.
  useEffect(() => {
    if (!alimentoId) return;

    async function carregar(id: string) {
      setCarregando(true);
      const [alimentoResp, porcoesResp] = await Promise.all([
        supabase
          .from('alimentos_referencia')
          .select('nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g')
          .eq('id', id)
          .single(),
        supabase.from('alimentos_medidas_caseiras').select('id, medida, gramas').eq('alimento_id', id).order('medida'),
      ]);

      if (alimentoResp.error || !alimentoResp.data) {
        onToast({ variant: 'error', text: `Não foi possível carregar o alimento: ${alimentoResp.error?.message ?? 'não encontrado'}` });
        onClose();
        return;
      }

      const linha = alimentoResp.data;
      setForm({
        nomeTaco: linha.nome_taco,
        fonte: linha.fonte === 'usda' ? 'usda' : 'taco',
        aliases: linha.aliases.join(', '),
        caloriasKcal100g: String(linha.calorias_kcal_100g),
        proteinasG100g: String(linha.proteinas_g_100g),
        carboidratosG100g: String(linha.carboidratos_g_100g),
        gordurasG100g: String(linha.gorduras_g_100g),
      });
      setPorcoes(porcoesResp.data ?? []);
      setCarregando(false);
    }

    void carregar(alimentoId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [alimentoId]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const payload = {
      nome_taco: form.nomeTaco.trim(),
      fonte: form.fonte,
      // Mesma normalização de "código" já usada em Atividades/Alergias não
      // se aplica aqui — aliases são texto livre em pt-BR, só separados por
      // vírgula e sem entradas vazias (ex.: vírgula sobrando no fim).
      aliases: form.aliases
        .split(',')
        .map((alias) => alias.trim().toLowerCase())
        .filter((alias) => alias.length > 0),
      calorias_kcal_100g: Number(form.caloriasKcal100g),
      proteinas_g_100g: Number(form.proteinasG100g),
      carboidratos_g_100g: Number(form.carboidratosG100g),
      gorduras_g_100g: Number(form.gordurasG100g),
    };

    const { data, error } = alimentoId
      ? await supabase.from('alimentos_referencia').update(payload).eq('id', alimentoId).select('id').single()
      : await supabase.from('alimentos_referencia').insert(payload).select('id').single();

    setSalvando(false);

    if (error || !data) {
      onToast({ variant: 'error', text: `Não foi possível salvar: ${error?.message ?? 'sem retorno'}` });
      return;
    }

    onToast({ variant: 'success', text: alimentoId ? `"${payload.nome_taco}" atualizado.` : `"${payload.nome_taco}" criado.` });
    onSalvo(alimentoId ?? data.id);
  }

  async function adicionarPorcao(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!alimentoId) return;
    setAdicionandoPorcao(true);

    const { data, error } = await supabase
      .from('alimentos_medidas_caseiras')
      .insert({ alimento_id: alimentoId, medida: novaMedida.trim(), gramas: Number(novosGramas) })
      .select('id, medida, gramas')
      .single();

    setAdicionandoPorcao(false);

    if (error || !data) {
      onToast({ variant: 'error', text: `Não foi possível adicionar a porção: ${error?.message ?? 'sem retorno'}` });
      return;
    }

    setPorcoes((atual) => [...atual, data].sort((a, b) => a.medida.localeCompare(b.medida)));
    setNovaMedida('');
    setNovosGramas('');
  }

  async function removerPorcao(porcao: Porcao) {
    setIdsPorcaoEmAcao((atual) => new Set(atual).add(porcao.id));
    const { error } = await supabase.from('alimentos_medidas_caseiras').delete().eq('id', porcao.id);
    setIdsPorcaoEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(porcao.id);
      return proximo;
    });

    if (error) {
      onToast({ variant: 'error', text: `Não foi possível remover a porção "${porcao.medida}": ${error.message}` });
      return;
    }

    setPorcoes((atual) => atual.filter((item) => item.id !== porcao.id));
  }

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center overflow-y-auto bg-clinical-bg/80 p-4">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="alimento-modal-title"
        className="w-full max-w-lg rounded-2xl border border-clinical-border bg-clinical-surface p-6"
      >
        <header className="mb-5">
          <p className="text-xs uppercase tracking-wide text-clinical-muted">Catálogo de alimentos</p>
          <h2 id="alimento-modal-title" className="text-lg font-semibold text-slate-100">
            {ehEdicao ? 'Editar Alimento' : 'Novo Alimento'}
          </h2>
        </header>

        {carregando ? (
          <p className="text-clinical-muted">Carregando...</p>
        ) : (
          <>
            <form onSubmit={(event) => void handleSubmit(event)} className="space-y-4">
              <div>
                <label htmlFor="alimento-nome" className="block text-sm font-medium text-slate-300">
                  Nome
                </label>
                <input
                  id="alimento-nome"
                  type="text"
                  required
                  disabled={salvando}
                  value={form.nomeTaco}
                  onChange={(event) => setForm((atual) => ({ ...atual, nomeTaco: event.target.value }))}
                  placeholder="Ex.: Arroz, branco, cozido"
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                />
              </div>

              <div>
                <label htmlFor="alimento-aliases" className="block text-sm font-medium text-slate-300">
                  Sinônimos (separados por vírgula)
                </label>
                <input
                  id="alimento-aliases"
                  type="text"
                  disabled={salvando}
                  value={form.aliases}
                  onChange={(event) => setForm((atual) => ({ ...atual, aliases: event.target.value }))}
                  placeholder="Ex.: arroz, arroz branco, arroz cozido"
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                />
                <p className="mt-1 text-xs text-clinical-muted">
                  Usados pelo casamento léxico do Passo 2 do F10. Não recalcula o embedding semântico — ver comentário no código.
                </p>
              </div>

              <div>
                <label htmlFor="alimento-fonte" className="block text-sm font-medium text-slate-300">
                  Fonte
                </label>
                <select
                  id="alimento-fonte"
                  disabled={salvando}
                  value={form.fonte}
                  onChange={(event) => setForm((atual) => ({ ...atual, fonte: event.target.value as 'taco' | 'usda' }))}
                  className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                >
                  <option value="taco">TACO</option>
                  <option value="usda">USDA</option>
                </select>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <CampoMacro
                  id="alimento-calorias"
                  label="Calorias (kcal/100g)"
                  value={form.caloriasKcal100g}
                  disabled={salvando}
                  onChange={(valor) => setForm((atual) => ({ ...atual, caloriasKcal100g: valor }))}
                />
                <CampoMacro
                  id="alimento-proteinas"
                  label="Proteína (g/100g)"
                  value={form.proteinasG100g}
                  disabled={salvando}
                  onChange={(valor) => setForm((atual) => ({ ...atual, proteinasG100g: valor }))}
                />
                <CampoMacro
                  id="alimento-carboidratos"
                  label="Carboidrato (g/100g)"
                  value={form.carboidratosG100g}
                  disabled={salvando}
                  onChange={(valor) => setForm((atual) => ({ ...atual, carboidratosG100g: valor }))}
                />
                <CampoMacro
                  id="alimento-gorduras"
                  label="Gordura (g/100g)"
                  value={form.gordurasG100g}
                  disabled={salvando}
                  onChange={(valor) => setForm((atual) => ({ ...atual, gordurasG100g: valor }))}
                />
              </div>

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
                  disabled={salvando}
                  className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {salvando ? 'Salvando...' : ehEdicao ? 'Salvar' : 'Criar e continuar'}
                </button>
              </div>
            </form>

            {ehEdicao && (
              <div className="mt-6 border-t border-clinical-border pt-5">
                <h3 className="text-sm font-medium text-slate-200">Porções (medidas caseiras)</h3>
                <ul className="mt-2 space-y-1">
                  {porcoes.length === 0 ? (
                    <li className="text-xs text-clinical-muted">Nenhuma porção cadastrada ainda.</li>
                  ) : (
                    porcoes.map((porcao) => (
                      <li key={porcao.id} className="flex items-center justify-between rounded-lg border border-clinical-border px-3 py-1.5 text-sm">
                        <span className="text-slate-200">
                          {porcao.medida} <span className="text-clinical-muted">— {porcao.gramas}g</span>
                        </span>
                        <button
                          type="button"
                          disabled={idsPorcaoEmAcao.has(porcao.id)}
                          onClick={() => void removerPorcao(porcao)}
                          className="text-xs text-clinical-muted transition hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
                        >
                          Remover
                        </button>
                      </li>
                    ))
                  )}
                </ul>
                <form onSubmit={(event) => void adicionarPorcao(event)} className="mt-3 flex items-end gap-2">
                  <div className="flex-1">
                    <label htmlFor="nova-porcao-medida" className="block text-xs font-medium text-slate-300">
                      Medida
                    </label>
                    <input
                      id="nova-porcao-medida"
                      type="text"
                      required
                      disabled={adicionandoPorcao}
                      value={novaMedida}
                      onChange={(event) => setNovaMedida(event.target.value)}
                      placeholder="Ex.: colher de sopa"
                      className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-1.5 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                    />
                  </div>
                  <div className="w-24">
                    <label htmlFor="nova-porcao-gramas" className="block text-xs font-medium text-slate-300">
                      Gramas
                    </label>
                    <input
                      id="nova-porcao-gramas"
                      type="number"
                      min="0.01"
                      step="0.01"
                      required
                      disabled={adicionandoPorcao}
                      value={novosGramas}
                      onChange={(event) => setNovosGramas(event.target.value)}
                      className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-1.5 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                    />
                  </div>
                  <button
                    type="submit"
                    disabled={adicionandoPorcao}
                    className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    Adicionar
                  </button>
                </form>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

function CampoMacro({
  id,
  label,
  value,
  disabled,
  onChange,
}: {
  id: string;
  label: string;
  value: string;
  disabled: boolean;
  onChange: (valor: string) => void;
}) {
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-medium text-slate-300">
        {label}
      </label>
      <input
        id={id}
        type="number"
        min="0"
        step="0.01"
        required
        disabled={disabled}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
      />
    </div>
  );
}
