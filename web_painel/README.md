# Painel Web Profissional (ONDA 3 — B2B)

Fundação do painel React + TypeScript + Vite + Tailwind para Médicos,
Nutricionistas e Auditoria de Seguradoras — Fase 2 do PRD Mestre.

## Setup

Este ambiente de desenvolvimento não tem Node.js instalado, então nada
aqui foi rodado por `npm install`/`vite build`/`tsc` — revise com atenção
antes do primeiro `npm install` real.

```bash
cd web_painel
npm install
cp .env.example .env   # preencha com o mesmo projeto Supabase do app mobile
npm run dev
```

## Build de produção

```bash
npm run build    # tsc -b (gate de tipos) && vite build — bloqueia o build se houver erro de tipo
npm run preview  # serve o build de dist/ localmente, para testar antes de publicar
```

`vite.config.ts` já separa `react`/`react-dom`/`react-router-dom`,
`@supabase/supabase-js` e `recharts` em chunks de vendor próprios
(`build.rollupOptions.output.manualChunks`) e remove todo comentário do JS
minificado (`esbuild.legalComments: 'none'`) — ver os comentários no
próprio arquivo para o raciocínio de cache/Custo Zero por trás disso.

## Deploy

O painel roda em **Cloudflare Workers** (assets estáticos), configurado em
`web_painel/wrangler.jsonc`. O deploy é automático a cada push na `main`,
via integração Git do Cloudflare — não é feito manualmente com
`wrangler deploy` no dia a dia.

- **Root directory**: `web_painel` (o projeto vive numa subpasta do
  monorepo, não na raiz do repositório).
- **Build command**: `npm install && npm run build`.
- **Output**: `dist/` — servido como assets estáticos; o fallback de SPA
  (rotas do React Router como `/pacientes/<uuid>` não devolverem 404) é
  feito por `wrangler.jsonc`'s `assets.not_found_handling:
  "single-page-application"`, não por um arquivo `_redirects` separado
  (Cloudflare Workers assets já cobre isso nativamente — um `_redirects`
  com `/* /index.html 200` ao lado disso causa loop infinito de redirect).
- **Variáveis de ambiente** (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`):
  configuradas no painel do Cloudflare (Settings → Variables do projeto),
  nunca commitadas — `.env` fica só na máquina local, coberto pelo
  `.gitignore`.

## Antes de usar em produção

1. **Aplique as migrations** `supabase/migrations/20260709180000_painel_web_profissional_rls.sql`
   e `supabase/migrations/20260709190000_garmin_conexoes.sql` — sem elas,
   nenhuma tela consegue ler dado nenhum de paciente (RLS nega tudo por
   padrão) e o gateway Garmin não tem onde buscar o token do aluno.
2. **Crie ao menos uma conta profissional**: um `perfis_usuarios` com
   `eh_profissional = true` e `tipo_profissional` em
   `('Medico', 'Nutricionista', 'Fisioterapeuta', 'Personal_Trainer',
   'Auditoria_Seguradora')`. Não há tela de auto-cadastro de profissional
   neste painel — é um onboarding administrativo, fora de escopo aqui.
3. **A Edge Function `garmin-gateway`** (`supabase/functions/garmin-gateway/`,
   endpoint em `VITE_GARMIN_DISPATCH_ENDPOINT`) já está implementada e
   testada (`deno test --allow-env`) — falta só fazer o deploy dela
   (`supabase functions deploy garmin-gateway`) e configurar
   `GARMIN_CONSUMER_KEY`/`GARMIN_CONSUMER_SECRET` como secrets do projeto.
   A **Edge Function `ingest-b2b-analytics`** referenciada pelo app mobile
   continua sem implementação server-side — só o contrato client-side
   existe (`lib/features/intelligence/data/repositories/b2b_sync_repository.dart`).
4. **Auditoria de Seguradora hoje vê uma lista sempre vazia.** `PatientList.tsx`
   só resolve pacientes via `planejamento_clinico` (vínculo de prescrição
   individual), que não é o modelo de autorização correto para um auditor
   de sinistros (que precisa enxergar um pool de apólices, não uma relação
   de cuidado 1:1). Falta uma tabela `apolices_seguradora` (ou
   equivalente) + a policy de RLS correspondente antes desse papel virar
   funcional de verdade — deliberadamente deixado "fail closed" em vez de
   uma policy ampla demais. Ver o comentário no topo de
   `src/features/patients/components/PatientList.tsx`.
