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

### Deploy em hospedagem gratuita (SPA fallback)

- **Netlify / Cloudflare Pages**: leem `public/_redirects` automaticamente
  (Vite copia esse arquivo para a raiz de `dist/` no build) — mesmo
  arquivo, mesmo formato, cobre os dois hosts.
- **Vercel**: lê `vercel.json` na raiz do projeto (`web_painel/vercel.json`,
  não dentro de `dist/` — convenção diferente da dos outros dois hosts).

Sem um desses, atualizar a página numa rota do React Router (ex.:
`/pacientes/<uuid>`) devolve 404 do servidor de hospedagem em vez de
deixar o React Router assumir a rota no cliente.

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
