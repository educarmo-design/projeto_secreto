import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface Alergia {
  id: string;
  nomeCodigo: string;
  nomeExibicao: string;
  descricao: string | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * N06 (RELATÓRIO 20260811_0005) — manutenção do catálogo de alergias
 * (`alergias`, criado em `20260811210000_n06_catalogos_e_admin_perfis_seguro.sql`).
 * Ao contrário de `tipos_atividades_fisicas` (que já nasceu semeado com as
 * modalidades comuns Android/iOS), o catálogo de alergias nasceu VAZIO —
 * não há uma lista oficial de referência mapeada; cresce só pelo que o
 * Admin cadastrar aqui.
 *
 * Edição (RELATÓRIO 20260811_0006): nome de exibição e descrição são
 * editáveis inline — `nome_codigo` fica travado (é o valor que
 * `usuario_alergias` referencia; mesma razão de `tipos_atividades_fisicas`).
 */
export function AdminAlergias() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [itens, setItens] = useState<Alergia[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [novoCodigo, setNovoCodigo] = useState('');
  const [novoNome, setNovoNome] = useState('');
  const [novaDescricao, setNovaDescricao] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());
  const [idEmEdicao, setIdEmEdicao] = useState<string | null>(null);
  const [edicaoNome, setEdicaoNome] = useState('');
  const [edicaoDescricao, setEdicaoDescricao] = useState('');

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase
      .from('alergias')
      .select('id, nome_codigo, nome_exibicao, descricao')
      .order('nome_exibicao', { ascending: true });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setItens(
      (data ?? []).map((linha) => ({
        id: linha.id,
        nomeCodigo: linha.nome_codigo,
        nomeExibicao: linha.nome_exibicao,
        descricao: linha.descricao,
      })),
    );
    setEstado('sucesso');
  }

  async function adicionar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const { error } = await supabase.from('alergias').insert({
      nome_codigo: novoCodigo.trim().toUpperCase().replace(/\s+/g, '_'),
      nome_exibicao: novoNome.trim(),
      descricao: novaDescricao.trim() || null,
    });

    setSalvando(false);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível criar: ${error.message}` });
      return;
    }

    setNovoCodigo('');
    setNovoNome('');
    setNovaDescricao('');
    setToast({ variant: 'success', text: 'Alergia criada.' });
    void carregar();
  }

  function iniciarEdicao(item: Alergia) {
    setIdEmEdicao(item.id);
    setEdicaoNome(item.nomeExibicao);
    setEdicaoDescricao(item.descricao ?? '');
  }

  async function salvarEdicao(item: Alergia) {
    const nomeNovo = edicaoNome.trim();
    const descricaoNova = edicaoDescricao.trim() || null;
    if (!nomeNovo) {
      setToast({ variant: 'error', text: 'Nome de exibição não pode ficar vazio.' });
      return;
    }
    if (nomeNovo === item.nomeExibicao && descricaoNova === item.descricao) {
      setIdEmEdicao(null);
      return;
    }

    setIdsEmAcao((atual) => new Set(atual).add(item.id));
    const { error } = await supabase
      .from('alergias')
      .update({ nome_exibicao: nomeNovo, descricao: descricaoNova })
      .eq('id', item.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(item.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar "${item.nomeExibicao}": ${error.message}` });
      return;
    }

    setItens((atual) =>
      atual.map((linha) =>
        linha.id === item.id ? { ...linha, nomeExibicao: nomeNovo, descricao: descricaoNova } : linha,
      ),
    );
    setIdEmEdicao(null);
    setToast({ variant: 'success', text: `"${nomeNovo}" salva.` });
  }

  async function remover(item: Alergia) {
    setIdsEmAcao((atual) => new Set(atual).add(item.id));
    const { error } = await supabase.from('alergias').delete().eq('id', item.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(item.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível remover "${item.nomeExibicao}": ${error.message}` });
      return;
    }

    setItens((atual) => atual.filter((linha) => linha.id !== item.id));
    setToast({ variant: 'success', text: `"${item.nomeExibicao}" removida.` });
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Alergias</h1>
        <p className="text-sm text-clinical-muted">
          Catálogo de alergias conhecidas ({itens.length} cadastradas).
        </p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <form
        onSubmit={(event) => void adicionar(event)}
        className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-clinical-border bg-clinical-surface p-4"
      >
        <div className="min-w-[140px]">
          <label htmlFor="nova-alergia-codigo" className="block text-xs font-medium text-slate-300">
            Código
          </label>
          <input
            id="nova-alergia-codigo"
            type="text"
            required
            value={novoCodigo}
            onChange={(event) => setNovoCodigo(event.target.value)}
            placeholder="Ex.: LACTOSE"
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <div className="min-w-[160px] flex-1">
          <label htmlFor="nova-alergia-nome" className="block text-xs font-medium text-slate-300">
            Nome de exibição
          </label>
          <input
            id="nova-alergia-nome"
            type="text"
            required
            value={novoNome}
            onChange={(event) => setNovoNome(event.target.value)}
            placeholder="Ex.: Intolerância à Lactose"
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <div className="min-w-[200px] flex-1">
          <label htmlFor="nova-alergia-descricao" className="block text-xs font-medium text-slate-300">
            Descrição (opcional)
          </label>
          <input
            id="nova-alergia-descricao"
            type="text"
            value={novaDescricao}
            onChange={(event) => setNovaDescricao(event.target.value)}
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
                <th className="px-4 py-3">Código</th>
                <th className="px-4 py-3">Nome de exibição</th>
                <th className="px-4 py-3">Descrição</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {itens.map((item) => {
                const editando = idEmEdicao === item.id;
                const emAcao = idsEmAcao.has(item.id);
                return (
                  <tr key={item.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 font-mono text-xs text-slate-300">{item.nomeCodigo}</td>
                    <td className="px-4 py-3 text-slate-200">
                      {editando ? (
                        <input
                          type="text"
                          autoFocus
                          value={edicaoNome}
                          onChange={(event) => setEdicaoNome(event.target.value)}
                          className="w-full rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary"
                        />
                      ) : (
                        item.nomeExibicao
                      )}
                    </td>
                    <td className="px-4 py-3 text-slate-300">
                      {editando ? (
                        <input
                          type="text"
                          value={edicaoDescricao}
                          onChange={(event) => setEdicaoDescricao(event.target.value)}
                          className="w-full rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary"
                        />
                      ) : (
                        item.descricao ?? '—'
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
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
