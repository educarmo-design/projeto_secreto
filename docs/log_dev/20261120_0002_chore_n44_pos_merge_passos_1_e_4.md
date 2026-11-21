# 20261120_0002 — N44: pós-merge (Passos 1 e 4 do fundador, ajustes e verificação)

**Data:** 2026-11-20
**Branch:** `docs/n44-pos-merge-log` (a partir de `main`, após o merge do PR #23)
**Persona:** DevOps/Segurança (Mestre v9.2.1 — S8.1, decisão 92, R43)

## Contexto

Continuação de `20261120_0001_chore_n44_migracao_chaves_env_ci.md`. Aquele log cobre os Passos 2 e 3 (código/config). Este cobre o que aconteceu depois: o fundador executou o Passo 1 (criou as chaves) e o Passo 4 (desativou o par legado, às 20:29 UTC), o PR #23 foi mesclado e os sintomas pós-desativação foram corrigidos.

## O que foi feito

1. **Diagnóstico de login.** Com a senha de uma conta redefinida via SQL, o login no painel falhava fora do `localhost`. Login direto na API de autenticação com a chave publicável do `web_painel/.env` → HTTP 200. A `anon` antiga → `401 "Legacy API keys are disabled"` (desativada em 2026-11-20T20:29:34Z). Causa: Cloudflare (build da `main`, que ainda lia só `VITE_SUPABASE_ANON_KEY`) e o app instalado (anon embutida no build) usavam a chave legada.
2. **Chave publicável versionada.** O PR #23 ainda tinha `VITE_SUPABASE_PUBLISHABLE_KEY=` vazia (a chave estava só na cópia local do fundador). Commit `7c70124` levou só `web_painel/.env` (valor público por desenho) ao PR antes do merge.
3. **Merge do PR #23** na `main` (commit `2b4f311`), com autorização explícita do fundador e 5/5 checks verdes. O Cloudflare publica a `main` sozinho.
4. **`config_local.json` (local, ignorado pelo git)** passou a ter `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` (valor vindo do `web_painel/.env`); backup do arquivo antigo na pasta temporária. O app precisa ser recompilado com `flutter run --dart-define-from-file=config_local.json`, pois a chave é embutida no build.
5. **Redefinição de senha** de duas contas (a do fundador e a conta de teste `atleta1000@teste.com`) por SQL no projeto vinculado (`auth.users.encrypted_password` com bcrypt via `extensions.crypt`). A senha não foi gravada em nenhum arquivo versionado.
6. **Servidor de desenvolvimento** do painel iniciado em `localhost:5173` para recarregar o `.env`.

## Problemas encontrados

- **CI da `main` falhou uma vez** em "Edge Functions (check + testes)": `Integrity check failed … esm.sh/tslib@2.8.1/denonext/tslib.mjs` (hash diferente do `deno.lock`). Mesmo código tinha passado no PR minutos antes; o job reexecutado passou. Causa: o esm.sh não garante bytes idênticos para a mesma URL. Pode se repetir. Mitigação possível (não feita): fixar versões exatas e regenerar os `deno.lock`, ou repetir o job nesse erro específico.
- `wrangler` não autenticado nesta máquina; deploy manual no Cloudflare não foi feito (o deploy é pela integração Git).
- `config_local.example.json` tem alteração local não commitada com uma chave publicável real; arquivo de exemplo deveria ter placeholder.

## Verificação

- Login por senha na API de autenticação com a chave publicável: HTTP 200 (conta do fundador). Hash da senha nova conferido em ambas as contas (`senha_confere: true`).
- Chave legada: `401 Legacy API keys are disabled` (confirma que o Passo 4 está ativo).
- CI da `main`: 4/4 jobs verdes após reexecução.
- **Relato do fundador:** login no `localhost` do painel funcionou; ao final, "está tudo funcionando" (painel publicado e app).
- **Não verificado por mim:** o deploy do Cloudflare em si e o login no app compilado.

## Riscos

- Fallbacks legados (`SUPABASE_ANON_KEY`/`SERVICE_ROLE_KEY`) são agora código morto; remoção é limpeza opcional.
- Variável do Cloudflare tem prioridade sobre o `.env`: `VITE_SUPABASE_PUBLISHABLE_KEY` deve ser igual nos dois.
- Qualquer app Flutter instalado de antes continua falhando até ser recompilado.

## Arquivos

- `docs/log_dev/20261120_0002_chore_n44_pos_merge_passos_1_e_4.md` (este) e linha em `docs/log_dev/INDICE.md`.
- Já na `main` via PR #23: `web_painel/.env` (chave publicável, commit `7c70124`).
