import { useEffect, useState } from 'react';
import { supabase } from '@/core/supabase';
import type { StatusVinculo } from '@/core/types/database';
import { Toast, type ToastMessage } from '@/components/Toast';

interface Vinculo {
  id: string;
  profissionalId: string;
  profissionalNome: string | null;
  pacienteId: string;
  pacienteNome: string | null;
  status: StatusVinculo;
  tipoPagador: string;
  tipoProduto: string;
  dataInicio: string;
  dataSaida: string | null;
  fimCarencia: string | null;
  criadoEm: string;
}

type EstadoTela = 'carregando' | 'sucesso' | 'erro';

const ROTULO_STATUS: Record<StatusVinculo, string> = {
  pendente: 'Pendente',
  ativo: 'Ativo',
  em_carencia: 'Em carência',
  encerrado: 'Encerrado',
};

const COR_STATUS: Record<StatusVinculo, string> = {
  pendente: 'bg-clinical-primary/15 text-clinical-primary',
  ativo: 'bg-clinical-success/15 text-clinical-success',
  em_carencia: 'bg-amber-500/15 text-amber-400',
  encerrado: 'bg-clinical-muted/15 text-clinical-muted',
};

/**
 * N06 (RELATÓRIO 20260811_0006) — manutenção de vínculos profissional×
 * paciente (Adendo v4, F.2). Lê pela RPC D2 `admin_listar_vinculos`
 * (`20260811230000_n06_escrita_admin_alimentos_e_vinculos.sql`) — nome dos
 * dois lados decifrado server-side, nenhuma chave PGP chega aqui.
 *
 * "Aprovar"/"Encerrar" chamam RPCs dedicadas
 * (`admin_aprovar_vinculo`/`admin_encerrar_vinculo`), não um `.update()`
 * direto: `vinculos_profissional_paciente` não tem NENHUMA policy de UPDATE
 * para `authenticated` (os dois lados do vínculo encerram/aceitam via Edge
 * Function `manage-professional-link`, que roda com `service_role`) — as
 * RPCs replicam a mesma regra de negócio (fim_carencia de 30 dias ao
 * encerrar, data_inicio = hoje ao aprovar) e são a ÚNICA porta de escrita
 * em SQL direto nesta tabela, restrita a admin.
 */
export function AdminVinculos() {
  const [estado, setEstado] = useState<EstadoTela>('carregando');
  const [vinculos, setVinculos] = useState<Vinculo[]>([]);
  const [mensagemErro, setMensagemErro] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastMessage | null>(null);
  const [idsEmAcao, setIdsEmAcao] = useState<Set<string>>(new Set());

  useEffect(() => {
    void carregar();
  }, []);

  async function carregar() {
    setEstado('carregando');
    const { data, error } = await supabase.rpc('admin_listar_vinculos');

    if (error) {
      setEstado('erro');
      setMensagemErro(error.message);
      return;
    }

    setVinculos(
      (data ?? []).map((linha) => ({
        id: linha.id,
        profissionalId: linha.profissional_id,
        profissionalNome: linha.profissional_nome,
        pacienteId: linha.paciente_id,
        pacienteNome: linha.paciente_nome,
        status: linha.status,
        tipoPagador: linha.tipo_pagador,
        tipoProduto: linha.tipo_produto,
        dataInicio: linha.data_inicio,
        dataSaida: linha.data_saida,
        fimCarencia: linha.fim_carencia,
        criadoEm: linha.criado_em,
      })),
    );
    setEstado('sucesso');
  }

  async function aprovar(vinculo: Vinculo) {
    setIdsEmAcao((atual) => new Set(atual).add(vinculo.id));
    const { error } = await supabase.rpc('admin_aprovar_vinculo', { p_vinculo_id: vinculo.id });
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(vinculo.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível aprovar: ${error.message}` });
      return;
    }

    setToast({ variant: 'success', text: 'Vínculo aprovado.' });
    void carregar();
  }

  async function encerrar(vinculo: Vinculo) {
    if (
      !window.confirm(
        `Encerrar o vínculo entre "${vinculo.profissionalNome ?? '—'}" e "${vinculo.pacienteNome ?? '—'}"?`,
      )
    ) {
      return;
    }

    setIdsEmAcao((atual) => new Set(atual).add(vinculo.id));
    const { error } = await supabase.rpc('admin_encerrar_vinculo', { p_vinculo_id: vinculo.id });
    setIdsEmAcao((atual) => {
      const proximo = new Set(atual);
      proximo.delete(vinculo.id);
      return proximo;
    });

    if (error) {
      setToast({ variant: 'error', text: `Não foi possível encerrar: ${error.message}` });
      return;
    }

    setToast({ variant: 'success', text: 'Vínculo encerrado.' });
    void carregar();
  }

  return (
    <div>
      <header className="mb-6">
        <h1 className="text-lg font-semibold text-slate-100">Vínculos (Profissional × Usuário)</h1>
        <p className="text-sm text-clinical-muted">
          {estado === 'sucesso' ? `${vinculos.length} vínculo(s).` : 'Relações profissional-paciente e seu status.'}
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
                <th className="px-4 py-3">Profissional</th>
                <th className="px-4 py-3">Paciente</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Início</th>
                <th className="px-4 py-3">Saída</th>
                <th className="px-4 py-3">Fim carência</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {vinculos.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-clinical-muted">
                    Nenhum vínculo cadastrado ainda.
                  </td>
                </tr>
              ) : (
                vinculos.map((vinculo) => {
                  const emAcao = idsEmAcao.has(vinculo.id);
                  return (
                    <tr key={vinculo.id} className="border-t border-clinical-border">
                      <td className="px-4 py-3 text-slate-200">{vinculo.profissionalNome ?? '—'}</td>
                      <td className="px-4 py-3 text-slate-200">{vinculo.pacienteNome ?? '—'}</td>
                      <td className="px-4 py-3">
                        <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${COR_STATUS[vinculo.status]}`}>
                          {ROTULO_STATUS[vinculo.status]}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-slate-300">
                        {new Date(vinculo.dataInicio).toLocaleDateString('pt-BR')}
                      </td>
                      <td className="px-4 py-3 text-slate-300">
                        {vinculo.dataSaida ? new Date(vinculo.dataSaida).toLocaleDateString('pt-BR') : '—'}
                      </td>
                      <td className="px-4 py-3 text-slate-300">
                        {vinculo.fimCarencia ? new Date(vinculo.fimCarencia).toLocaleDateString('pt-BR') : '—'}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex justify-end gap-2">
                          {vinculo.status === 'pendente' && (
                            <button
                              type="button"
                              disabled={emAcao}
                              onClick={() => void aprovar(vinculo)}
                              className="rounded-lg bg-clinical-primary px-3 py-1.5 text-xs font-medium text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60"
                            >
                              Aprovar
                            </button>
                          )}
                          {vinculo.status !== 'encerrado' && (
                            <button
                              type="button"
                              disabled={emAcao}
                              onClick={() => void encerrar(vinculo)}
                              className="rounded-lg border border-clinical-border px-3 py-1.5 text-xs font-medium text-clinical-muted transition hover:border-clinical-critical hover:text-clinical-critical disabled:cursor-not-allowed disabled:opacity-60"
                            >
                              Encerrar
                            </button>
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
