-- Onda 1.5: Reestruturação de colunas fixas.
-- Substitui o padrão flexível de metricas_saude (dados_jsonb genérico) por
-- 5 tabelas otimizadas com colunas fixas e tipadas, uma por domínio clínico,
-- incluindo a "Caixa Preta" de anomalias de saúde detectadas em primeiro
-- plano pelo app (HealthSyncService).

-- ============================================================================
-- 1. metricas_saude_diarias
-- Um registro por usuário/dia, colunas fixas para cada parâmetro
-- biológico/clínico rastreado (wearable + captura por câmera).
-- ============================================================================
create table metricas_saude_diarias (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  data_referencia date not null,
  passos int,
  distancia_metros numeric(9, 2),
  fc_repouso int,
  hrv_medio numeric(6, 2),
  calorias_ativas numeric(8, 2),
  minutos_sono int,
  peso_kg numeric(5, 2),
  percentual_gordura numeric(5, 2),
  pressao_sistolica int,
  pressao_diastolica int,
  glicose_jejum numeric(6, 2),
  saturacao_oxigenio numeric(5, 2),
  temperatura_corporal numeric(4, 2),
  origem text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id_anonimo, data_referencia)
);

create index idx_metricas_saude_diarias_usuario_data
  on metricas_saude_diarias (usuario_id_anonimo, data_referencia desc);

alter table metricas_saude_diarias enable row level security;

create policy "metricas_saude_diarias_select_own"
  on metricas_saude_diarias for select
  using (auth.uid() = usuario_id_anonimo);

create policy "metricas_saude_diarias_insert_own"
  on metricas_saude_diarias for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "metricas_saude_diarias_update_own"
  on metricas_saude_diarias for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 2. eventos_anomalias_saude ("Caixa Preta")
-- Log estruturado, append-only, de leituras fora da faixa de referência
-- detectadas em primeiro plano pelo HealthSyncService (ex.: pico de FC fora
-- de treino, glicose/pressão críticas). Sem policy de update/delete: uma vez
-- gravado, o evento é imutável.
-- ============================================================================
create table eventos_anomalias_saude (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  tipo_anomalia text not null,
  parametro text not null,
  valor_detectado numeric(8, 2) not null,
  valor_limite_min numeric(8, 2),
  valor_limite_max numeric(8, 2),
  em_treino boolean not null default false,
  severidade text not null default 'atencao',
  origem text,
  detectado_em timestamptz not null default now()
);

create index idx_eventos_anomalias_saude_usuario_data
  on eventos_anomalias_saude (usuario_id_anonimo, detectado_em desc);

alter table eventos_anomalias_saude enable row level security;

create policy "eventos_anomalias_saude_select_own"
  on eventos_anomalias_saude for select
  using (auth.uid() = usuario_id_anonimo);

create policy "eventos_anomalias_saude_insert_own"
  on eventos_anomalias_saude for insert
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 3. diario_alimentar_diario
-- ============================================================================
create table diario_alimentar_diario (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  data_refeicao date not null,
  tipo_refeicao text not null,
  descricao text,
  calorias numeric(7, 2),
  proteinas_g numeric(6, 2),
  carboidratos_g numeric(6, 2),
  gorduras_g numeric(6, 2),
  registrado_em timestamptz not null default now()
);

create index idx_diario_alimentar_diario_usuario_data
  on diario_alimentar_diario (usuario_id_anonimo, data_refeicao desc);

alter table diario_alimentar_diario enable row level security;

create policy "diario_alimentar_diario_select_own"
  on diario_alimentar_diario for select
  using (auth.uid() = usuario_id_anonimo);

create policy "diario_alimentar_diario_insert_own"
  on diario_alimentar_diario for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "diario_alimentar_diario_update_own"
  on diario_alimentar_diario for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 4. resultados_exames
-- ============================================================================
create table resultados_exames (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  tipo_exame text not null,
  valor_resultado numeric(10, 3),
  unidade_medida text,
  valor_referencia_min numeric(10, 3),
  valor_referencia_max numeric(10, 3),
  laboratorio text,
  data_exame date not null,
  observacoes text,
  criado_em timestamptz not null default now()
);

create index idx_resultados_exames_usuario_data
  on resultados_exames (usuario_id_anonimo, data_exame desc);

alter table resultados_exames enable row level security;

create policy "resultados_exames_select_own"
  on resultados_exames for select
  using (auth.uid() = usuario_id_anonimo);

create policy "resultados_exames_insert_own"
  on resultados_exames for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "resultados_exames_update_own"
  on resultados_exames for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);

-- ============================================================================
-- 5. eventos_treino
-- ============================================================================
create table eventos_treino (
  id bigserial primary key,
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  tipo_treino text not null,
  data_inicio timestamptz not null,
  data_fim timestamptz,
  duracao_minutos int,
  calorias_queimadas numeric(7, 2),
  fc_media int,
  fc_maxima int,
  distancia_metros numeric(9, 2),
  origem text,
  criado_em timestamptz not null default now()
);

create index idx_eventos_treino_usuario_data
  on eventos_treino (usuario_id_anonimo, data_inicio desc);

alter table eventos_treino enable row level security;

create policy "eventos_treino_select_own"
  on eventos_treino for select
  using (auth.uid() = usuario_id_anonimo);

create policy "eventos_treino_insert_own"
  on eventos_treino for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "eventos_treino_update_own"
  on eventos_treino for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);
