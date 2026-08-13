import { Fragment, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface Papel {
  id: string;
  nomeCodigo: string;
  nomeExibicao: string;
}

interface Permissao {
  id: string;
  modulo: string;
  acaoCodigo: string;
  descricao: string | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/** Função pura, fora do componente de propósito — evita que o React Hooks
 * ESLint plugin trate `carregar`/`alternar` como dependentes de um valor
 * recriado a cada render (a chave da matriz não depende de nenhum estado). */
function chave(papelId: string, permissaoId: string) {
  return `${papelId}:${permissaoId}`;
}

/**
 * D3 — Matriz de Permissões DINÂMICA (RELATÓRIO 20260811_0005, ajuste do
 * fundador: "NADA de arquivo .md estático... uma tela de gestão no Painel
 * Web para habilitar/desabilitar permissões por papel em tempo real").
 *
 * Linhas = permissões do sistema (agrupadas por módulo); colunas = papéis.
 * Cada célula é um checkbox: marcado = `papeis_permissoes` tem essa dupla
 * (papel_id, permissao_id). Toggle chama a RPC
 * `admin_atualizar_permissao_papel` (ÚNICA porta de escrita da matriz —
 * `papeis_permissoes` não tem policy de INSERT/DELETE direta para
 * `authenticated`, ver `20260811200000_d3_rbac_dinamico.sql`) — nunca um
 * `.insert()`/`.delete()` direto na tabela.
 *
 * Otimista: marca/desmarca a UI na hora do clique, reverte só se a RPC
 * devolver erro (ex.: alguém sem `is_admin` chegando aqui de alguma forma —
 * a RPC valida `eh_admin()` no servidor, então mesmo que o roteamento do
 * painel falhasse, a escrita real seria recusada).
 */
export function AdminMatrizPermissoes() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [papeis, setPapeis] = useState<Papel[]>([]);
  const [permissoes, setPermissoes] = useState<Permissao[]>([]);
  // Chave "papelId:permissaoId" -> habilitado. Um Set seria mais enxuto,
  // mas o Record deixa a leitura de cada célula (matriz[papel][permissao])
  // trivial de expressar sem reconstruir nada a cada render.
  const [matriz, setMatriz] = useState<Record<string, boolean>>({});
  const [celulasEmAcao, setCelulasEmAcao] = useState<Set<string>>(new Set());
  const [toast, setToast] = useState<ToastMessage | null>(null);

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');

    const [papeisResp, permissoesResp, matrizResp] = await Promise.all([
      supabase.from('papeis').select('id, nome_codigo, nome_exibicao').order('nome_exibicao'),
      supabase.from('permissoes').select('id, modulo, acao_codigo, descricao').order('modulo').order('acao_codigo'),
      supabase.from('papeis_permissoes').select('papel_id, permissao_id'),
    ]);

    const erro = papeisResp.error ?? permissoesResp.error ?? matrizResp.error;
    if (erro) {
      setEstado('erro');
      setMensagemErro(erro.message);
      return;
    }

    setPapeis(
      (papeisResp.data ?? []).map((linha) => ({
        id: linha.id,
        nomeCodigo: linha.nome_codigo,
        nomeExibicao: linha.nome_exibicao,
      })),
    );
    setPermissoes(
      (permissoesResp.data ?? []).map((linha) => ({
        id: linha.id,
        modulo: linha.modulo,
        acaoCodigo: linha.acao_codigo,
        descricao: linha.descricao,
      })),
    );
    setMatriz(
      Object.fromEntries((matrizResp.data ?? []).map((linha) => [chave(linha.papel_id, linha.permissao_id), true])),
    );
    setEstado('sucesso');
  }

  async function alternar(papel: Papel, permissao: Permissao) {
    const key = chave(papel.id, permissao.id);
    const habilitadoAntes = matriz[key] ?? false;
    const habilitarAgora = !habilitadoAntes;

    // Otimista: atualiza a UI antes da resposta do servidor.
    setMatriz((atual) => ({ ...atual, [key]: habilitarAgora }));
    setCelulasEmAcao((atual) => new Set(atual).add(key));

    const { error } = await supabase.rpc('admin_atualizar_permissao_papel', {
      p_papel_id: papel.id,
      p_permissao_id: permissao.id,
      p_habilitado: habilitarAgora,
    });

    setCelulasEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(key);
      return proximo;
    });

    if (error) {
      // Reverte — a escrita real não aconteceu.
      setMatriz((atual) => ({ ...atual, [key]: habilitadoAntes }));
      setToast({
        variant: 'error',
        text: `Não foi possível ${habilitarAgora ? 'habilitar' : 'desabilitar'} "${permissao.modulo}.${permissao.acaoCodigo}" para ${papel.nomeExibicao}: ${error.message}`,
      });
      return;
    }

    setToast({
      variant: 'success',
      text: `${papel.nomeExibicao}: "${permissao.modulo}.${permissao.acaoCodigo}" ${habilitarAgora ? 'habilitada' : 'desabilitada'}.`,
    });
  }

  const permissoesPorModulo = useMemo(() => {
    const grupos = new Map<string, Permissao[]>();
    for (const permissao of permissoes) {
      const lista = grupos.get(permissao.modulo) ?? [];
      lista.push(permissao);
      grupos.set(permissao.modulo, lista);
    }
    return grupos;
  }, [permissoes]);

  if (estado === 'carregando') {
    return <p className="text-clinical-muted">Carregando Matriz de Permissões...</p>;
  }

  if (estado === 'erro') {
    return (
      <div role="alert" className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical">
        Erro ao carregar a Matriz de Permissões: {mensagemErro}
      </div>
    );
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Matriz de Permissões</h1>
        <p className="text-sm text-clinical-muted">
          Marque/desmarque para habilitar ou desabilitar uma permissão por papel — a mudança é salva na hora.
        </p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
        <table className="w-full text-left text-sm">
          <thead className="text-xs uppercase text-clinical-muted">
            <tr>
              <th className="sticky left-0 bg-clinical-surface px-4 py-3">Permissão</th>
              {papeis.map((papel) => (
                <th key={papel.id} className="px-4 py-3 text-center">
                  {papel.nomeExibicao}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {[...permissoesPorModulo.entries()].map(([modulo, permissoesDoModulo]) => (
              <Fragment key={modulo}>
                <tr className="border-t border-clinical-border bg-clinical-bg/60">
                  <td colSpan={papeis.length + 1} className="px-4 py-2 text-xs font-semibold uppercase tracking-wide text-clinical-muted">
                    {modulo}
                  </td>
                </tr>
                {permissoesDoModulo.map((permissao) => (
                  <tr key={permissao.id} className="border-t border-clinical-border">
                    <td className="sticky left-0 bg-clinical-surface px-4 py-3 text-slate-200">
                      <span className="font-mono text-xs text-clinical-muted">
                        {permissao.modulo}.{permissao.acaoCodigo}
                      </span>
                      {permissao.descricao && (
                        <p className="mt-0.5 text-xs text-clinical-muted">{permissao.descricao}</p>
                      )}
                    </td>
                    {papeis.map((papel) => {
                      const key = chave(papel.id, permissao.id);
                      const habilitado = matriz[key] ?? false;
                      const emAcao = celulasEmAcao.has(key);
                      return (
                        <td key={papel.id} className="px-4 py-3 text-center">
                          <input
                            type="checkbox"
                            checked={habilitado}
                            disabled={emAcao}
                            onChange={() => void alternar(papel, permissao)}
                            aria-label={`${permissao.modulo}.${permissao.acaoCodigo} para ${papel.nomeExibicao}`}
                            className="h-4 w-4 accent-clinical-primary disabled:cursor-not-allowed disabled:opacity-60"
                          />
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
