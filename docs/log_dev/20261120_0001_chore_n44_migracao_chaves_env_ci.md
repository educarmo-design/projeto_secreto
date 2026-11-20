# 20261120_0001 — N44: migração das chaves Supabase (Passos 2 e 3) + `web_painel/.env` versionado + CI mínimo

**Data:** 2026-11-20
**Branch:** `chore/n44-migracao-chaves-supabase-env-ci` (a partir de `main`)
**Persona:** DevOps/Segurança (Mestre v9.2.1 — S8.1, decisão 92, R43)

## Contexto

N44 é o primeiro item do Bloco 1 e tem prazo imposto pela Supabase (fim de 2026): `anon`/`service_role` serão descontinuadas em favor de `sb_publishable_…`/`sb_secret_…`. Esta tarefa faz a parte de código/configuração (Passos 2 e 3 do S8.1). O Passo 1 (criar as chaves novas) e o Passo 4 (desativar o par legado) são do fundador, no Dashboard. **As chaves legadas NÃO foram desativadas.** Fora de escopo, respeitado: migração do JWT secret para chaves assimétricas.

## Auditoria (antes de editar) — o que a premissa da tarefa acertou e errou

| Premissa | Achado |
|---|---|
| "Correção local de Convidar Paciente, que existe só na máquina do fundador" | Era **só o valor** de `VITE_MANAGE_PROFESSIONAL_LINK_ENDPOINT` no `.env` local (relatório 20260917_0003). O `.env.example` versionado já tinha o mesmo valor. Nenhum código estava só na máquina do fundador. |
| "Versionar `.env` conforme o `.env.example`" | O `.env.example` **tinha duas armadilhas**: `VITE_SUPABASE_URL` terminando em `/rest/v1/` (o `supabase-js` acrescenta o sufixo sozinho → URL duplicada, painel quebrado em qualquer clone) e um JWT `anon` real embutido. Versionei o `.env` com a **origem** da URL, e o exemplo foi corrigido. |
| "`.env` está no `.gitignore`" | Eram **três** camadas: `.env` (raiz, vale em qualquer pasta), `web_painel/.env` (raiz) e `.env` em `web_painel/.gitignore`. As três tratadas. |
| Edge Functions leem `SUPABASE_*_KEY` | A documentação oficial confirma: `SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` **continuam existindo mas carregam as chaves LEGADAS** e param quando o par legado for desativado. As novas vêm em `SUPABASE_SECRET_KEYS`/`SUPABASE_PUBLISHABLE_KEYS` (dicionários JSON). Sem a troca no código das funções, elas quebrariam no Passo 4 mesmo com app e painel já migrados. |
| Segredos em arquivos versionados | Varredura: **nenhuma** `sb_secret_` nem JWT `service_role` versionados. Há 1 JWT `anon` (público) em `docs/auditoria/20260729.txt`, num comando de exemplo antigo. Não reescrevi histórico. |

## O que mudou

**Edge Functions** (`supabase/functions/`)
- Novo `_shared/chaves_supabase.ts`: `lerChaveSecreta()` e `lerChavePublicavel()` leem o dicionário novo e **caem na chave legada** se ele não existir ou vier malformado (nunca lançam, nunca logam o valor). É isso que permite o aceite da Parte 1: tudo funciona com as duas famílias de chave ativas.
- Usado em `search-food`, `calculate-recovery-mode`, `manage-professional-link` (chave secreta), `extract-metric-photo` (chave publicável) e `garmin-gateway` (chave secreta; **não deployada**, decisão de 17/set).
- Novo `_shared/chaves_supabase_test.ts` (6 testes).

**Painel web** (`web_painel/`)
- `src/core/supabase.ts` exporta `supabaseUrl`/`supabasePublishableKey` (nova variável `VITE_SUPABASE_PUBLISHABLE_KEY`, fallback `VITE_SUPABASE_ANON_KEY`). `UpdatePasswordPage.tsx` e `AnamneseProfissionalView.tsx` deixam de ler a variável por conta própria e importam de lá (removi dois blocos duplicados de validação).
- 6 scripts de `scripts/` passam a usar `scripts/lib/chaveSecretaSupabase.ts` (`SUPABASE_SECRET_KEY`, fallback `SUPABASE_SERVICE_ROLE_KEY`).
- `.env` agora **versionado**, só com valores públicos. `.env.example` e `.env.local.example` atualizados. `README.md` corrigido (dizia que o `.env` não é commitado).

