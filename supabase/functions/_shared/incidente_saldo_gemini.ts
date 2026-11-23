// _shared/incidente_saldo_gemini.ts — sinal operacional de HTTP 402 do Gemini
// (N45, risco R44 do Documento Mestre v9.2.1).
//
// Quando o Gemini responde 402 (saldo pré-pago esgotado / pagamento
// pendente), o USUÁRIO final recebe só uma mensagem neutra ("indisponível no
// momento"). Quem precisa saber a CAUSA é o administrador: esta função grava,
// na tabela de infraestrutura `configuracoes_sistema`, a chave
// `incidente_gemini_402` com o instante da última ocorrência. O Painel Web
// lê essa chave num banner exclusivo de admin e permite reconhecer/limpar
// (apagar a linha) depois da recarga no Google AI Studio.
//
// Segurança: a chave NÃO começa com `cliente_`, então a policy
// `configuracoes_sistema_select_cliente` não a expõe; só `eh_admin()` lê,
// altera ou apaga. A escrita aqui usa a chave secreta do projeto (ignora
// RLS) APENAS para este upsert de uma linha — nenhum outro dado é tocado e o
// valor da chave nunca é logado (Parte 6).
//
// Usa `fetch` direto no PostgREST (sem `createClient`): leve, testável por
// stub de `fetch` e sem depender de CDN externo.

export const CHAVE_INCIDENTE_SALDO_GEMINI = 'incidente_gemini_402';

const DESCRICAO_INCIDENTE =
  'Última ocorrência de HTTP 402 (saldo/faturamento) da API Gemini. Verifique o Google AI Studio e, após a recarga, reconheça o aviso no Painel Web.';

/**
 * Registra (ou atualiza) o incidente. Best-effort: NUNCA lança — falhar em
 * sinalizar o admin não pode piorar a resposta ao usuário (que já é um
 * erro). Falhas vão para o log do servidor, sem a chave.
 * Devolve `true` se gravou.
 */
export async function registrarIncidenteSaldoGemini(
  supabaseUrl: string | undefined,
  chaveSecreta: string | undefined,
  agora: Date = new Date(),
): Promise<boolean> {
  if (!supabaseUrl || !chaveSecreta) {
    console.error('incidente_saldo_gemini: SUPABASE_URL/chave secreta ausentes — incidente 402 NÃO registrado.');
    return false;
  }
  try {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      apikey: chaveSecreta,
      // `sb_secret_…` não é JWT: só vai em `apikey`. A chave legada (JWT)
      // também precisa do Bearer.
      ...(chaveSecreta.startsWith('eyJ') ? { Authorization: `Bearer ${chaveSecreta}` } : {}),
      Prefer: 'resolution=merge-duplicates,return=minimal',
    };
    const resposta = await fetch(`${supabaseUrl}/rest/v1/configuracoes_sistema?on_conflict=chave`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        chave: CHAVE_INCIDENTE_SALDO_GEMINI,
        valor: agora.toISOString(),
        descricao: DESCRICAO_INCIDENTE,
        atualizado_em: agora.toISOString(),
      }),
    });
    if (!resposta.ok) {
      console.error(`incidente_saldo_gemini: gravação falhou (HTTP ${resposta.status}).`);
      return false;
    }
    return true;
  } catch (erro) {
    console.error('incidente_saldo_gemini: erro ao gravar:', erro instanceof Error ? erro.message : 'desconhecido');
    return false;
  }
}
