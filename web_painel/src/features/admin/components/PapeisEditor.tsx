import { useState } from 'react';
import { supabase } from '@/core/supabase';
import type { ToastMessage } from '@/components/Toast';

export interface Papel {
  id: string;
  nomeCodigo: string;
  nomeExibicao: string;
}

interface PapeisEditorProps {
  usuarioId: string;
  papeisDoUsuario: Papel[];
  todosPapeis: Papel[];
  onMudou: (novosPapeisDoUsuario: Papel[]) => void;
  onToast: (toast: ToastMessage) => void;
}

/**
 * N06 (RELATÓRIO 20260811_0006) — chips de papel + seletor de "adicionar",
 * reusado por `AdminUsuarios.tsx` e `AdminProfissionais.tsx`. Grava direto
 * em `usuario_papeis` (não via RPC): ao contrário de `papeis_permissoes`
 * (D3, só editável pela RPC `admin_atualizar_permissao_papel`),
 * `usuario_papeis` TEM policy de INSERT/UPDATE/DELETE para admin
 * (`20260811200000_d3_rbac_dinamico.sql`) — não é a matriz de permissões em
 * si, é só "quem acumula qual papel", então o RLS direto já é suficiente.
 *
 * D3 é aditivo ao gate binário antigo (`is_admin`/`eh_profissional`/
 * `tipo_profissional`) — atribuir/remover um papel aqui não muda esses
 * campos nem a decisão de aprovação (ver `AdminDashboard.tsx`).
 */
export function PapeisEditor({ usuarioId, papeisDoUsuario, todosPapeis, onMudou, onToast }: PapeisEditorProps) {
  const [emAcao, setEmAcao] = useState(false);

  const idsAtuais = new Set(papeisDoUsuario.map((papel) => papel.id));
  const disponveisParaAdicionar = todosPapeis.filter((papel) => !idsAtuais.has(papel.id));

  // Recebe o id direto do evento — não lê de um `useState` intermediário
  // (o `<select>` some da árvore assim que o papel é adicionado, então não
  // há "resetar a seleção depois"; e ler `papelSelecionado` do state dentro
  // do próprio handler de `onChange` pegaria o valor de ANTES do clique,
  // por causa do batching do React).
  async function adicionar(papelId: string) {
    const papel = todosPapeis.find((item) => item.id === papelId);
    if (!papel) return;

    setEmAcao(true);
    const { error } = await supabase.from('usuario_papeis').insert({ usuario_id: usuarioId, papel_id: papel.id });
    setEmAcao(false);

    if (error) {
      onToast({ variant: 'error', text: `Não foi possível adicionar o papel "${papel.nomeExibicao}": ${error.message}` });
      return;
    }

    onMudou([...papeisDoUsuario, papel]);
  }

  async function remover(papel: Papel) {
    setEmAcao(true);
    const { error } = await supabase
      .from('usuario_papeis')
      .delete()
      .eq('usuario_id', usuarioId)
      .eq('papel_id', papel.id);
    setEmAcao(false);

    if (error) {
      onToast({ variant: 'error', text: `Não foi possível remover o papel "${papel.nomeExibicao}": ${error.message}` });
      return;
    }

    onMudou(papeisDoUsuario.filter((item) => item.id !== papel.id));
  }

  return (
    <div className="flex flex-wrap items-center gap-1.5">
      {papeisDoUsuario.length === 0 && <span className="text-xs text-clinical-muted">Nenhum papel</span>}
      {papeisDoUsuario.map((papel) => (
        <span
          key={papel.id}
          className="flex items-center gap-1 rounded-full bg-clinical-primary/15 px-2 py-0.5 text-xs font-medium text-clinical-primary"
        >
          {papel.nomeExibicao}
          <button
            type="button"
            disabled={emAcao}
            onClick={() => void remover(papel)}
            aria-label={`Remover papel ${papel.nomeExibicao}`}
            className="text-clinical-primary/70 transition hover:text-clinical-critical disabled:cursor-not-allowed"
          >
            ×
          </button>
        </span>
      ))}
      {disponveisParaAdicionar.length > 0 && (
        <select
          value=""
          disabled={emAcao}
          onChange={(event) => {
            if (event.target.value) void adicionar(event.target.value);
          }}
          aria-label="Adicionar papel"
          className="rounded-full border border-clinical-border bg-clinical-bg px-2 py-0.5 text-xs text-clinical-muted outline-none focus:border-clinical-primary disabled:opacity-60"
        >
          <option value="">+ papel</option>
          {disponveisParaAdicionar.map((papel) => (
            <option key={papel.id} value={papel.id}>
              {papel.nomeExibicao}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}
