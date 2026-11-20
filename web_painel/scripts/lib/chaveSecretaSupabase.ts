/**
 * Leitura da chave PRIVILEGIADA do Supabase para os scripts administrativos
 * (N44 / S8.1 do Documento Mestre v9.2.1).
 *
 * `SUPABASE_SECRET_KEY` (`sb_secret_…`) é a chave atual; `SUPABASE_SERVICE_ROLE_KEY`
 * (JWT legado) só é lida como fallback durante a transição, enquanto o par
 * legado ainda está ativo no Dashboard. Depois do Passo 4 (desativar o par
 * legado) o fallback deixa de ser alcançado e pode ser removido.
 *
 * A chave vive SÓ em `web_painel/.env.local` (nunca versionado — ver
 * `.env.local.example`) e nunca é logada, nem em mensagem de erro. Esta chave
 * ignora RLS: só server-side/CLI, nunca em código que roda no navegador (a
 * Supabase devolve 401 para uma chave secreta enviada por um navegador).
 */
export function lerChaveSecretaAdmin(): string {
  const chave = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!chave) {
    throw new Error(
      'SUPABASE_SECRET_KEY não configurada — confirme web_painel/.env.local (veja .env.local.example).',
    );
  }
  return chave;
}
