import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { StatusAprovacaoUsuario } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';
import { PapeisEditor, type Papel } from './PapeisEditor';

interface Usuario {
  id: string;
  nome: string | null;
  email: string | null;
  idade: number | null;
  statusAprovacao: StatusAprovacaoUsuario;
  criadoEm: string;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

const ROTULO_STATUS: Record<StatusAprovacaoUsuario, string> = {
  pendente: 'Pendente',
  aprovado: 'Aprovado',
  rejeitado: 'Rejeitado',
};

/**
 * N06 (RELATÓRIO 20260811_0005/0006) — listagem E gestão administrativa de
 * USUÁRIOS (atletas, `eh_profissional = false`) — distinta de
 * `AdminProfissionais`. Usa a RPC `admin_perfis_seguro` (D2, decifra nome/
 * e-mail server-side, escopada a admin) e filtra client-side por
 * `eh_profissional`, já que a RPC só filtra por `status_aprovacao` (atletas
 * não passam pelo fluxo de aprovação por convite, mas a coluna existe e é
 * editável — mesmo grant/RLS de admin de `AdminDashboard.tsx`).
 *
 * Status e papéis são gravados DIRETO nas tabelas (`perfis_usuarios`/
 * `usuario_papeis`), sem RPC — RLS de admin (`perfis_usuarios_update_admin`,
 * `usuario_papeis_*_admin`) já cobre os dois. A RPC `admin_perfis_seguro` só
 * é necessária para LER PII cifrada (D2); escrever `status_aprovacao`/papel
 * não toca em nome/telefone/e-mail.
 */
export function AdminUsuarios() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [usuarios, setUsuarios] = useState<Usuario[]>([]);
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

    const linhasUsuarios = (data ?? []).filter((linha) => !linha.eh_profissional);
    const ids = linhasUsuarios.map((linha) => linha.id);

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
    setUsuarios(
      linhasUsuarios.map((linha) => ({
        id: linha.id,
        nome: linha.nome,
        email: linha.email,
        idade: linha.idade,
        statusAprovacao: linha.status_aprovacao,
        criadoEm: linha.criado_em,
      })),
    );
    setEstado('sucesso');
  }

  async function alterarStatus(usuario: Usuario, novoStatus: StatusAprovacaoUsuario) {
    if (novoStatus === usuario.statusAprovacao) return;

    setIdsEmAcao((atual) => new Set(atual).add(usuario.id));
    const { error } = await supabase
      .from('perfis_usuarios')
      .update({ status_aprovacao: novoStatus })
      .eq('id', usuario.id);
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(usuario.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível atualizar o status: ${error.message}` });
      return;
    }

    setUsuarios((atual) =>
      atual.map((item) => (item.id === usuario.id ? { ...item, statusAprovacao: novoStatus } : item)),
    );
    setToast({ variant: 'success', text: `Status de "${usuario.nome ?? usuario.email}" atualizado.` });
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Usuários</h1>
        <p className="text-sm text-clinical-muted">
          {estado === 'sucesso' ? `${usuarios.length} atleta(s) cadastrado(s).` : 'Contas de atletas (não-profissionais).'}
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
                <th className="px-4 py-3">Idade</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Papéis</th>
                <th className="px-4 py-3">Cadastrado em</th>
              </tr>
            </thead>
            <tbody>
              {usuarios.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum usuário cadastrado ainda.
                  </td>
                </tr>
              ) : (
                usuarios.map((usuario) => (
                  <tr key={usuario.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 text-slate-200">{usuario.nome ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{usuario.email ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{usuario.idade ?? '—'}</td>
                    <td className="px-4 py-3">
                      <select
                        value={usuario.statusAprovacao}
                        disabled={idsEmAcao.has(usuario.id)}
                        onChange={(event) => void alterarStatus(usuario, event.target.value as StatusAprovacaoUsuario)}
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
                        usuarioId={usuario.id}
                        papeisDoUsuario={papeisPorUsuario[usuario.id] ?? []}
                        todosPapeis={todosPapeis}
                        onMudou={(novos) =>
                          setPapeisPorUsuario((atual) => ({ ...atual, [usuario.id]: novos }))
                        }
                        onToast={setToast}
                      />
                    </td>
                    <td className="px-4 py-3 text-slate-300">
                      {new Date(usuario.criadoEm).toLocaleDateString('pt-BR')}
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
