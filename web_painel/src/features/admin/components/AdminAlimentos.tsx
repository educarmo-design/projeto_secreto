import { useEffect, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

const CATEGORIAS_CONSUMO = ['liquido_frio', 'liquido_quente', 'unidade', 'fatia', 'peso_livre'] as const;
type CategoriaConsumo = (typeof CATEGORIAS_CONSUMO)[number];

const ROTULO_CATEGORIA: Record<CategoriaConsumo, string> = {
  liquido_frio: 'Líquido frio',
  liquido_quente: 'Líquido quente',
  unidade: 'Unidade',
  fatia: 'Fatia',
  peso_livre: 'Peso livre',
};

interface Alimento {
  id: string;
  nomeTaco: string;
  fonte: string;
  aliases: string[];
  caloriasKcal100g: number;
  proteinasG100g: number;
  carboidratosG100g: number;
  gordurasG100g: number;
  categoriaConsumo: CategoriaConsumo | null;
  unidadeMedidaPadrao: 'g' | 'ml' | null;
  medidaPadraoNome: string | null;
  medidaPadraoQtd: number | null;
  revisaoNecessaria: boolean;
  observacaoRevisao: string | null;
}

interface Porcao {
  id: number;
  medida: string;
  gramas: number;
  revisaoNecessaria: boolean;
  observacaoRevisao: string | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

const LIMITE_RESULTADOS = 50;

function alimentoDeLinha(linha: Record<string, unknown>): Alimento {
  return {
    id: linha.id as string,
    nomeTaco: linha.nome_taco as string,
    fonte: linha.fonte as string,
    aliases: (linha.aliases as string[] | null) ?? [],
    caloriasKcal100g: linha.calorias_kcal_100g as number,
    proteinasG100g: linha.proteinas_g_100g as number,
    carboidratosG100g: linha.carboidratos_g_100g as number,
    gordurasG100g: linha.gorduras_g_100g as number,
    categoriaConsumo: (linha.categoria_consumo as CategoriaConsumo | null) ?? null,
    unidadeMedidaPadrao: (linha.unidade_medida_padrao as 'g' | 'ml' | null) ?? null,
    medidaPadraoNome: (linha.medida_padrao_nome as string | null) ?? null,
    medidaPadraoQtd: (linha.medida_padrao_qtd as number | null) ?? null,
    revisaoNecessaria: Boolean(linha.revisao_necessaria),
    observacaoRevisao: (linha.observacao_revisao as string | null) ?? null,
  };
}

function porcaoDeLinha(linha: Record<string, unknown>): Porcao {
  return {
    id: linha.id as number,
    medida: linha.medida as string,
    gramas: linha.gramas as number,
    revisaoNecessaria: Boolean(linha.revisao_necessaria),
    observacaoRevisao: (linha.observacao_revisao as string | null) ?? null,
  };
}

// `as const` (não `string` widened) é necessário — o parser de tipos do
// supabase-js lê o LITERAL da string de `.select(...)` para inferir a
// forma da linha devolvida; uma `const` de tipo `string` genérico faz cair
// em `GenericStringError` (erro só de tipo, não de runtime).
const SELECT_ALIMENTO =
  'id, nome_taco, fonte, aliases, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g, categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd, revisao_necessaria, observacao_revisao' as const;

const SELECT_PORCAO = 'id, medida, gramas, revisao_necessaria, observacao_revisao' as const;

/**
 * RELATÓRIO 20260823_0004 — reformulação completa (pedido do fundador,
 * corrigindo o achado 20260823_0003).
 *
 * Antes: um modal único, sem filtro de revisão, sem os 4 campos de
 * categorização/unidade padrão, sem os campos de revisão (que nem
 * existiam no banco). Agora: layout de lista + detalhe (mesma tela,
 * "completo funcionalmente, cru visualmente") — alimento selecionado
 * mostra os dados TACO no topo (`AlimentoDetalhe`) e as medidas caseiras
 * dele embaixo (`MedidasCaseirasPanel`), CADA UM com seu próprio CRUD e
 * seu próprio filtro de "precisa de revisão" — exatamente como pedido:
 * "dar manutenção nas telas de alimentos e medidas caseiras de forma
 * separadas".
 *
 * RELATÓRIO 20260825_0002 — vira também a "tela de revisão do item":
 * `AdminRevisaoCatalogo` (a fila) ganhou um botão "Revisar item →" em
 * cada linha, que deep-linka pra cá via `?id=<alimentoId>` (e
 * `&medida=<medidaId>` quando o item da fila é uma medida caseira, não o
 * alimento em si) — em vez de duplicar UI de detalhe/observação, a fila
 * só aponta pra ESTA tela, que já mostra o alimento (com observação, se
 * `revisao_necessaria`) E as medidas caseiras dele logo abaixo (pedido do
 * fundador: "isso serve para medida caseira com alimento" — a medida
 * nunca é revisada isolada do alimento dono).
 */
export function AdminAlimentos() {
  const [searchParams] = useSearchParams();
  const idAlvo = searchParams.get('id');
  const medidaAlvo = searchParams.get('medida');

  const [estado, setEstado] = useState<EstadoTela>('sucesso');
  const [busca, setBusca] = useState('');
  const [somenteRevisao, setSomenteRevisao] = useState(false);
  const [alimentos, setAlimentos] = useState<Alimento[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [totalAproximado, setTotalAproximado] = useState<number | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());

  // null = nada selecionado. 'novo' = formulário em branco (criar). Um
  // Alimento = editando ele (e o painel de medidas caseiras aparece).
  const [selecionado, setSelecionado] = useState<Alimento | 'novo' | null>(null);

  useEffect(() => {
    void buscar('', false);
    // Deep link vindo da fila de revisão: seleciona direto, sem depender
    // do item estar entre os 50 primeiros da busca alfabética padrão.
    if (idAlvo) void selecionarPorId(idAlvo);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function selecionarPorId(id: string) {
    const { data, error } = await supabase.from('alimentos_referencia').select(SELECT_ALIMENTO).eq('id', id).single();
    if (error || !data) {
      setToast({ variant: 'error', text: `Não foi possível abrir o alimento: ${error?.message ?? 'não encontrado'}` });
      return;
    }
    setSelecionado(alimentoDeLinha(data as Record<string, unknown>));
  }

  async function buscar(termo: string, filtroRevisao: boolean) {
    setEstado('carregando');

    let query = supabase
      .from('alimentos_referencia')
      .select(SELECT_ALIMENTO, { count: 'exact' })
      .order('nome_taco', { ascending: true })
      .limit(LIMITE_RESULTADOS);

    if (termo.trim()) {
      query = query.ilike('nome_taco', `%${termo.trim()}%`);
    }
    if (filtroRevisao) {
      query = query.eq('revisao_necessaria', true);
    }

    const { data, error, count } = await query;

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setAlimentos((data ?? []).map((linha) => alimentoDeLinha(linha as Record<string, unknown>)));
    setTotalAproximado(count);
    setEstado('sucesso');
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void buscar(busca, somenteRevisao);
  }

  async function remover(alimento: Alimento) {
    if (!window.confirm(`Remover "${alimento.nomeTaco}" do catálogo? As medidas caseiras dele também somem.`)) {
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
    if (selecionado !== 'novo' && selecionado?.id === alimento.id) setSelecionado(null);
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
          onClick={() => setSelecionado('novo')}
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
        >
          + Novo Alimento
        </button>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <div className="flex flex-col gap-6 lg:flex-row">
        {/* ── Lista (esquerda) ─────────────────────────────────────────── */}
        <div className="lg:w-2/5">
          <form onSubmit={handleSubmit} className="mb-3 flex flex-col gap-2">
            <div className="flex gap-3">
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
            </div>
            <label className="flex items-center gap-2 text-xs text-clinical-muted">
              <input
                type="checkbox"
                checked={somenteRevisao}
                onChange={(event) => {
                  setSomenteRevisao(event.target.checked);
                  void buscar(busca, event.target.checked);
                }}
              />
              Mostrar só alimentos que precisam de revisão
            </label>
          </form>

          {estado === 'carregando' && <p className="text-clinical-muted">Buscando...</p>}
          {estado === 'erro' && (
            <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical">
              Erro ao buscar: {mensagemErro}
            </div>
          )}
          {estado === 'sucesso' && (
            <div className="max-h-[70vh] overflow-y-auto rounded-2xl border border-clinical-border bg-clinical-surface">
              {alimentos.length === 0 ? (
                <p className="px-4 py-6 text-center text-sm text-clinical-muted">Nenhum alimento encontrado.</p>
              ) : (
                <ul>
                  {alimentos.map((alimento) => {
                    const ativo = selecionado !== 'novo' && selecionado?.id === alimento.id;
                    return (
                      <li key={alimento.id} className="border-t border-clinical-border first:border-t-0">
                        <button
                          type="button"
                          onClick={() => setSelecionado(alimento)}
                          className={`flex w-full items-center justify-between gap-2 px-4 py-2.5 text-left text-sm transition ${
                            ativo ? 'bg-clinical-primary/10 text-clinical-primary' : 'text-slate-200 hover:bg-clinical-bg'
                          }`}
                        >
                          <span className="truncate">{alimento.nomeTaco}</span>
                          {alimento.revisaoNecessaria && (
                            <span className="shrink-0 rounded-full bg-amber-500/20 px-2 py-0.5 text-[10px] font-medium uppercase text-amber-400">
                              Revisão
                            </span>
                          )}
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
              {alimentos.length === LIMITE_RESULTADOS && (
                <p className="border-t border-clinical-border px-4 py-3 text-xs text-clinical-muted">
                  Mostrando os primeiros {LIMITE_RESULTADOS} resultados — refine a busca para ver mais.
                </p>
              )}
            </div>
          )}
        </div>

        {/* ── Detalhe (direita): alimento no topo, medidas embaixo ────────── */}
        <div className="lg:flex-1">
          {selecionado === null && (
            <div className="flex h-full min-h-[200px] items-center justify-center rounded-2xl border border-dashed border-clinical-border p-8 text-center text-sm text-clinical-muted">
              Selecione um alimento na lista, ou toque em "+ Novo Alimento".
            </div>
          )}
          {selecionado === 'novo' && (
            <AlimentoDetalhe
              alimento={null}
              onCancelar={() => setSelecionado(null)}
              onSalvo={(criado) => {
                void buscar(busca, somenteRevisao);
                setSelecionado(criado);
              }}
              onToast={setToast}
            />
          )}
          {selecionado !== null && selecionado !== 'novo' && (
            <div className="space-y-6">
              <AlimentoDetalhe
                alimento={selecionado}
                onCancelar={() => setSelecionado(null)}
                onSalvo={(salvo) => {
                  void buscar(busca, somenteRevisao);
                  setSelecionado(salvo);
                }}
                onRemover={() => void remover(selecionado)}
                removendo={idsEmAcao.has(selecionado.id)}
                onToast={setToast}
              />
              <MedidasCaseirasPanel
                alimentoId={selecionado.id}
                onToast={setToast}
                medidaInicialId={selecionado.id === idAlvo && medidaAlvo ? Number(medidaAlvo) : null}
              />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** Campos do formulário do alimento — strings mesmo para os números (mesmo motivo de sempre: `<input type="number">` controlado precisa de string vazia como estado intermediário válido). */
interface FormularioAlimento {
  nomeTaco: string;
  fonte: 'taco' | 'usda';
  aliases: string;
  caloriasKcal100g: string;
  proteinasG100g: string;
  carboidratosG100g: string;
  gordurasG100g: string;
  categoriaConsumo: '' | CategoriaConsumo;
  unidadeMedidaPadrao: '' | 'g' | 'ml';
  medidaPadraoNome: string;
  medidaPadraoQtd: string;
  revisaoNecessaria: boolean;
  observacaoRevisao: string;
}

function formularioDeAlimento(alimento: Alimento | null): FormularioAlimento {
  if (!alimento) {
    return {
      nomeTaco: '',
      fonte: 'taco',
      aliases: '',
      caloriasKcal100g: '',
      proteinasG100g: '',
      carboidratosG100g: '',
      gordurasG100g: '',
      categoriaConsumo: '',
      unidadeMedidaPadrao: '',
      medidaPadraoNome: '',
      medidaPadraoQtd: '',
      revisaoNecessaria: false,
      observacaoRevisao: '',
    };
  }
  return {
    nomeTaco: alimento.nomeTaco,
    fonte: alimento.fonte === 'usda' ? 'usda' : 'taco',
    aliases: alimento.aliases.join(', '),
    caloriasKcal100g: String(alimento.caloriasKcal100g),
    proteinasG100g: String(alimento.proteinasG100g),
    carboidratosG100g: String(alimento.carboidratosG100g),
    gordurasG100g: String(alimento.gordurasG100g),
    categoriaConsumo: alimento.categoriaConsumo ?? '',
    unidadeMedidaPadrao: alimento.unidadeMedidaPadrao ?? '',
    medidaPadraoNome: alimento.medidaPadraoNome ?? '',
    medidaPadraoQtd: alimento.medidaPadraoQtd !== null ? String(alimento.medidaPadraoQtd) : '',
    revisaoNecessaria: alimento.revisaoNecessaria,
    observacaoRevisao: alimento.observacaoRevisao ?? '',
  };
}

/**
 * "Topo" da tela de detalhe — dados TACO do alimento (macros, categoria,
 * unidade padrão) + revisão. Separado de [MedidasCaseirasPanel] de
 * propósito (pedido do fundador: manutenção separada dos dois).
 */
function AlimentoDetalhe({
  alimento,
  onCancelar,
  onSalvo,
  onRemover,
  removendo,
  onToast,
}: {
  alimento: Alimento | null;
  onCancelar: () => void;
  onSalvo: (alimento: Alimento) => void;
  onRemover?: () => void;
  removendo?: boolean;
  onToast: (toast: ToastMessage) => void;
}) {
  const ehEdicao = alimento !== null;
  const [form, setForm] = useState<FormularioAlimento>(() => formularioDeAlimento(alimento));
  const [salvando, setSalvando] = useState(false);

  useEffect(() => {
    setForm(formularioDeAlimento(alimento));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [alimento?.id]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const payload = {
      nome_taco: form.nomeTaco.trim(),
      fonte: form.fonte,
      aliases: form.aliases
        .split(',')
        .map((alias) => alias.trim().toLowerCase())
        .filter((alias) => alias.length > 0),
      calorias_kcal_100g: Number(form.caloriasKcal100g),
      proteinas_g_100g: Number(form.proteinasG100g),
      carboidratos_g_100g: Number(form.carboidratosG100g),
      gorduras_g_100g: Number(form.gordurasG100g),
      categoria_consumo: form.categoriaConsumo || null,
      unidade_medida_padrao: form.unidadeMedidaPadrao || null,
      medida_padrao_nome: form.medidaPadraoNome.trim() || null,
      medida_padrao_qtd: form.medidaPadraoQtd ? Number(form.medidaPadraoQtd) : null,
      revisao_necessaria: form.revisaoNecessaria,
      observacao_revisao: form.revisaoNecessaria ? form.observacaoRevisao.trim() || null : null,
    };

    const { data, error } = alimento
      ? await supabase.from('alimentos_referencia').update(payload).eq('id', alimento.id).select(SELECT_ALIMENTO).single()
      : await supabase.from('alimentos_referencia').insert(payload).select(SELECT_ALIMENTO).single();

    setSalvando(false);

    if (error || !data) {
      onToast({ variant: 'error', text: `Não foi possível salvar: ${error?.message ?? 'sem retorno'}` });
      return;
    }

    onToast({ variant: 'success', text: alimento ? `"${payload.nome_taco}" atualizado.` : `"${payload.nome_taco}" criado.` });
    onSalvo(alimentoDeLinha(data as Record<string, unknown>));
  }

  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-6">
      <header className="mb-4 flex items-start justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-wide text-clinical-muted">Dados TACO/USDA</p>
          <h2 className="text-base font-semibold text-slate-100">{ehEdicao ? form.nomeTaco || 'Editar Alimento' : 'Novo Alimento'}</h2>
        </div>
        <div className="flex gap-2">
          {ehEdicao && onRemover && (
            <button
              type="button"
              disabled={removendo}
              onClick={onRemover}
              className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
            >
              Remover
            </button>
          )}
          <button
            type="button"
            onClick={onCancelar}
            className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:text-slate-100"
          >
            Fechar
          </button>
        </div>
      </header>

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
            Usados pelo casamento léxico do Passo 2 do F10. Não recalcula o embedding semântico — o alimento entra no cálculo na hora, mas só aparece na busca por sinônimo depois do próximo job de re-embed.
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3">
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
          <div>
            <label htmlFor="alimento-unidade" className="block text-sm font-medium text-slate-300">
              Unidade padrão
            </label>
            <select
              id="alimento-unidade"
              disabled={salvando}
              value={form.unidadeMedidaPadrao}
              onChange={(event) => setForm((atual) => ({ ...atual, unidadeMedidaPadrao: event.target.value as '' | 'g' | 'ml' }))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            >
              <option value="">— não definida —</option>
              <option value="g">g (sólidos/porções)</option>
              <option value="ml">ml (líquidos)</option>
            </select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <CampoMacro id="alimento-calorias" label="Calorias (kcal/100g)" value={form.caloriasKcal100g} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, caloriasKcal100g: v }))} />
          <CampoMacro id="alimento-proteinas" label="Proteína (g/100g)" value={form.proteinasG100g} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, proteinasG100g: v }))} />
          <CampoMacro id="alimento-carboidratos" label="Carboidrato (g/100g)" value={form.carboidratosG100g} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, carboidratosG100g: v }))} />
          <CampoMacro id="alimento-gorduras" label="Gordura (g/100g)" value={form.gordurasG100g} disabled={salvando} onChange={(v) => setForm((a) => ({ ...a, gordurasG100g: v }))} />
        </div>

        <div>
          <label htmlFor="alimento-categoria" className="block text-sm font-medium text-slate-300">
            Categoria de consumo
          </label>
          <select
            id="alimento-categoria"
            disabled={salvando}
            value={form.categoriaConsumo}
            onChange={(event) => setForm((atual) => ({ ...atual, categoriaConsumo: event.target.value as '' | CategoriaConsumo }))}
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
          >
            <option value="">— não definida (cai no fallback genérico de peso livre) —</option>
            {CATEGORIAS_CONSUMO.map((c) => (
              <option key={c} value={c}>
                {ROTULO_CATEGORIA[c]}
              </option>
            ))}
          </select>
          <p className="mt-1 text-xs text-clinical-muted">
            Controla qual UI a tela de confirmar refeição mostra pro usuário (botões de tamanho pra líquidos, aviso de unidade/fatia).
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label htmlFor="alimento-medida-nome" className="block text-sm font-medium text-slate-300">
              Rótulo da medida padrão
            </label>
            <input
              id="alimento-medida-nome"
              type="text"
              disabled={salvando}
              value={form.medidaPadraoNome}
              onChange={(event) => setForm((atual) => ({ ...atual, medidaPadraoNome: event.target.value }))}
              placeholder="Ex.: Unidade, Fatia, Copo médio"
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          </div>
          <div>
            <label htmlFor="alimento-medida-qtd" className="block text-sm font-medium text-slate-300">
              Quantidade (g ou ml)
            </label>
            <input
              id="alimento-medida-qtd"
              type="number"
              min="0"
              step="0.01"
              disabled={salvando}
              value={form.medidaPadraoQtd}
              onChange={(event) => setForm((atual) => ({ ...atual, medidaPadraoQtd: event.target.value }))}
              className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          </div>
        </div>

        <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-3">
          <label className="flex items-center gap-2 text-sm font-medium text-amber-300">
            <input
              type="checkbox"
              disabled={salvando}
              checked={form.revisaoNecessaria}
              onChange={(event) => setForm((atual) => ({ ...atual, revisaoNecessaria: event.target.checked }))}
            />
            Precisa de revisão humana
          </label>
          {form.revisaoNecessaria && (
            <textarea
              disabled={salvando}
              value={form.observacaoRevisao}
              onChange={(event) => setForm((atual) => ({ ...atual, observacaoRevisao: event.target.value }))}
              placeholder="Por que este alimento precisa de revisão? (ex.: categoria incerta, nome ambíguo)"
              rows={2}
              className="mt-2 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
            />
          )}
        </div>

        <div className="flex justify-end gap-3 pt-2">
          <button
            type="submit"
            disabled={salvando}
            className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {salvando ? 'Salvando...' : ehEdicao ? 'Salvar' : 'Criar alimento'}
          </button>
        </div>
      </form>
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

/**
 * "Embaixo" da tela de detalhe — medidas caseiras do alimento selecionado.
 * CRUD completo e filtro de revisão PRÓPRIOS, separados de
 * [AlimentoDetalhe] (pedido do fundador).
 */
function MedidasCaseirasPanel({
  alimentoId,
  onToast,
  medidaInicialId,
}: {
  alimentoId: string;
  onToast: (toast: ToastMessage) => void;
  /** Deep link da fila de revisão (RELATÓRIO 20260825_0002) — abre esta
   * medida já em edição assim que a lista carrega, pra observação aparecer
   * sem precisar procurar/clicar "Editar" de novo. */
  medidaInicialId?: number | null;
}) {
  const [porcoes, setPorcoes] = useState<Porcao[]>([]);
  const [carregando, setCarregando] = useState(true);
  const [somenteRevisao, setSomenteRevisao] = useState(false);
  const [idEditando, setIdEditando] = useState<number | null>(null);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<number>>(new Set());

  const [novaMedida, setNovaMedida] = useState('');
  const [novosGramas, setNovosGramas] = useState('');
  const [adicionando, setAdicionando] = useState(false);

  useEffect(() => {
    void carregar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [alimentoId]);

  async function carregar() {
    setCarregando(true);
    const { data, error } = await supabase
      .from('alimentos_medidas_caseiras')
      .select(SELECT_PORCAO)
      .eq('alimento_id', alimentoId)
      .order('medida');

    if (error) {
      onToast({ variant: 'error', text: `Não foi possível carregar as medidas caseiras: ${error.message}` });
      setCarregando(false);
      return;
    }
    const carregadas = (data ?? []).map((linha) => porcaoDeLinha(linha as Record<string, unknown>));
    setPorcoes(carregadas);
    if (medidaInicialId && carregadas.some((p) => p.id === medidaInicialId)) {
      setIdEditando(medidaInicialId);
    }
    setCarregando(false);
  }

  async function adicionar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAdicionando(true);

    const { data, error } = await supabase
      .from('alimentos_medidas_caseiras')
      .insert({ alimento_id: alimentoId, medida: novaMedida.trim(), gramas: Number(novosGramas) })
      .select(SELECT_PORCAO)
      .single();

    setAdicionando(false);

    if (error || !data) {
      onToast({ variant: 'error', text: `Não foi possível adicionar a medida: ${error?.message ?? 'sem retorno'}` });
      return;
    }

    setPorcoes((atual) => [...atual, porcaoDeLinha(data as Record<string, unknown>)].sort((a, b) => a.medida.localeCompare(b.medida)));
    setNovaMedida('');
    setNovosGramas('');
  }

  async function salvarEdicao(porcao: Porcao, edicao: { medida: string; gramas: string; revisaoNecessaria: boolean; observacaoRevisao: string }) {
    setIdsEmAcao((atual) => new Set(atual).add(porcao.id));

    const { data, error } = await supabase
      .from('alimentos_medidas_caseiras')
      .update({
        medida: edicao.medida.trim(),
        gramas: Number(edicao.gramas),
        revisao_necessaria: edicao.revisaoNecessaria,
        observacao_revisao: edicao.revisaoNecessaria ? edicao.observacaoRevisao.trim() || null : null,
      })
      .eq('id', porcao.id)
      .select(SELECT_PORCAO)
      .single();

    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(porcao.id);
      return proximo;
    });

    if (error || !data) {
      onToast({ variant: 'error', text: `Não foi possível salvar a medida "${porcao.medida}": ${error?.message ?? 'sem retorno'}` });
      return;
    }

    const atualizada = porcaoDeLinha(data as Record<string, unknown>);
    setPorcoes((atual) => atual.map((item) => (item.id === atualizada.id ? atualizada : item)));
    setIdEditando(null);
  }

  async function remover(porcao: Porcao) {
    setIdsEmAcao((atual) => new Set(atual).add(porcao.id));
    const { error } = await supabase.from('alimentos_medidas_caseiras').delete().eq('id', porcao.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(porcao.id);
      return proximo;
    });

    if (error) {
      onToast({ variant: 'error', text: `Não foi possível remover a medida "${porcao.medida}": ${error.message}` });
      return;
    }
    setPorcoes((atual) => atual.filter((item) => item.id !== porcao.id));
  }

  const porcoesFiltradas = somenteRevisao ? porcoes.filter((p) => p.revisaoNecessaria) : porcoes;

  return (
    <div className="rounded-2xl border border-clinical-border bg-clinical-surface p-6">
      <header className="mb-4 flex items-center justify-between gap-3">
        <div>
          <p className="text-xs uppercase tracking-wide text-clinical-muted">Medidas caseiras</p>
          <h2 className="text-base font-semibold text-slate-100">{porcoes.length} cadastrada(s)</h2>
        </div>
        <label className="flex items-center gap-2 text-xs text-clinical-muted">
          <input type="checkbox" checked={somenteRevisao} onChange={(event) => setSomenteRevisao(event.target.checked)} />
          Só as que precisam de revisão
        </label>
      </header>

      {carregando ? (
        <p className="text-sm text-clinical-muted">Carregando...</p>
      ) : (
        <>
          <ul className="space-y-2">
            {porcoesFiltradas.length === 0 ? (
              <li className="text-sm text-clinical-muted">
                {somenteRevisao ? 'Nenhuma medida marcada para revisão.' : 'Nenhuma medida cadastrada ainda.'}
              </li>
            ) : (
              porcoesFiltradas.map((porcao) =>
                idEditando === porcao.id ? (
                  <MedidaEditForm
                    key={porcao.id}
                    porcao={porcao}
                    salvando={idsEmAcao.has(porcao.id)}
                    onCancelar={() => setIdEditando(null)}
                    onSalvar={(edicao) => void salvarEdicao(porcao, edicao)}
                  />
                ) : (
                  <li key={porcao.id} className="flex items-center justify-between rounded-lg border border-clinical-border px-3 py-2 text-sm">
                    <span className="flex items-center gap-2 text-slate-200">
                      {porcao.medida} <span className="text-clinical-muted">— {porcao.gramas}</span>
                      {porcao.revisaoNecessaria && (
                        <span className="rounded-full bg-amber-500/20 px-2 py-0.5 text-[10px] font-medium uppercase text-amber-400">Revisão</span>
                      )}
                    </span>
                    <span className="flex gap-3">
                      <button type="button" onClick={() => setIdEditando(porcao.id)} className="text-xs text-clinical-muted transition hover:text-clinical-primary">
                        Editar
                      </button>
                      <button
                        type="button"
                        disabled={idsEmAcao.has(porcao.id)}
                        onClick={() => void remover(porcao)}
                        className="text-xs text-clinical-muted transition hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
                      >
                        Remover
                      </button>
                    </span>
                  </li>
                ),
              )
            )}
          </ul>

          <form onSubmit={(event) => void adicionar(event)} className="mt-4 flex items-end gap-2 border-t border-clinical-border pt-4">
            <div className="flex-1">
              <label htmlFor="nova-medida" className="block text-xs font-medium text-slate-300">
                Medida
              </label>
              <input
                id="nova-medida"
                type="text"
                required
                disabled={adicionando}
                value={novaMedida}
                onChange={(event) => setNovaMedida(event.target.value)}
                placeholder="Ex.: colher de sopa"
                className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-1.5 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
            </div>
            <div className="w-28">
              <label htmlFor="nova-gramas" className="block text-xs font-medium text-slate-300">
                g/ml
              </label>
              <input
                id="nova-gramas"
                type="number"
                min="0.01"
                step="0.01"
                required
                disabled={adicionando}
                value={novosGramas}
                onChange={(event) => setNovosGramas(event.target.value)}
                className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-1.5 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
              />
            </div>
            <button
              type="submit"
              disabled={adicionando}
              className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary disabled:cursor-not-allowed disabled:opacity-60"
            >
              Adicionar
            </button>
          </form>
        </>
      )}
    </div>
  );
}

/** Formulário inline de edição de UMA medida caseira — troca a `<li>` de leitura por este quando `idEditando` bate. */
function MedidaEditForm({
  porcao,
  salvando,
  onCancelar,
  onSalvar,
}: {
  porcao: Porcao;
  salvando: boolean;
  onCancelar: () => void;
  onSalvar: (edicao: { medida: string; gramas: string; revisaoNecessaria: boolean; observacaoRevisao: string }) => void;
}) {
  const [medida, setMedida] = useState(porcao.medida);
  const [gramas, setGramas] = useState(String(porcao.gramas));
  const [revisaoNecessaria, setRevisaoNecessaria] = useState(porcao.revisaoNecessaria);
  const [observacaoRevisao, setObservacaoRevisao] = useState(porcao.observacaoRevisao ?? '');

  return (
    <li className="rounded-lg border border-clinical-primary/40 bg-clinical-bg p-3">
      <div className="flex gap-2">
        <input
          type="text"
          disabled={salvando}
          value={medida}
          onChange={(event) => setMedida(event.target.value)}
          className="flex-1 rounded-lg border border-clinical-border bg-clinical-surface px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
        />
        <input
          type="number"
          min="0.01"
          step="0.01"
          disabled={salvando}
          value={gramas}
          onChange={(event) => setGramas(event.target.value)}
          className="w-24 rounded-lg border border-clinical-border bg-clinical-surface px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
        />
      </div>
      <label className="mt-2 flex items-center gap-2 text-xs text-amber-300">
        <input type="checkbox" disabled={salvando} checked={revisaoNecessaria} onChange={(event) => setRevisaoNecessaria(event.target.checked)} />
        Precisa de revisão humana
      </label>
      {revisaoNecessaria && (
        <textarea
          disabled={salvando}
          value={observacaoRevisao}
          onChange={(event) => setObservacaoRevisao(event.target.value)}
          placeholder="Por que esta medida precisa de revisão?"
          rows={2}
          className="mt-2 w-full rounded-lg border border-clinical-border bg-clinical-surface px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
        />
      )}
      <div className="mt-2 flex justify-end gap-2">
        <button type="button" onClick={onCancelar} disabled={salvando} className="rounded-lg border border-clinical-border px-3 py-1 text-xs text-clinical-muted transition hover:text-slate-100">
          Cancelar
        </button>
        <button
          type="button"
          disabled={salvando}
          onClick={() => onSalvar({ medida, gramas, revisaoNecessaria, observacaoRevisao })}
          className="rounded-lg bg-clinical-primary px-3 py-1 text-xs font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {salvando ? 'Salvando...' : 'Salvar'}
        </button>
      </div>
    </li>
  );
}
