import { useEffect, useState } from 'react';
import { TriangleAlert } from 'lucide-react';
import { supabase } from '@/core/supabase';

/** Chave gravada pelas Edge Functions (`_shared/incidente_saldo_gemini.ts`) num HTTP 402 do Gemini. */
const CHAVE_INCIDENTE_SALDO_GEMINI = 'incidente_gemini_402';

/**
 * N45 (risco R44) — banner EXCLUSIVO de administrador: a API do Gemini
 * respondeu HTTP 402 (saldo pré-pago esgotado / pagamento pendente), então a
 * análise por IA dos pacientes está indisponível. O usuário final nunca vê a
 * causa; ela chega só aqui.
 *
 * Quem decide mostrar é o BANCO, não esta tela: `configuracoes_sistema` só
 * devolve a chave `incidente_gemini_402` a quem passa em `eh_admin()` (RLS) —
 * paciente ou profissional não-admin que montasse este componente leria 0
 * linhas e nada apareceria. `DashboardLayout` ainda só o monta quando
 * `isAdmin` (defesa em profundidade, Zero Trust).
 *
 * "Reconhecer" apaga a linha (policy `configuracoes_sistema_delete_admin`).
 * Se o saldo continuar zerado, o próximo 402 grava o aviso de novo.
 */
export function AlertaSaldoGemini() {
  const [ocorridoEm, setOcorridoEm] = useState<string | null>(null);
  const [limpando, setLimpando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let cancelado = false;
    async function carregar() {
      const { data, error } = await supabase
        .from('configuracoes_sistema')
        .select('valor')
        .eq('chave', CHAVE_INCIDENTE_SALDO_GEMINI)
        .maybeSingle();
      if (cancelado || error || !data) return;
      setOcorridoEm(data.valor ?? '');
    }
    void carregar();
    return () => {
      cancelado = true;
    };
  }, []);

  async function reconhecer() {
    setLimpando(true);
    setErro(null);
    const { error } = await supabase.from('configuracoes_sistema').delete().eq('chave', CHAVE_INCIDENTE_SALDO_GEMINI);
    setLimpando(false);
    if (error) {
      setErro(`Não foi possível limpar o aviso: ${error.message}`);
      return;
    }
    setOcorridoEm(null);
  }

  if (ocorridoEm === null) return null;

  const quando = ocorridoEm ? new Date(ocorridoEm) : null;
  const quandoTexto = quando && !Number.isNaN(quando.getTime()) ? quando.toLocaleString('pt-BR') : null;

  return (
    <div role="status" className="mb-6 rounded-xl border border-amber-500/40 bg-amber-500/10 p-4 text-sm text-amber-100">
      <div className="flex items-start gap-3">
        <TriangleAlert size={20} className="mt-0.5 shrink-0" aria-hidden="true" />
        <div className="flex-1">
          <p className="font-medium">API Gemini respondeu HTTP 402 (saldo/faturamento)</p>
          <p className="mt-1">
            A análise por IA (foto, áudio, texto e busca de alimentos) está indisponível para os usuários.
            {quandoTexto ? ` Última ocorrência: ${quandoTexto}.` : ''} Verifique o saldo e o faturamento no Google AI
            Studio e, depois da recarga, reconheça este aviso.
          </p>
          {erro && <p className="mt-2 text-red-300">{erro}</p>}
          <button
            type="button"
            onClick={() => void reconhecer()}
            disabled={limpando}
            className="mt-3 rounded-lg border border-amber-500/50 px-3 py-1.5 font-medium transition hover:bg-amber-500/20 disabled:opacity-60"
          >
            {limpando ? 'Limpando…' : 'Reconhecer e limpar aviso'}
          </button>
        </div>
      </div>
    </div>
  );
}