**App Flutter** (`lib/`)
- `AppConfig.supabasePublishableKey` lê `--dart-define=SUPABASE_PUBLISHABLE_KEY`, com fallback para `SUPABASE_ANON_KEY` (o `config_local.json` atual continua funcionando). Identificador renomeado em 14 arquivos; tela de "configuração ausente" atualizada.
- Novo `config_local.example.json` (versionado).

**Scripts da raiz** (`scripts/*.ts`, Deno): 4 scripts preferem `SUPABASE_SECRET_KEY`/`SUPABASE_PUBLISHABLE_KEY`, com fallback legado.

**Documentação**: `.env.example` (raiz), `SETUP_GUIDE.md`, `QUICK_REFERENCE.md`, `web_painel/vite.config.ts` (comentário).

**Higiene de repositório**: `.gitignore` (raiz e `web_painel/`) — `web_painel/.env` versionado; `.env.local`, `.env` da raiz, `config.env` e `config_local.json` continuam ignorados.

**CI** (`.github/workflows/ci.yml` + `.github/scripts/verificar_segredos.sh`): 4 jobs — guarda de segredos, painel (lint + typecheck + build), Edge Functions (`deno check` + testes), Flutter (analyze + test). Sem deploy, sem secrets do GitHub.

## Decisões | motivo

1. **Fallback legado em todo lugar** — o aceite da Parte 1 exige funcionar com as duas famílias ativas e voltar trocando uma variável. Depois do Passo 4 o fallback vira código morto e pode ser removido.
2. **`.env` versionado com `VITE_SUPABASE_PUBLISHABLE_KEY=` vazia** — a chave só existe depois do Passo 1 (do fundador). A chave publicável é pública por desenho; o fundador a cola no arquivo e faz commit. A chave `anon` legada que estava no `.env` local foi **movida para `web_painel/.env.local`** (ignorado, prioridade maior no Vite) para o painel local não parar; backup do `.env` antigo guardado fora do repositório.
3. **CI com teto no número atual de dívida, não zero** — medi antes: lint do painel já falhava com 2 warnings antigos (`seed_taco_completa.ts`), Flutter tem 29 infos + 1 warning antigos. Ligar em zero faria o primeiro PR nascer vermelho; escondê-los seria pior. O teto impede crescimento, e o comentário no workflow diz como baixar.
4. **Fora do CI, de propósito**: `deno check` dos scripts da raiz (já tinha 1 erro de tipo antigo em `gerar_csv_medidas_pendentes.ts`).
5. **Garmin não tocado** — `VITE_GARMIN_DISPATCH_ENDPOINT` segue placeholder, por decisão explícita do fundador em 17/set.
6. **Guarda de segredos não bloqueia `anon`/`sb_publishable_`** (públicas por desenho); bloqueia `sb_secret_` e qualquer JWT com `role=service_role`.

## Verificação (tudo medido nesta máquina)

- Edge Functions: testes antigos intactos (7 + 132 + 3 + 8 + 16 passam) + 6 novos de `_shared`; `deno check` limpo.
- Painel: `npm run build` limpo; lint no teto de 2 warnings (os mesmos de antes); bundle novo sem `sb_secret_`/`service_role`.
- Flutter: **593 testes passam**; `flutter analyze` = 30 apontamentos, mesmos da linha de base (0 erros); comando exato do CI sai com código 0.
- Guarda de segredos: passa no repositório (23 s); **falha** (exit 1) com um JWT `service_role` e uma `sb_secret_` sintéticos, sem imprimir o valor.
- **Deploy** (`supabase functions deploy`): `search-food` v13→v14, `calculate-recovery-mode` v6→v7, `manage-professional-link` v7→v8, `extract-metric-photo` v50→v51. `verify_jwt` já era `true` nas quatro (igual ao padrão do redeploy — sem mudança de comportamento). `garmin-gateway` não deployada (nunca foi).
- **Smoke em produção** com o token `anon` público (passa o gateway, não é sessão): as 4 funções responderam com o próprio `401 "Sessão inválida ou expirada."`, ou seja, subiram, leram a chave do projeto e chegaram na autenticação (`500 Configuração do servidor incompleta` indicaria falha de chave).
- **Não verificado**: nada com as chaves `sb_` novas, porque o Passo 1 ainda não foi feito. A Parte 1 do aceite só se confirma depois dele.

## Desvios

