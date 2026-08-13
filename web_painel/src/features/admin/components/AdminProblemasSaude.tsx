import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface ProblemaSaude {
  id: string;
  nome: string;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * N09 (RELATÓRIO 20260811_0007) — manutenção do catálogo de problemas de
 * saúde (comorbidades autodeclaradas na Anamnese Nutricional Versionada,
 * self-service no app Flutter — `lib/features/nutricao`). Mesmo espírito de
 * `AdminAlergias.tsx`, mas mais simples por pedido explícito do fundador:
 * `problemas_saude` só tem `id`/`nome` (sem código separado nem
 * descrição), então não há campo "código" travado na edição — o próprio
 * nome é editável direto.
 */
export function AdminProblemasSaude() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [itens, setItens] = useState<ProblemaSaude[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [novoNome, setNovoNome] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());
  const [idEmEdicao, setIdEmEdicao] = useState<string | null>(null);
  const [nomeEmEdicao, setNomeEmEdicao] = useState('');

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase.from('problemas_saude').select('id, nome').order('nome', { ascending: true });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setItens(data ?? []);
    setEstado('sucesso');
  }

  async function adicionar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const { error } = await supabase.from('problemas_saude').insert({ nome: novoNome.trim() });

    setSalvando(false);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível criar: ${error.message}` });
      return;
    }

    setNovoNome('');
    setToast({ variant: 'success', text: 'Problema de saúde criado.' });
    void carregar();
  }

  function iniciarEdicao(item: ProblemaSaude) {
    setIdEmEdicao(item.id);
    setNomeEmEdicao(item.nome);
  }

  async function salvarEdicao(item: ProblemaSaude) {
    const nomeNovo = nomeEmEdicao.trim();
    if (!nomeNovo) {
      setToast({ variant: 'error', text: 'Nome não pode ficar vazio.' });
      return;
    }
    if (nomeNovo === item.nome) {
      setIdEmEdicao(null);
      return;
    }

    setIdsEmAcao((atual) => new Set(atual).add(item.id));
    const { error } = await supabase.from('problemas_saude').update({ nome: nomeNovo }).eq('id', item.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(item.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar "${item.nome}": ${error.message}` });
      return;
    }

    setItens((atual) => atual.map((linha) => (linha.id === item.id ? { ...linha, nome: nomeNovo } : linha)));
    setIdEmEdicao(null);
    setToast({ variant: 'success', text: `"${nomeNovo}" salvo.` });
  }

  async function remover(item: ProblemaSaude) {
    if (!window.confirm(`Remover "${item.nome}" do catálogo?`)) return;

    setIdsEmAcao((atual) => new Set(atual).add(item.id));
    const { error } = await supabase.from('problemas_saude').delete().eq('id', item.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(item.id);
      return proximo;
    });

    if (error) {
      setToast({
        variant: 'error',
        text: `Não foi possível remover "${item.nome}" (provavelmente há anamneses usando este item): ${error.message}`,
      });
      return;
    }

    setItens((atual) => atual.filter((linha) => linha.id !== item.id));
    setToast({ variant: 'success', text: `"${item.nome}" removido.` });
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Problemas de Saúde</h1>
        <p className="text-sm text-clinical-muted">
          Catálogo de comorbidades usado na Anamnese Nutricional ({itens.length} cadastrados).
        </p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <form
        onSubmit={(event) => void adicionar(event)}
        className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-clinical-border bg-clinical-surface p-4"
      >
        <div className="min-w-[220px] flex-1">
          <label htmlFor="novo-problema-nome" className="block text-xs font-medium text-slate-300">
            Nome
          </label>
          <input
            id="novo-problema-nome"
            type="text"
            required
            value={novoNome}
            onChange={(event) => setNovoNome(event.target.value)}
            placeholder="Ex.: Diabetes Tipo 2"
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <button
          type="submit"
          disabled={salvando}
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {salvando ? 'Adicionando...' : 'Adicionar'}
        </button>
      </form>

      {estado === 'carregando' && <p className="text-clinical-muted">Carregando...</p>}
      {estado === 'erro' && (
        <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical">
          Erro ao carregar: {mensagemErro}
        </div>
      )}
      {estado === 'sucesso' && (
        <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-clinical-muted">
              <tr>
                <th className="px-4 py-3">Nome</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {itens.length === 0 ? (
                <tr>
                  <td colSpan={2} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum problema de saúde cadastrado ainda.
                  </td>
                </tr>
              ) : (
                itens.map((item) => {
                  const editando = idEmEdicao === item.id;
                  const emAcao = idsEmAcao.has(item.id);
                  return (
                    <tr key={item.id} className="border-t border-clinical-border">
                      <td className="px-4 py-3 text-slate-200">
                        {editando ? (
                          <input
                            type="text"
                            autoFocus
                            value={nomeEmEdicao}
                            onChange={(event) => setNomeEmEdicao(event.target.value)}
                            className="w-full rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary"
                          />
                        ) : (
                          item.nome
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex justify-end gap-2">
                          {editando ? (
                            <>
                              <button
                                type="button"
                                onClick={() => setIdEmEdicao(null)}
                                className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:text-slate-100"
                              >
                                Cancelar
                              </button>
                              <button
                                type="button"
                                disabled={emAcao}
                                onClick={() => void salvarEdicao(item)}
                                className="rounded-lg bg-clinical-primary px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                              >
                                {emAcao ? 'Salvando...' : 'Salvar'}
                              </button>
                            </>
                          ) : (
                            <>
                              <button
                                type="button"
                                disabled={emAcao}
                                onClick={() => iniciarEdicao(item)}
                                className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-primary hover:text-clinical-primary disabled:cursor-not-allowed disabled:opacity-60"
                              >
                                Editar
                              </button>
                              <button
                                type="button"
                                disabled={emAcao}
                                onClick={() => void remover(item)}
                                className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
                              >
                                Remover
                              </button>
                            </>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
