import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface TipoAtividade {
  id: string;
  nomeCodigo: string;
  nomeExibicao: string;
  metEstimado: number | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * N06 (RELATÓRIO 20260811_0005) — manutenção do dicionário de modalidades
 * (`tipos_atividades_fisicas`, criado em `20260811160000` para o
 * RELATÓRIO 20260811_0002/Treinos). Escrita liberada a admin só nesta
 * tarefa (`20260811220000_admin_escrita_tipos_atividades_fisicas.sql`) —
 * antes só existia SELECT, o dicionário nascia semeado por migration.
 *
 * `nome_codigo` espelha `HealthWorkoutActivityType.name` do pacote `health`
 * no app Flutter — mudar/apagar um código aqui sem coordenar com o app pode
 * quebrar a FK de `atividades_fisicas_treinos.tipo_atividade_codigo` para
 * treinos já sincronizados (o `on delete`/update não está em CASCADE nessa
 * FK; um DELETE de um código em uso falha com erro de integridade
 * referencial — comportamento correto, mas a mensagem de erro do Postgres
 * não é amigável, então valeria uma tela futura tratar isso melhor).
 *
 * Edição (RELATÓRIO 20260811_0006): só o nome de exibição é editável
 * inline — `nome_codigo` fica travado na edição de propósito, porque é ele
 * que a FK de `atividades_fisicas_treinos` referencia; renomear o código de
 * um treino já sincronizado quebraria o vínculo silenciosamente. Quem quer
 * mudar o código precisa remover e recriar.
 *
 * `met_estimado` (RELATÓRIO 20260811_0007, `20260811240000`) — MET
 * (Metabolic Equivalent of Task) da modalidade, opcional (fica `null` até
 * o Admin cadastrar; não há fonte automática). Input do Motor N07 (futuro),
 * não usado por nenhum cálculo nesta tarefa.
 */
export function AdminAtividadesFisicas() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [itens, setItens] = useState<TipoAtividade[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [novoCodigo, setNovoCodigo] = useState('');
  const [novoNome, setNovoNome] = useState('');
  const [novoMet, setNovoMet] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());
  const [idEmEdicao, setIdEmEdicao] = useState<string | null>(null);
  const [nomeEmEdicao, setNomeEmEdicao] = useState('');
  const [metEmEdicao, setMetEmEdicao] = useState('');

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase
      .from('tipos_atividades_fisicas')
      .select('id, nome_codigo, nome_exibicao, met_estimado')
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
        metEstimado: linha.met_estimado,
      })),
    );
    setEstado('sucesso');
  }

  async function adicionar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSalvando(true);

    const { error } = await supabase.from('tipos_atividades_fisicas').insert({
      // UPPER_SNAKE_CASE — mesma convenção do enum HealthWorkoutActivityType
      // (ex.: "RUNNING") que este código espelha.
      nome_codigo: novoCodigo.trim().toUpperCase().replace(/\s+/g, '_'),
      nome_exibicao: novoNome.trim(),
      met_estimado: novoMet.trim() ? Number(novoMet) : null,
    });

    setSalvando(false);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível criar: ${error.message}` });
      return;
    }

    setNovoCodigo('');
    setNovoNome('');
    setNovoMet('');
    setToast({ variant: 'success', text: 'Modalidade criada.' });
    void carregar();
  }

  function iniciarEdicao(item: TipoAtividade) {
    setIdEmEdicao(item.id);
    setNomeEmEdicao(item.nomeExibicao);
    setMetEmEdicao(item.metEstimado === null ? '' : String(item.metEstimado));
  }

  async function salvarEdicao(item: TipoAtividade) {
    const nomeNovo = nomeEmEdicao.trim();
    const metNovo = metEmEdicao.trim() ? Number(metEmEdicao) : null;
    if (!nomeNovo) {
      setToast({ variant: 'error', text: 'Nome de exibição não pode ficar vazio.' });
      return;
    }
    if (nomeNovo === item.nomeExibicao && metNovo === item.metEstimado) {
      setIdEmEdicao(null);
      return;
    }

    setIdsEmAcao((atual) => new Set(atual).add(item.id));
    const { error } = await supabase
      .from('tipos_atividades_fisicas')
      .update({ nome_exibicao: nomeNovo, met_estimado: metNovo })
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
        linha.id === item.id ? { ...linha, nomeExibicao: nomeNovo, metEstimado: metNovo } : linha,
      ),
    );
    setIdEmEdicao(null);
    setToast({ variant: 'success', text: `"${nomeNovo}" salvo.` });
  }

  async function remover(item: TipoAtividade) {
    setIdsEmAcao((atual) => new Set(atual).add(item.id));
    const { error } = await supabase.from('tipos_atividades_fisicas').delete().eq('id', item.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(item.id);
      return proximo;
    });

    if (error) {
      setToast({
        variant: 'error',
        text: `Não foi possível remover "${item.nomeExibicao}" (provavelmente há treinos usando este código): ${error.message}`,
      });
      return;
    }

    setItens((atual) => atual.filter((linha) => linha.id !== item.id));
    setToast({ variant: 'success', text: `"${item.nomeExibicao}" removida.` });
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Atividades Físicas</h1>
        <p className="text-sm text-clinical-muted">
          Dicionário de modalidades de treino ({itens.length} cadastradas).
        </p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <form
        onSubmit={(event) => void adicionar(event)}
        className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-clinical-border bg-clinical-surface p-4"
      >
        <div className="flex-1 min-w-[160px]">
          <label htmlFor="nova-modalidade-codigo" className="block text-xs font-medium text-slate-300">
            Código
          </label>
          <input
            id="nova-modalidade-codigo"
            type="text"
            required
            value={novoCodigo}
            onChange={(event) => setNovoCodigo(event.target.value)}
            placeholder="Ex.: PADDLE"
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <div className="flex-1 min-w-[200px]">
          <label htmlFor="nova-modalidade-nome" className="block text-xs font-medium text-slate-300">
            Nome de exibição
          </label>
          <input
            id="nova-modalidade-nome"
            type="text"
            required
            value={novoNome}
            onChange={(event) => setNovoNome(event.target.value)}
            placeholder="Ex.: Beach Tennis"
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <div className="w-28">
          <label htmlFor="nova-modalidade-met" className="block text-xs font-medium text-slate-300">
            MET estimado
          </label>
          <input
            id="nova-modalidade-met"
            type="number"
            min="0"
            step="0.1"
            value={novoMet}
            onChange={(event) => setNovoMet(event.target.value)}
            placeholder="Ex.: 8.0"
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
                <th className="px-4 py-3">MET estimado</th>
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
                          value={nomeEmEdicao}
                          onChange={(event) => setNomeEmEdicao(event.target.value)}
                          className="w-full rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary"
                        />
                      ) : (
                        item.nomeExibicao
                      )}
                    </td>
                    <td className="px-4 py-3 text-slate-300">
                      {editando ? (
                        <input
                          type="number"
                          min="0"
                          step="0.1"
                          value={metEmEdicao}
                          onChange={(event) => setMetEmEdicao(event.target.value)}
                          className="w-20 rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary"
                        />
                      ) : (
                        (item.metEstimado ?? '—')
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
