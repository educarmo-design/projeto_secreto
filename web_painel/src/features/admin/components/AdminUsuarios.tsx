import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';

interface Usuario {
  id: string;
  nome: string | null;
  email: string | null;
  idade: number | null;
  criadoEm: string;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

/**
 * N06 (RELATÓRIO 20260811_0005) — listagem administrativa de USUÁRIOS
 * (atletas, `eh_profissional = false`) — distinta de `AdminProfissionais`.
 * Usa a RPC `admin_perfis_seguro` (D2, decifra nome/e-mail server-side,
 * escopada a admin) e filtra client-side por `eh_profissional`, já que a
 * RPC só filtra por `status_aprovacao` (atletas não passam pelo fluxo de
 * aprovação, então filtrar por status não faria sentido aqui).
 */
export function AdminUsuarios() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [usuarios, setUsuarios] = useState<Usuario[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);

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

    setUsuarios(
      (data ?? [])
        .filter((linha) => !linha.eh_profissional)
        .map((linha) => ({
          id: linha.id,
          nome: linha.nome,
          email: linha.email,
          idade: linha.idade,
          criadoEm: linha.criado_em,
        })),
    );
    setEstado('sucesso');
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Usuários</h1>
        <p className="text-sm text-clinical-muted">
          {estado === 'sucesso' ? `${usuarios.length} atleta(s) cadastrado(s).` : 'Contas de atletas (não-profissionais).'}
        </p>
      </header>

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
                <th className="px-4 py-3">Cadastrado em</th>
              </tr>
            </thead>
            <tbody>
              {usuarios.length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum usuário cadastrado ainda.
                  </td>
                </tr>
              ) : (
                usuarios.map((usuario) => (
                  <tr key={usuario.id} className="border-t border-clinical-border">
                    <td className="px-4 py-3 text-slate-200">{usuario.nome ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{usuario.email ?? '—'}</td>
                    <td className="px-4 py-3 text-slate-300">{usuario.idade ?? '—'}</td>
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
