import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import { Toast, type ToastMessage } from '@/components/Toast';

interface SolicitacaoPendente {
  id: string;
  nome: string | null;
  email: string | null;
  tipoProfissional: string | null;
  criadoEm: string;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';
type Acao = 'aprovar' | 'rejeitar';

/**
 * Sala de Espera — backoffice do Admin (20260714100000_add_approval_workflow.sql).
 *
 * Zero Trust: o botão "Aprovar" só existe nesta tela por conveniência de UI.
 * A escrita real (`update perfis_usuarios set status_aprovacao = 'aprovado',
 * eh_profissional = true`) só é aceita pelo Postgres se quem a envia tiver
 * `is_admin = true` na própria linha — reforçado pela policy
 * `perfis_usuarios_update_admin`. Um usuário sem `is_admin` que chegasse
 * nesta rota (App.tsx barra isso, mas Zero Trust nunca confia só no
 * frontend) receberia "permission denied" do banco ao tentar aprovar
 * qualquer coisa.
 */
export function AdminDashboard() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [pendentes, setPendentes] = useState<SolicitacaoPendente[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());
  const [toast, setToast] = useState<ToastMessage | null>(null);

  useEffect(() => {
    void carregarPendentes();
  }, []);

  async function carregarPendentes() {
    setEstado('carregando');
    setMensagemErro(null);

    const { data, error } = await supabase
      .from('perfis_usuarios')
      .select('id, nome, email, tipo_profissional, criado_em')
      .eq('status_aprovacao', 'pendente')
      .order('criado_em', { ascending: true });

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setPendentes(
      (data ?? []).map((linha) => ({
        id: linha.id,
        nome: linha.nome,
        email: linha.email,
        tipoProfissional: linha.tipo_profissional,
        criadoEm: linha.criado_em,
      })),
    );
    setEstado('sucesso');
  }

  async function decidir(solicitacao: SolicitacaoPendente, acao: Acao) {
    setIdsEmAcao((atual) => new Set(atual).add(solicitacao.id));

    const { error } = await supabase
      .from('perfis_usuarios')
      .update(
        acao === 'aprovar'
          ? { status_aprovacao: 'aprovado', eh_profissional: true }
          : { status_aprovacao: 'rejeitado' },
      )
      .eq('id', solicitacao.id);

    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(solicitacao.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível concluir a ação: ${error.message}` });
      return;
    }

    setPendentes((atual) => atual.filter((item) => item.id !== solicitacao.id));
    setToast({
      variant: 'success',
      text:
        acao === 'aprovar'
          ? `${solicitacao.nome ?? solicitacao.email ?? 'Solicitação'} aprovado(a) — já pode aceder ao painel.`
          : `${solicitacao.nome ?? solicitacao.email ?? 'Solicitação'} rejeitado(a).`,
    });
  }

  if (estado === 'carregando') {
    return <p className="text-clinical-muted">Carregando solicitações...</p>;
  }

  if (estado === 'erro') {
    return (
      <div
        role="alert"
        className="rounded-xl border border-clinical-critical/40 bg-clinical-critical/10 p-4 text-clinical-critical"
      >
        Erro ao carregar solicitações: {mensagemErro}
      </div>
    );
  }

  return (
    <div>
      <header className="mb-4">
        <h1 className="text-lg font-semibold text-slate-100">Sala de Espera</h1>
        <p className="text-sm text-clinical-muted">
          {pendentes.length} solicitação(ões) de acesso aguardando análise.
        </p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

      {pendentes.length === 0 ? (
        <p className="text-sm text-clinical-muted">Nenhuma solicitação pendente no momento.</p>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-clinical-border bg-clinical-surface">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-clinical-muted">
              <tr>
                <th className="px-4 py-3">Nome</th>
                <th className="px-4 py-3">E-mail</th>
                <th className="px-4 py-3">Área de atuação</th>
                <th className="px-4 py-3">Solicitado em</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {pendentes.map((solicitacao) => {
                const emAcao = idsEmAcao.has(solicitacao.id);
                return (
                  <tr key={solicitacao.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 text-slate-200">{solicitacao.nome ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{solicitacao.email ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">
                      {solicitacao.tipoProfissional ?? '—'}
                    </td>
                    <td className="px-4 py-3 text-slate-300">
                      {new Date(solicitacao.criadoEm).toLocaleDateString('pt-BR')}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex justify-end gap-2">
                        <button
                          type="button"
                          disabled={emAcao}
                          onClick={() => void decidir(solicitacao, 'rejeitar')}
                          className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
                        >
                          Rejeitar
                        </button>
                        <button
                          type="button"
                          disabled={emAcao}
                          onClick={() => void decidir(solicitacao, 'aprovar')}
                          className="rounded-lg bg-clinical-primary px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                        >
                          {emAcao ? 'Processando...' : 'Aprovar'}
                        </button>
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
