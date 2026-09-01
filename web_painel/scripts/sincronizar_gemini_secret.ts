/**
 * RELATÓRIO 20260901_0001 (R15, Bloco B item 5) — consolida a
 * `GEMINI_API_KEY` duplicada: hoje ela existe em DOIS lugares
 * independentes, sem nenhuma sincronização automática —
 *   1. Secret do projeto Supabase (`supabase secrets set`), lida em
 *      runtime por `extract-metric-photo`/`search-food` via
 *      `Deno.env.get('GEMINI_API_KEY')`.
 *   2. `web_painel/.env.local` (nunca commitado), lida pelos scripts
 *      administrativos deste diretório (`curar_catalogo_alimentos_ia.ts`,
 *      `seed_food_embeddings.ts`).
 * Se alguém trocar o valor num lugar só (ex.: rotacionar a chave no Google
 * AI Studio e atualizar só o `.env.local`), os dois lados divergem
 * silenciosamente — o mesmo padrão de risco já documentado pra
 * `EMBEDDING_MODEL_NAME` no cabeçalho de `seed_food_embeddings.ts`.
 *
 * Este script NÃO cria uma terceira cópia — ele torna `web_painel/.env.local`
 * a ÚNICA fonte onde a chave é digitada, e empurra esse valor pro Supabase
 * a cada execução, IDEMPOTENTE (rodar de novo sem mudar nada não tem
 * efeito). A direção é sempre local → Supabase, nunca o contrário: a API
 * de secrets do Supabase é escrita-só por desenho (`supabase secrets list`
 * nunca devolve o valor em texto puro, só um hash) — não existe "puxar" o
 * valor de volta, então o arquivo local PRECISA ser onde o valor de
 * verdade mora.
 *
 * Escopo deliberadamente estreito: escreve um arquivo TEMPORÁRIO contendo
 * só a linha `GEMINI_API_KEY=...` e chama
 * `supabase secrets set --env-file <temp>` só com ela — nunca
 * `--env-file .env.local` direto, que empurraria TODAS as variáveis do
 * arquivo (incluindo `SUPABASE_SERVICE_ROLE_KEY`, fora do escopo deste
 * script) como secrets de uma vez, um efeito colateral que ninguém pediu.
 * O arquivo temporário nunca é escrito no diretório do projeto (usa o
 * temp dir do SO) e é apagado no `finally`, mesmo se o comando falhar.
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Confirme .env.local com GEMINI_API_KEY preenchida (o valor real)
 *   3. npm run secrets:sync-gemini
 *      Requer o Supabase CLI instalado e logado (`npx supabase login`) e
 *      o projeto linkado (`npx supabase link`) — mesma sessão que já
 *      funciona pra `supabase secrets list`/`supabase db push`.
 */
import { config } from 'dotenv';
import { execSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

config(); // .env (valores públicos, versionados)
config({ path: '.env.local', override: true }); // .env.local (segredos, nunca commitado)

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

if (!GEMINI_API_KEY || GEMINI_API_KEY === 'sua_gemini_api_key_aqui') {
  console.error(
    '❌ GEMINI_API_KEY ausente ou ainda com o valor de exemplo em web_painel/.env.local.\n' +
      '   Preencha com a chave real (Google AI Studio) antes de sincronizar.',
  );
  process.exit(1);
}

// Diretório temporário do SO (nunca dentro do projeto) — o arquivo some
// no finally abaixo, mesmo se `supabase secrets set` falhar.
const dirTemporario = mkdtempSync(join(tmpdir(), 'gemini-secret-sync-'));
const arquivoTemporario = join(dirTemporario, '.env');

try {
  writeFileSync(arquivoTemporario, `GEMINI_API_KEY=${GEMINI_API_KEY}\n`, { mode: 0o600 });

  console.log('🔄 Sincronizando GEMINI_API_KEY (web_painel/.env.local -> secret do projeto Supabase)...');
  // `execSync` com string (não `execFileSync` com array) — no Windows,
  // `npx` é um shim `.cmd`, que só o shell sabe executar; `execFileSync`
  // falha (ENOENT sem shell, EINVAL tentando `npx.cmd` diretamente). Uma
  // única string comando evita o aviso de depreciação do Node sobre
  // `shell: true` + array de argumentos não escapados — aqui só há UM
  // valor interpolado (o caminho do arquivo temporário, gerado por este
  // mesmo script, nunca entrada externa), colocado entre aspas duplas.
  execSync(`npx supabase secrets set --env-file "${arquivoTemporario}"`, { stdio: 'inherit' });
  console.log('✅ Secret do projeto atualizado. Edge Functions redeployadas depois deste ponto já usam o valor novo.');
  console.log('   Functions já deployadas continuam com o valor antigo até o próximo deploy (supabase functions deploy).');
} finally {
  // Apaga o diretório temporário inteiro (arquivo + pasta) — nunca deixa
  // a chave em texto puro sobrando em disco fora do .env.local original.
  rmSync(dirTemporario, { recursive: true, force: true });
}
