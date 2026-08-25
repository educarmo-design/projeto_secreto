import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface AlimentoRevisao {
  id: string;
  nomeTaco: string;
  observacaoRevisao: string | null;
}

interface MedidaRevisao {
  id: number;
  alimentoId: string;
  alimentoNome: string;
  medida: string;
  gramas: number;
  observacaoRevisao: string | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * RELATÓRIO 20260824_0001 — o fundador populou o catálogo (RELATÓRIO
 * 20260823_0004) mas não achou onde ver a fila de revisão: o filtro que eu
 * tinha colocado em `AdminAlimentos.tsx` fica escondido dentro da tela
 * (tem que já estar lá pra notar o checkbox). Esta tela nova é o ponto de
 * entrada explícito — "fila de revisão" dedicada, com observação visível
 * direto na lista (sem precisar abrir cada item) e marcar/desmarcar
 * revisão ali mesmo. Duas filas SEPARADAS (pedido do fundador): alimentos
 * e medidas caseiras, cada uma com seu próprio card em [AdminOverview].
 */
export function AdminRevisaoAlimentos() {
  return <FilaRevisao tipo="alimentos" />;
}

export function AdminRevisaoMedidasCaseiras() {
  return <FilaRevisao tipo="medidas" />;
}

function FilaRevisao({ tipo }: { tipo: 'alimentos' | 'medidas' }) {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [alimentos, setAlimentos] = useState<AlimentoRevisao[]>([]);
  const [medidas, setMedidas] = useState<MedidaRevisao[]>([]);
  const [toast, setToast] = useState<ToastMessage | null>(null);

  useEffect(() => {
    void carregar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tipo]);

  async function carregar() {
    setEstado('carregando');

    if (tipo === 'alimentos') {
      const { data, error } = await supabase
        .from('alimentos_referencia')
        .select('id, nome_taco, observacao_revisao')
        .eq('revisao_necessaria', true)
        .order('nome_taco');

      if (error) {
        setEstado('erro');
        return;
      }
      setAlimentos(
        (data ?? []).map((linha) => ({
          id: linha.id,
          nomeTaco: linha.nome_taco,
          observacaoRevisao: linha.observacao_revisao,
        })),
      );
      setEstado('sucesso');
      return;
    }

    const { data, error } = await supabase
      .from('alimentos_medidas_caseiras')
      .select('id, alimento_id, medida, gramas, observacao_revisao')
      .eq('revisao_necessaria', true)
      .order('medida');

    if (error) {
      setEstado('erro');
      return;
    }

    const linhas = data ?? [];
    // Join do lado do cliente em vez de embed do PostgREST
    // (`alimentos_referencia(nome_taco)`): a fila de revisão normalmente
    // tem poucas dezenas de linhas, então 2 queries simples (medidas +
    // nomes únicos) é mais barato de manter do que declarar a
    // Relationship no `database.ts` só pra esta tela.
    const idsUnicos = [...new Set(linhas.map((l) => l.alimento_id))];
    const { data: alimentosData, error: erroAlimentos } = idsUnicos.length
      ? await supabase.from('alimentos_referencia').select('id, nome_taco').in('id', idsUnicos)
      : { data: [], error: null };

    if (erroAlimentos) {
      setEstado('erro');
      return;
    }
    const nomePorId = new Map((alimentosData ?? []).map((a) => [a.id, a.nome_taco]));

    setMedidas(
      linhas.map((linha) => ({
        id: linha.id,
        alimentoId: linha.alimento_id,
        alimentoNome: nomePorId.get(linha.alimento_id) ?? '(alimento removido)',
        medida: linha.medida,
        gramas: linha.gramas,
        observacaoRevisao: linha.observacao_revisao,
      })),
    );
    setEstado('sucesso');
  }

  async function salvarAlimento(item: AlimentoRevisao, revisaoNecessaria: boolean, observacao: string) {
    const { error } = await supabase
      .from('alimentos_referencia')
      .update({
        revisao_necessaria: revisaoNecessaria,
        observacao_revisao: revisaoNecessaria ? observacao.trim() || null : null,
      })
      .eq('id', item.id);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar "${item.nomeTaco}": ${error.message}` });
      throw error;
    }
    // Desmarcado (ou reclassificado) sai da fila — a lista É o filtro.
    setAlimentos((atual) => (revisaoNecessaria ? atual : atual.filter((a) => a.id !== item.id)));
    setToast({ variant: 'success', text: `"${item.nomeTaco}" atualizado.` });
  }

  async function salvarMedida(item: MedidaRevisao, revisaoNecessaria: boolean, observacao: string) {
    const { error } = await supabase
      .from('alimentos_medidas_caseiras')
      .update({
        revisao_necessaria: revisaoNecessaria,
        observacao_revisao: revisaoNecessaria ? observacao.trim() || null : null,
      })
      .eq('id', item.id);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar "${item.medida}": ${error.message}` });
      throw error;
    }
    setMedidas((atual) => (revisaoNecessaria ? atual : atual.filter((m) => m.id !== item.id)));
    setToast({ variant: 'success', text: `"${item.medida}" atualizado.` });
  }

  const titulo = tipo === 'alimentos' ? 'Alimentos em revisão' : 'Medidas caseiras em revisão';
  const quantidade = tipo === 'alimentos' ? alimentos.length : medidas.length;

  return (
    <div>
      <header className="mb-6 flex items-start justify-between gap-3">
        <div>
          <h1 className="text-lg font-semibold text-slate-100">{titulo}</h1>
          <p className="text-sm text-clinical-muted">
            {estado === 'sucesso' ? `${quantidade} item(ns) aguardando revisão humana.` : 'Fila de curadoria pendente.'}
          </p>
        </div>
        <Link to="/admin/alimentos" className="text-xs text-clinical-primary hover:underline">
          Ir para o catálogo completo →
        </Link>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      {estado === 'carregando' && <p className="text-clinical-muted">Carregando...</p>}
      {estado === 'erro' && (
        <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical">
          Não foi possível carregar a fila de revisão.
        </div>
      )}
      {estado === 'sucesso' && quantidade === 0 && (
        <div className="rounded-2xl border border-dashed border-clinical-border p-8 text-center text-sm text-clinical-muted">
          Nenhum item aguardando revisão — fila vazia. 🎉
        </div>
      )}
      {estado === 'sucesso' && quantidade > 0 && (
        <ul className="space-y-3">
          {tipo === 'alimentos'
            ? alimentos.map((item) => (
                <FilaItem
                  key={item.id}
                  titulo={item.nomeTaco}
                  observacaoInicial={item.observacaoRevisao ?? ''}
                  linkRevisao={`/admin/alimentos?id=${item.id}`}
                  onSalvar={(revisao, obs) => salvarAlimento(item, revisao, obs)}
                />
              ))
            : medidas.map((item) => (
                <FilaItem
                  key={item.id}
                  titulo={`${item.medida} — ${item.gramas}`}
                  subtitulo={`Alimento: ${item.alimentoNome}`}
                  observacaoInicial={item.observacaoRevisao ?? ''}
                  // Medida caseira nunca é revisada isolada do alimento
                  // dono (pedido do fundador) — o deep link leva pro
                  // mesmo alimento, com esta medida já aberta em edição.
                  linkRevisao={`/admin/alimentos?id=${item.alimentoId}&medida=${item.id}`}
                  onSalvar={(revisao, obs) => salvarMedida(item, revisao, obs)}
                />
              ))}
        </ul>
      )}
    </div>
  );
}

