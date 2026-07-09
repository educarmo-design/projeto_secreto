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

## Antes de usar em produção

1. **Aplique a migration** `supabase/migrations/20260709180000_painel_web_profissional_rls.sql`
   — sem ela, nenhuma tela consegue ler dado nenhum de paciente (RLS nega
   tudo por padrão).
2. **Crie ao menos uma conta profissional**: um `perfis_usuarios` com
   `eh_profissional = true` e `tipo_profissional` em
   `('Medico', 'Nutricionista', 'Fisioterapeuta', 'Personal_Trainer',
   'Auditoria_Seguradora')`. Não há tela de auto-cadastro de profissional
   neste painel — é um onboarding administrativo, fora de escopo aqui.
3. **A Edge Function `dispatch-garmin-training-plan`** (endpoint em
   `VITE_GARMIN_DISPATCH_ENDPOINT`) e a **Edge Function
   `ingest-b2b-analytics`** referenciada pelo app mobile continuam sem
   implementação server-side neste repositório — só o contrato/assinatura
   client-side existe. Ver `src/features/prescriptions/services/garminApi.ts`.
4. **Auditoria de Seguradora hoje vê uma lista sempre vazia.** `PatientList.tsx`
   só resolve pacientes via `planejamento_clinico` (vínculo de prescrição
   individual), que não é o modelo de autorização correto para um auditor
   de sinistros (que precisa enxergar um pool de apólices, não uma relação
   de cuidado 1:1). Falta uma tabela `apolices_seguradora` (ou
   equivalente) + a policy de RLS correspondente antes desse papel virar
   funcional de verdade — deliberadamente deixado "fail closed" em vez de
   uma policy ampla demais. Ver o comentário no topo de
   `src/features/patients/components/PatientList.tsx`.
