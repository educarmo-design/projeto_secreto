# RELATÓRIO 20260917_0003 — Fix: endpoint placeholder quebrava "Convidar Paciente" em produção

**Data:** 2026-09-17
**Branch:** `fix/painel-web-endpoint-convite-paciente` (a partir de `main`)
**Persona:** Especialista em React/Web e Backend (Mestre v8.0)

## Contexto

Achado durante a verificação pedida pelo fundador ("verificar se o painel web também está funcionando"), depois dos merges de `feat/web-anamnese-profissional` e `feat/app-anamnese-v1-ux`. Não relacionado a nenhuma das duas tarefas — bug pré-existente, achado por inspeção do bundle de produção.

## Achado

`web_painel/.env` (committado no repo) tinha dois endpoints de Edge Function como placeholder literal (`https://your-project.supabase.co/...`):

- `VITE_MANAGE_PROFESSIONAL_LINK_ENDPOINT` — a função `manage-professional-link` **está deployada e ACTIVE em produção** (`supabase functions list`, v7); só o front apontava pro host errado. O botão "Convidar Paciente" (`InvitePatientModal.tsx` → `vinculosApi.ts`) estava, portanto, **quebrado em produção** (a chamada nunca resolveria DNS).
- `VITE_GARMIN_DISPATCH_ENDPOINT` — mesmo placeholder, mas a função `garmin-gateway` **nem está deployada** (existe só como código-fonte local, ausente de `supabase functions list`) e depende de `GARMIN_CONSUMER_KEY`/`GARMIN_CONSUMER_SECRET` (credenciais reais da Garmin Developer Program) que não estão configuradas — parece uma integração intencionalmente pausada, não um esquecimento simples.

**Decisão do fundador**: corrigir o 1º agora (fix trivial e seguro); só registrar o 2º como gap conhecido (não dá pra corrigir sem as credenciais reais da Garmin).

## Correção

**Achado no caminho**: `web_painel/.env` está no `.gitignore` (`.env` e `web_painel/.env`, linhas 1/25) — **nunca foi versionado**, apesar do próprio `.env.example` documentar explicitamente que "`.env` é o arquivo PÚBLICO (versionado, sem segredo nenhum)" (comentário de R15/RELATÓRIO 20260901_0001). Ou seja, o `.gitignore` atual contradiz a intenção documentada do próprio projeto. Isso está fora do escopo desta correção (decisão de manter/remover a entrada do `.gitignore` não foi pedida) — só registrado aqui, não alterado.

Na prática, isso significa: a correção em `web_painel/.env` (trocar `your-project.supabase.co` por `xtipphglpqqrjguxcajn.supabase.co` na linha de `VITE_MANAGE_PROFESSIONAL_LINK_ENDPOINT`) foi aplicada **diretamente no arquivo local desta máquina** (o mesmo ambiente onde o Painel Web roda hoje — não há pipeline de deploy separado, ver achado da tarefa anterior) e já está em efeito, mas **não aparece no diff deste commit** (não há nada pra versionar ali). O que ESTE commit versiona é `web_painel/.env.example` (o template rastreado) — mesma correção, pra não perpetuar o bug em qualquer novo setup que copie do exemplo. `VITE_GARMIN_DISPATCH_ENDPOINT` **não foi tocado** em nenhum dos dois arquivos — decisão explícita do fundador.

## Verificação

- `npm run build` limpo (bundle novo gerado com a URL correta, confirmado via grep no bundle final: `xtipphglpqqrjguxcajn.supabase.co/functions/v1/manage-professional-link` presente).
- Chamada HTTP direta ao endpoint real (`POST .../manage-professional-link`, sem header de autorização): devolveu `401 UNAUTHORIZED_NO_AUTH_HEADER` — confirma que o host resolve e a função responde de verdade (diferente do placeholder, que falharia com erro de DNS antes mesmo de chegar num servidor). O botão real usa uma sessão autenticada, então o fluxo completo (convite de paciente) passa a funcionar.
- `npm run lint`: só os 2 warnings pré-existentes de `scripts/seed_taco_completa.ts` (não tocado).

## Entregável

- `web_painel/.env` corrigido localmente (não versionado — ver achado do `.gitignore` acima).
- `web_painel/.env.example` corrigido (1 linha, versionado).
- Branch `fix/painel-web-endpoint-convite-paciente`, a partir de `main`, aguardando autorização explícita do fundador para merge (Regra 18).