/**
 * Uma linha da fila — sempre começa marcada (só itens
 * `revisao_necessaria=true` entram na fila), com observação visível e
 * editável direto, e o toggle que a spec do fundador pediu: "nas duas
 * telas é possível marcar ou desmarcar o item de revisão".
 *
 * RELATÓRIO 20260825_0002 — `linkRevisao` é o botão "Revisar item →"
 * pedido pelo fundador: some pra "tela de revisão do item" completa
 * (`AdminAlimentos`, deep-linkada por `?id=`/`&medida=`) em vez de só o
 * toggle rápido daqui. As duas formas de resolver convivem: quem só quer
 * marcar/desmarcar não precisa sair da fila; quem precisa editar
 * macros/categoria/gramas vai pro item.
 */
function FilaItem({
  titulo,
  subtitulo,
  observacaoInicial,
  linkRevisao,
  onSalvar,
}: {
  titulo: string;
  subtitulo?: string;
  observacaoInicial: string;
  linkRevisao: string;
  onSalvar: (revisaoNecessaria: boolean, observacao: string) => Promise<void>;
}) {
  const [revisaoNecessaria, setRevisaoNecessaria] = useState(true);
  const [observacao, setObservacao] = useState(observacaoInicial);
  const [salvando, setSalvando] = useState(false);

  async function handleSalvar() {
    setSalvando(true);
    try {
      await onSalvar(revisaoNecessaria, observacao);
      // Sucesso desmarcando: o item some da lista do pai (unmount) — nada
      // a fazer aqui. Sucesso mantendo marcado: volta a ficar editável.
    } catch {
      // Erro já vira Toast no pai; aqui só destrava o formulário de novo.
    } finally {
      setSalvando(false);
    }
  }

  return (
    <li className="rounded-2xl border border-amber-500/30 bg-amber-500/5 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-slate-100">{titulo}</p>
          {subtitulo && <p className="text-xs text-clinical-muted">{subtitulo}</p>}
        </div>
        <Link to={linkRevisao} className="shrink-0 text-xs text-clinical-primary hover:underline">
          Revisar item →
        </Link>
      </div>

      <textarea
        disabled={salvando}
        value={observacao}
        onChange={(event) => setObservacao(event.target.value)}
        placeholder="Observação da revisão"
        rows={2}
        className="mt-2 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
      />

      <div className="mt-2 flex items-center justify-between">
        <label className="flex items-center gap-2 text-xs text-amber-300">
          <input
            type="checkbox"
            disabled={salvando}
            checked={revisaoNecessaria}
            onChange={(event) => setRevisaoNecessaria(event.target.checked)}
          />
          Precisa de revisão humana
        </label>
        <button
          type="button"
          disabled={salvando}
          onClick={() => void handleSalvar()}
          className="rounded-lg bg-clinical-primary px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {salvando ? 'Salvando...' : revisaoNecessaria ? 'Salvar' : 'Marcar como revisado'}
        </button>
      </div>
    </li>
  );
}
