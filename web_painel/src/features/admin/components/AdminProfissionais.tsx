import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { StatusAprovacaoUsuario } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';
import { PapeisEditor, type Papel } from './PapeisEditor';

interface Profissional {
  id: string;
  nome: string | null;
  email: string | null;
  tipoProfissional: string | null;
  registroProfissional: string | null;
  statusAprovacao: StatusAprovacaoUsuario;
  idade: number | null;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

const ROTULO_STATUS: Record<StatusAprovacaoUsuario, string> = {
  pendente: 'Pendente',
  aprovado: 'Aprovado',
  rejeitado: 'Rejeitado',
};

/**
 * N06 (RELATÓRIO 20260811_0005/0006) — listagem E gestão administrativa de
 * TODOS os profissionais (`eh_profissional = true`), qualquer
 * `status_aprovacao` — diferente da "Sala de Espera" (`AdminDashboard.tsx`),
 * que só mostra `pendente` e é o fluxo normal de aprovar/rejeitar convite.
 * Esta tela é a visão de manutenção ampla: o `<select>` de status aqui
 * existe para o caso "preciso corrigir manualmente" (reabrir um rejeitado
 * por engano, revogar um aprovado), não para substituir a Sala de Espera —
 * as duas escrevem a mesma coluna (`perfis_usuarios.status_aprovacao`),
 * então não há conflito de fonte de verdade.
 */
export function AdminProfissionais() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [profissionais, setProfissionais] = useState<Profissional[]>([]);
  const [papeisPorUsuario, setPapeisPorUsuario] = useState<Record<string, Papel[]>>({});
  const [todosPapeis, setTodosPapeis] = useState<Papel[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase.rpc('admin_perfis_seguro');

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    const linhasProfissionais = (data ?? []).filter((linha) => linha.eh_profissional);
    const ids = linhasProfissionais.map((linha) => linha.id);

    const [papeisResp, usuarioPapeisResp] = await Promise.all([
      supabase.from('papeis').select('id, nome_codigo, nome_exibicao').order('nome_exibicao'),
      ids.length > 0
        ? supabase.from('usuario_papeis').select('usuario_id, papel_id').in('usuario_id', ids)
        : Promise.resolve({ data: [], error: null }),
    ]);

    const papeis = (papeisResp.data ?? []).map((linha) => ({
      id: linha.id,
      nomeCodigo: linha.nome_codigo,
      nomeExibicao: linha.nome_exibicao,
    }));
    const papeisPorId = new Map(papeis.map((papel) => [papel.id, papel]));

    const mapa: Record<string, Papel[]> = {};
    for (const linha of usuarioPapeisResp.data ?? []) {
      const papel = papeisPorId.get(linha.papel_id);
      if (!papel) continue;
      (mapa[linha.usuario_id] ??= []).push(papel);
    }

    setTodosPapeis(papeis);
    setPapeisPorUsuario(mapa);
    setProfissionais(
      linhasProfissionais.map((linha) => ({
        id: linha.id,
        nome: linha.nome,
        email: linha.email,
        tipoProfissional: linha.tipo_profissional,
        registroProfissional: linha.registro_profissional,
        statusAprovacao: linha.status_aprovacao,
        idade: linha.idade,
      })),
    );
    setEstado('sucesso');
  }

  async function alterarStatus(profissional: Profissional, novoStatus: StatusAprovacaoUsuario) {
    if (novoStatus === profissional.statusAprovacao) return;

    setIdsEmAcao((atual) => new Set(atual).add(profissional.id));
    const { error } = await supabase
      .from('perfis_usuarios')
      .update({ status_aprovacao: novoStatus })
      .eq('id', profissional.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(profissional.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível atualizar o status: ${error.message}` });
      return;
    }

    setProfissionais((atual) =>
      atual.map((item) => (item.id === profissional.id ? { ...item, statusAprovacao: novoStatus } : item)),
    );
    setToast({ variant: 'success', text: `Status de "${profissional.nome ?? profissional.email}" atualizado.` });
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Profissionais</h1>
        <p className="text-sm text-clinical-muted">
          {estado === 'sucesso' ? `${profissionais.length} profissional(is) cadastrado(s).` : 'Todos os profissionais, qualquer status.'}
        </p>
      </header>

      {toast && <Toast toast={toast} onDismiss={() => setToast(null)} />}

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
                <th className="px-4 py-3">E-mail</th>
                <th className="px-4 py-3">Área de atuação</th>
                <th className="px-4 py-3">Registro Profissional</th>
                <th className="px-4 py-3">Idade</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Papéis</th>
              </tr>
            </thead>
            <tbody>
              {profissionais.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum profissional cadastrado ainda.
                  </td>
                </tr>
              ) : (
                profissionais.map((profissional) => (
                  <tr key={profissional.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 text-slate-200">{profissional.nome ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{profissional.email ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{profissional.tipoProfissional ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{profissional.registroProfissional ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{profissional.idade ?? '—'}</td>
                    <td className="px-4 py-3">
                      <select
                        value={profissional.statusAprovacao}
                        disabled={idsEmAcao.has(profissional.id)}
                        onChange={(event) =>
                          void alterarStatus(profissional, event.target.value as StatusAprovacaoUsuario)
                        }
                        className="rounded-lg border border-clinical-border bg-clinical-bg px-2 py-1 text-xs text-slate-100 outline-none focus:border-clinical-primary disabled:opacity-60"
                      >
                        {Object.entries(ROTULO_STATUS).map(([valor, rotulo]) => (
                          <option key={valor} value={valor}>
                            {rotulo}
                          </option>
                        ))}
                      </select>
                    </td>
                    <td className="px-4 py-3">
                      <PapeisEditor
                        usuarioId={profissional.id}
                        papeisDoUsuario={papeisPorUsuario[profissional.id] ?? []}
                        todosPapeis={todosPapeis}
                        onMudou={(novos) =>
                          setPapeisPorUsuario((atual) => ({ ...atual, [profissional.id]: novos }))
                        }
                        onToast={setToast}
                      />
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
