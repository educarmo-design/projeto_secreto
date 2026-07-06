-- Universal Database Core: initial schema for healthcare / fitness tracking platform
-- Covers user profiles, health metrics, menstrual cycle tracking, gamification, and clinical planning.

-- ============================================================================
-- 1. ENUM: healthcare professional roles
-- ============================================================================
create type tipo_profissional_saude as enum (
  'Medico',
  'Nutricionista',
  'Fisioterapeuta',
  'Personal_Trainer'
);

-- ============================================================================
-- 2. perfis_usuarios
-- ============================================================================
create table perfis_usuarios (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text,
  email text,
  telefone text,
  data_nascimento date,
  sexo_biologico text,
  eh_profissional boolean not null default false,
  tipo_profissional tipo_profissional_saude,
  cep text,
  logradouro text,
  bairro text,
  cidade text,
  estado text,
  criado_em timestamptz not null default now()
);

alter table perfis_usuarios enable row level security;

create policy "perfis_usuarios_select_own"
  on perfis_usuarios for select
  using (auth.uid() = id);

create policy "perfis_usuarios_insert_own"
  on perfis_usuarios for insert
  with check (auth.uid() = id);

create policy "perfis_usuarios_update_own"
  on perfis_usuarios for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ============================================================================
-- 3. metricas_saude
-- ============================================================================
create table metricas_saude (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  tipo_metrica text not null,
  origem text,
  dados_jsonb jsonb,
  participa_gamificacao boolean not null default true,
  data_registro timestamptz not null default now()
);

create index idx_metricas_saude_usuario_tipo_data
  on metricas_saude (usuario_id_anonimo, tipo_metrica, data_registro desc);

alter table metricas_saude enable row level security;

create policy "metricas_saude_select_own"
  on metricas_saude for select
  using (auth.uid() = usuario_id_anonimo);

create policy "metricas_saude_insert_own"
  on metricas_saude for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "metricas_saude_update_own"
  on metricas_saude for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 4. ciclo_menstrual
-- ============================================================================
create table ciclo_menstrual (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  data_inicio_ciclo date,
  duracao_ciclo_dias int not null default 28,
  sintomas_jsonb jsonb,
  registrado_em timestamptz not null default now()
);

alter table ciclo_menstrual enable row level security;

create policy "ciclo_menstrual_select_own"
  on ciclo_menstrual for select
  using (auth.uid() = usuario_id_anonimo);

create policy "ciclo_menstrual_insert_own"
  on ciclo_menstrual for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "ciclo_menstrual_update_own"
  on ciclo_menstrual for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 5. progresso_gamificacao
-- ============================================================================
create table progresso_gamificacao (
  usuario_id_anonimo uuid primary key references auth.users (id) on delete cascade,
  ofensiva_atual int not null default 0,
  pontuacao_ranking int not null default 0,
  ultima_atividade_data date,
  status_usuario text not null default 'ativo',
  detalhes_recuperacao_jsonb jsonb
);

alter table progresso_gamificacao enable row level security;

create policy "progresso_gamificacao_select_own"
  on progresso_gamificacao for select
  using (auth.uid() = usuario_id_anonimo);

create policy "progresso_gamificacao_insert_own"
  on progresso_gamificacao for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "progresso_gamificacao_update_own"
  on progresso_gamificacao for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 6. planejamento_clinico
-- ============================================================================
create table planejamento_clinico (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references auth.users (id) on delete cascade,
  paciente_id_anonimo uuid not null references auth.users (id) on delete cascade,
  tipo_plano text,
  estrutura_plano_jsonb jsonb,
  sincronizado_garmin boolean not null default false,
  data_limite date,
  criado_em timestamptz not null default now()
);

alter table planejamento_clinico enable row level security;

create policy "planejamento_clinico_select_participants"
  on planejamento_clinico for select
  using (auth.uid() = profissional_id or auth.uid() = paciente_id_anonimo);

create policy "planejamento_clinico_insert_professional"
  on planejamento_clinico for insert
  with check (auth.uid() = profissional_id);

create policy "planejamento_clinico_update_participants"
  on planejamento_clinico for update
  using (auth.uid() = profissional_id or auth.uid() = paciente_id_anonimo)
  with check (auth.uid() = profissional_id or auth.uid() = paciente_id_anonimo);
