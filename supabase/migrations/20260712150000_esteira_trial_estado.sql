-- Etapa 1 (F21 — lógica real): persistência server-side do estado da
-- Esteira dos 14 Dias Free, que passa a viver na Edge Function
-- `calculate-recovery-mode` em vez de num secure storage no aparelho (ver
-- supabase/functions/calculate-recovery-mode/index.ts para o algoritmo).
--
-- Guarda só o estado BRUTO (a data-âncora e a janela de congelamento) — o
-- `diaAtual` que o app exibe é sempre derivado na hora pela Edge Function a
-- partir destes campos + a data corrente do servidor, nunca armazenado
-- pronto, para nunca ficar desatualizado.
--
-- RLS: só uma policy de SELECT. De propósito, NENHUMA policy de
-- INSERT/UPDATE/DELETE para o papel `authenticated` — se o cliente pudesse
-- escrever sua própria linha via REST direto, ele recriaria exatamente a
-- brecha que esta migration existe para fechar (o usuário manipulando o
-- próprio congelamento). Toda escrita acontece exclusivamente pela Edge
-- Function, que usa a service role (ignora RLS por padrão, mesma
-- justificativa de `garmin_conexoes`).
create table esteira_trial_estado (
  usuario_id_anonimo uuid primary key references auth.users (id) on delete cascade,
  ancora_efetiva date not null,
  recuperacao_ativa boolean not null default false,
  congelado_desde date,
  meta_movimento_cumprida boolean not null default false,
  missoes_exames_concluidas smallint[] not null default '{}',
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table esteira_trial_estado enable row level security;

create policy "esteira_trial_estado_select_own"
  on esteira_trial_estado for select
  using (auth.uid() = usuario_id_anonimo);