- **Regra 22 (X-Request-Id + log de conclusão)** não aplicada nas 5 funções tocadas: nenhuma tinha isso, e adicionar seria reescrever o tratamento de resposta de 5 funções só para trocar a leitura de uma chave. Fica como item próprio.
- `analysis_options.yaml` tem uma alteração local sua (exclude de `build/android/ios`) que **não commitei** e não toquei; o CI usa a versão commitada, então a contagem de apontamentos lá pode diferir levemente.
- Nenhum pedido em HOLD implementado; nenhuma migration; nenhuma RPC/RLS alterada; zero mudança de regra de negócio.

## Problemas encontrados

- **Primeira execução do CI no GitHub falhou no Flutter (592 passam, 1 falha)** — `background_sync_manager_test.dart` ("agendarSincronizacaoDiaria registra… Wi-Fi e carregamento"). **Não é regressão desta tarefa**: no Linux, `Workmanager._ensurePlatformImplementation()` (workmanager 0.10.10) troca qualquer implementação de `WorkmanagerPlatform` por `WorkmanagerLinux` quando `Platform.isLinux`, descartando o fake que o teste injeta; no Windows o fake sobrevive. O meu único diff nesse arquivo é o renome de um identificador dentro de um callback. O job do Flutter passou a rodar em `windows-latest` (onde os 593 foram medidos) em vez de excluir o teste.
- `.env.example` com `/rest/v1/` (quebraria qualquer clone) e JWT `anon` embutido — corrigidos.
- Lint do painel já falhava na `main` (`--max-warnings 0` com 2 warnings) — dívida antiga, agora com teto no CI.
- Python não existe nesta máquina; um ajuste do guarda de segredos foi refeito com o editor.

## Riscos mapeados

1. **As Edge Functions passam a usar a chave nova sozinhas** assim que o Passo 1 for feito: a plataforma passa a injetar `SUPABASE_SECRET_KEYS` e o código prefere esse valor — sem novo deploy. Se uma `sb_secret_` se comportar diferente do esperado, o caminho de volta é reverter o código das funções (que volta a ler a legada, ainda ativa), não só trocar variável.
2. **Cloudflare**: o README do painel diz que as variáveis de produção ficam no Cloudflare. Se o painel for publicado por lá, a variável de lá tem prioridade sobre o `.env` do repositório — `VITE_SUPABASE_PUBLISHABLE_KEY` precisa ser igual nos dois lugares.
3. **R43 (prazo de terceiro)**: o Passo 4 só deve ser feito depois de testar tudo com as chaves novas e as legadas ainda ativas.
4. `docs/auditoria/20260729.txt` segue com um JWT `anon` — público, e inerte depois do Passo 4.

## Como o fundador testa

**Parte 1 — com as chaves legadas ainda ativas**
1. Dashboard → Settings → API Keys: criar a *publishable* e a *secret* (Passo 1; as legadas continuam funcionando).
2. Colar a `sb_publishable_…` em `web_painel/.env` (linha `VITE_SUPABASE_PUBLISHABLE_KEY=`) e em `config_local.json` (`SUPABASE_PUBLISHABLE_KEY`, veja `config_local.example.json`). Colar a `sb_secret_…` em `web_painel/.env.local` (`SUPABASE_SECRET_KEY`). Se usar Cloudflare, atualizar a variável lá.
3. App: login, leitura e escrita; foto do prato; Esteira. Painel: login e **Convidar Paciente**.
4. Abrir o PR e ver o CI verde.

**Parte 2 — depois do Passo 4 (desativar o par legado)**
5. Repetir o passo 3 e subir a partir de um clone limpo sem editar nenhum `.env` à mão.

## Performance

Sem impacto em runtime: a leitura de chave acontece uma vez por requisição, por `Deno.env.get` + um `JSON.parse` de poucos bytes. CI: 4 jobs em paralelo; o mais longo é o Flutter (~3 min de testes na medição local).

## Arquivos

Novos: `supabase/functions/_shared/chaves_supabase{,_test}.ts`, `web_painel/scripts/lib/chaveSecretaSupabase.ts`, `.github/workflows/ci.yml`, `.github/scripts/verificar_segredos.sh`, `config_local.example.json`, `web_painel/.env`.
Alterados: 5 Edge Functions, 3 telas/módulos do painel, 6 scripts do painel, 4 scripts da raiz, 14 arquivos de `lib/`, `.gitignore` (×2), `.env.example` (×2), `.env.local.example`, `README.md` do painel, `SETUP_GUIDE.md`, `QUICK_REFERENCE.md`, `vite.config.ts`.
