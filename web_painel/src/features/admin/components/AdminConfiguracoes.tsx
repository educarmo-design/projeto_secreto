import { useEffect, useState, type FormEvent } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface Configuracao {
  chave: string;
  valor: string | null;
  descricao: string | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * N06 (RELATÓRIO 20260811_0005) — manutenção de `configuracoes_sistema`
 * (chave/valor, `20260811210000_n06_catalogos_e_admin_perfis_seguro.sql`).
 *
 * ACHADO DO SPIKE 20260811_0004, ainda válido: não há, em nenhum PRD/Adendo
 * acessível, uma definição do que "Configurações" deveria conter — esta
 * tela edita a INFRAESTRUTURA genérica (qualquer par chave/valor), não
 * parâmetros de negócio específicos. As 2 linhas semeadas pela migration
 * (`manutencao_programada`, `idade_minima_anos`) são só exemplo/placeholder.
 */
export function AdminConfiguracoes() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [itens, setItens] = useState<Configuracao[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [valoresEmEdicao, setValoresEmEdicao] = useState<Record<string, string>>({});
  const [chavesSalvando, setChavesSalvando] = useState<Set<string>>(new Set());
  const [novaChave, setNovaChave] = useState('');
  const [novoValor, setNovoValor] = useState('');
  const [novaDescricao, setNovaDescricao] = useState('');
  const [criando, setCriando] = useState(false);

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase
      .from('configuracoes_sistema')
      .select('chave, valor, descricao')
      .order('chave', { ascending: true });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setItens(data ?? []);
    setValoresEmEdicao(Object.fromEntries((data ?? []).map((item) => [item.chave, item.valor ?? ''])));
    setEstado('sucesso');
  }

  async function salvar(chave: string) {
    setChavesSalvando((atual) => new Set(atual).add(chave));

    const { error } = await supabase
      .from('configuracoes_sistema')
      .update({ valor: valoresEmEdicao[chave] ?? null, atualizado_em: new Date().toISOString() })
      .eq('chave', chave);

    setChavesSalvando((atual) => {
      const proximo = new Set(atual);
      proximo.delete(chave);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível salvar "${chave}": ${error.message}` });
      return;
    }

    setToast({ variant: 'success', text: `"${chave}" atualizada.` });
  }

  async function criar(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCriando(true);

    const { error } = await supabase.from('configuracoes_sistema').insert({
      chave: novaChave.trim(),
      valor: novoValor.trim() || null,
      descricao: novaDescricao.trim() || null,
    });

    setCriando(false);

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível criar: ${error.message}` });
      return;
    }

    setNovaChave('');
    setNovoValor('');
    setNovaDescricao('');
    setToast({ variant: 'success', text: 'Configuração criada.' });
    void carregar();
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Configurações do Sistema</h1>
        <p className="text-sm text-clinical-muted">Pares chave/valor globais ({itens.length} cadastrados).</p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <form
        onSubmit={(event) => void criar(event)}
        className="mb-6 flex flex-wrap items-end gap-3 rounded-2xl border border-clinical-border bg-clinical-surface p-4"
      >
        <div className="min-w-[160px]">
          <label htmlFor="nova-config-chave" className="block text-xs font-medium text-slate-300">
            Chave
          </label>
          <input
            id="nova-config-chave"
            type="text"
            required
            value={novaChave}
            onChange={(event) => setNovaChave(event.target.value)}
            placeholder="Ex.: limite_upload_mb"
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <div className="min-w-[140px]">
          <label htmlFor="nova-config-valor" className="block text-xs font-medium text-slate-300">
            Valor
          </label>
          <input
            id="nova-config-valor"
            type="text"
            value={novoValor}
            onChange={(event) => setNovoValor(event.target.value)}
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <div className="min-w-[200px] flex-1">
          <label htmlFor="nova-config-descricao" className="block text-xs font-medium text-slate-300">
            Descrição (opcional)
          </label>
          <input
            id="nova-config-descricao"
            type="text"
            value={novaDescricao}
            onChange={(event) => setNovaDescricao(event.target.value)}
            className="mt-1 w-full rounded-lg border border-clinical-border bg-clinical-bg px-3 py-2 text-sm text-slate-100 outline-none focus:border-clinical-primary"
          />
        </div>
        <button
          type="submit"
          disabled={criando}
          className="rounded-lg bg-clinical-primary px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {criando ? 'Criando...' : 'Criar'}
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
                <th className="px-4 py-3">Chave</th>
                <th className="px-4 py-3">Valor</th>
                <th className="px-4 py-3">Descrição</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {itens.map((item) => {
                const salvando = chavesSalvando.has(item.chave);
                const alterado = (valoresEmEdicao[item.chave] ?? '') !== (item.valor ?? '');
                return (
                  <tr key={item.chave} className="border-t border-clinical-border">
                    <td className="px-4 py-3 font-mono text-xs text-slate-300">{item.chave}</td>
                    <td className="px-4 py-3">
                      <input
                        type="text"
                        value={valoresEmEdicao[item.chave] ?? ''}
                        onChange={(event) =>
                          setValoresEmEdicao((atual) => ({ ...atual, [item.chave]: event.target.value }))
                        }
                        className="w-full rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-sm text-slate-100 outline-none focus:border-clinical-primary"
                      />
                    </td>
                    <td className="px-4 py-3 text-slate-300">{item.descricao ?? '—'}</td>
                    <td className="px-4 py-3 text-right">
                      <button
                        type="button"
                        disabled={salvando || !alterado}
                        onClick={() => void salvar(item.chave)}
                        className="rounded-lg bg-clinical-primary px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                      >
                        {salvando ? 'Salvando...' : 'Salvar'}
                      </button>
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
