import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { StatusAprovacaoUsuario } from '@/core/types/database';

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
 * N06 (RELATÓRIO 20260811_0005) — listagem administrativa de TODOS os
 * profissionais (`eh_profissional = true`), qualquer `status_aprovacao` —
 * diferente da "Sala de Espera" (`AdminDashboard.tsx`), que só mostra
 * `pendente`. Esta tela é a visão de manutenção/consulta ampla; aprovar ou
 * rejeitar continua sendo função exclusiva da Sala de Espera (não duplica
 * essa ação aqui, para não ter dois lugares fazendo a mesma escrita).
 */
export function AdminProfissionais() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [profissionais, setProfissionais] = useState<Profissional[]>([]);
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

    setProfissionais(
      (data ?? [])
        .filter((linha) => linha.eh_profissional)
        .map((linha) => ({
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

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Profissionais</h1>
        <p className="text-sm text-clinical-muted">
          {estado === 'sucesso' ? `${profissionais.length} profissional(is) cadastrado(s).` : 'Todos os profissionais, qualquer status.'}
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
                <th className="px-4 py-3">Área de atuação</th>
                <th className="px-4 py-3">Registro Profissional</th>
                <th className="px-4 py-3">Idade</th>
                <th className="px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {profissionais.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-center text-clinical-muted">
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
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${
                          profissional.statusAprovacao === 'aprovado'
                            ? 'bg-clinical-success/15 text-clinical-success'
                            : profissional.statusAprovacao === 'rejeitado'
                              ? 'bg-clinical-critical/15 text-clinical-critical'
                              : 'bg-clinical-primary/15 text-clinical-primary'
                        }`}
                      >
                        {ROTULO_STATUS[profissional.statusAprovacao]}
                      </span>
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
