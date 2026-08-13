-- Decisão do fundador (RELATÓRIO 20260811_0002/spike de Nutrição/Atividades):
-- calorias granulares na tabela diária + estrutura própria de Treinos/Rotas,
-- com FC isolada por intervalo de tempo do treino. Sem Motor Clínico: só
-- grava valores absolutos, nenhuma lógica de anomalia/evento nova.

-- =============================================================================
-- 1) Calorias granulares em metricas_saude_diarias
-- =============================================================================
-- calorias_ativas já existe desde a Onda 1.5 (20260708174650). Faltam basais
-- e o total — HealthSyncService._mesclarPorDia soma ativas+basais em
-- calorias_totais só quando pelo menos uma das duas está presente naquele
-- dia (nunca grava 0 para um dia sem nenhum dado de caloria).
alter table metricas_saude_diarias
  add column if not exists calorias_basais numeric(8, 2),
  add column if not exists calorias_totais numeric(8, 2);

comment on column metricas_saude_diarias.calorias_basais is
  'HealthDataType.BASAL_ENERGY_BURNED (metabolismo basal/repouso) — maior fonte do dia, mesmo tratamento anti-double-counting de calorias_ativas. HealthSyncService._mesclarPorDia.';
comment on column metricas_saude_diarias.calorias_totais is
  'calorias_ativas + calorias_basais (soma do que estiver disponível naquele dia — não é um HealthDataType lido à parte; RELATÓRIO 20260810_0007 mapeou TOTAL_CALORIES_BURNED como não implementado de fato no lado iOS do pacote health, apesar de aparecer como "suportado" — somar ativas+basais no Dart é portável nas duas plataformas).';

-- =============================================================================
-- 2) Dicionário de modalidades de atividade física
-- =============================================================================
-- nome_codigo espelha HealthWorkoutActivityType.name (pacote `health`) —
-- FK direta de atividades_fisicas_treinos.tipo_atividade_codigo, sem camada
-- de tradução no meio. Só os tipos da seção "// Both" do enum (RELATÓRIO
-- 20260810_0007, Spike de Nutrição/Atividades) — comuns a Android E iOS,
-- pedido explícito do fundador ("modalidades comuns entre iOS e Android").
create table if not exists tipos_atividades_fisicas (
  id smallint generated always as identity primary key,
  nome_codigo text not null unique,
  nome_exibicao text not null
);

comment on table tipos_atividades_fisicas is
  'Dicionário de modalidades de treino comuns a Android e iOS (seção "Both" de HealthWorkoutActivityType no pacote health) — RELATÓRIO 20260810_0007/20260811_0002.';
comment on column tipos_atividades_fisicas.nome_codigo is
  'Espelha HealthWorkoutActivityType.name exatamente (ex.: "RUNNING") — é o valor que HealthSyncService grava em atividades_fisicas_treinos.tipo_atividade_codigo, sem tradução no meio.';

insert into tipos_atividades_fisicas (nome_codigo, nome_exibicao) values
  ('AMERICAN_FOOTBALL', 'Futebol Americano'),
  ('ARCHERY', 'Tiro com Arco'),
  ('AUSTRALIAN_FOOTBALL', 'Futebol Australiano'),
  ('BADMINTON', 'Badminton'),
  ('BASEBALL', 'Beisebol'),
  ('BASKETBALL', 'Basquete'),
  ('BIKING', 'Ciclismo'),
  ('BOXING', 'Boxe'),
  ('CARDIO_DANCE', 'Dança Cardio'),
  ('CRICKET', 'Críquete'),
  ('CROSS_COUNTRY_SKIING', 'Esqui Cross-Country'),
  ('CURLING', 'Curling'),
  ('DOWNHILL_SKIING', 'Esqui Alpino'),
  ('ELLIPTICAL', 'Elíptico'),
  ('FENCING', 'Esgrima'),
  ('GOLF', 'Golfe'),
  ('GYMNASTICS', 'Ginástica'),
  ('HANDBALL', 'Handebol'),
  ('HIGH_INTENSITY_INTERVAL_TRAINING', 'Treino Intervalado de Alta Intensidade (HIIT)'),
  ('HIKING', 'Trilha'),
  ('HOCKEY', 'Hóquei'),
  ('JUMP_ROPE', 'Pular Corda'),
  ('KICKBOXING', 'Kickboxing'),
  ('MARTIAL_ARTS', 'Artes Marciais'),
  ('PILATES', 'Pilates'),
  ('RACQUETBALL', 'Raquetebol'),
  ('ROWING', 'Remo'),
  ('RUGBY', 'Rugby'),
  ('RUNNING', 'Corrida'),
  ('SAILING', 'Vela'),
  ('SKATING', 'Patinação'),
  ('SNOWBOARDING', 'Snowboard'),
  ('SOCCER', 'Futebol'),
  ('SOFTBALL', 'Softbol'),
  ('SQUASH', 'Squash'),
  ('STAIR_CLIMBING', 'Subida de Escadas'),
  ('SWIMMING', 'Natação'),
  ('TABLE_TENNIS', 'Tênis de Mesa'),
  ('TENNIS', 'Tênis'),
  ('VOLLEYBALL', 'Vôlei'),
  ('WALKING', 'Caminhada'),
  ('WATER_POLO', 'Polo Aquático'),
  ('YOGA', 'Yoga')
on conflict (nome_codigo) do nothing;

-- Dicionário é catálogo público de leitura — todo usuário autenticado pode
-- ler, ninguém escreve pelo app (populado só por migration).
alter table tipos_atividades_fisicas enable row level security;

create policy "tipos_atividades_fisicas_select_all"
  on tipos_atividades_fisicas for select
  to authenticated
  using (true);

grant select on tipos_atividades_fisicas to authenticated;

-- =============================================================================
-- 3) Treinos
-- =============================================================================
-- id uuid (não bigserial, ao contrário do resto do schema): precisa ser
-- gerado ANTES do insert pra virar FK de atividades_fisicas_rotas sem uma
-- segunda ida ao banco só pra descobrir o id gerado.
create table if not exists atividades_fisicas_treinos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users (id) on delete cascade,
  tipo_atividade_codigo text not null references tipos_atividades_fisicas (nome_codigo),
  inicio_atividade timestamptz not null,
  fim_atividade timestamptz not null,
  energia_queimada_kcal numeric(8, 2),
  distancia_metros numeric(9, 2),
  passos_totais int,
  fc_media int,
  fc_maxima int,
  fc_minima int,
  origem text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  unique (usuario_id, inicio_atividade)
);

comment on table atividades_fisicas_treinos is
  'Um treino por HealthDataType.WORKOUT lido do Health Connect/HealthKit. RELATÓRIO 20260811_0002.';
comment on column atividades_fisicas_treinos.tipo_atividade_codigo is
  'FK para tipos_atividades_fisicas.nome_codigo — espelha WorkoutHealthValue.workoutActivityType.name.';
comment on column atividades_fisicas_treinos.fc_media is
  'Média/máxima/mínima calculadas SÓ com as leituras de HEART_RATE cujo timestamp cai dentro de [inicio_atividade, fim_atividade] deste treino — não é a FC do dia inteiro. HealthSyncService._processarTreinos. Valores absolutos, sem lógica de anomalia (restrição regulatória F02, ver RELATÓRIO 20260810_0004).';
comment on constraint atividades_fisicas_treinos_usuario_id_inicio_atividade_key on atividades_fisicas_treinos is
  'Idempotência: reprocessar os mesmos 30 dias não duplica o mesmo treino — upsert com onConflict nessa chave.';

create index if not exists idx_atividades_fisicas_treinos_usuario_data
  on atividades_fisicas_treinos (usuario_id, inicio_atividade desc);

alter table atividades_fisicas_treinos enable row level security;

create policy "atividades_fisicas_treinos_select_own"
  on atividades_fisicas_treinos for select
  using (auth.uid() = usuario_id);

create policy "atividades_fisicas_treinos_insert_own"
  on atividades_fisicas_treinos for insert
  with check (auth.uid() = usuario_id);

create policy "atividades_fisicas_treinos_update_own"
  on atividades_fisicas_treinos for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

grant select, insert, update on atividades_fisicas_treinos to authenticated;

-- =============================================================================
-- 4) Rotas GPS dos treinos
-- =============================================================================
-- Só os campos comuns às duas plataformas (pedido explícito do fundador) —
-- speed/course/speedAccuracy/courseAccuracy são exclusivos de iOS
-- (RELATÓRIO 20260810_0007) e ficam de fora de propósito.
create table if not exists atividades_fisicas_rotas (
  id bigserial primary key,
  treino_id uuid not null references atividades_fisicas_treinos (id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  timestamp_ponto timestamptz not null,
  altitude double precision,
  precisao double precision
);

comment on table atividades_fisicas_rotas is
  'Pontos de rota GPS de um treino (HealthDataType.WORKOUT_ROUTE) — só campos comuns a Android/iOS. Sem RLS própria por usuario_id: a posse é sempre a do treino pai (ver policies abaixo). RELATÓRIO 20260811_0002.';
comment on column atividades_fisicas_rotas.precisao is
  'horizontalAccuracy do ponto GPS (metros) — verticalAccuracy não é gravado (não é um campo "comum" pedido pelo fundador).';

create index if not exists idx_atividades_fisicas_rotas_treino
  on atividades_fisicas_rotas (treino_id);

alter table atividades_fisicas_rotas enable row level security;

-- RLS via join ao treino pai (nenhuma coluna usuario_id em rotas, por
-- desenho — só as colunas pedidas pelo fundador) — mesmo princípio de
-- perfis_pacientes_vinculados (20260713140000): a autorização mora na
-- relação com a tabela dona, não numa coluna redundante aqui.
create policy "atividades_fisicas_rotas_select_own"
  on atividades_fisicas_rotas for select
  using (exists (
    select 1 from atividades_fisicas_treinos t
    where t.id = atividades_fisicas_rotas.treino_id
      and t.usuario_id = auth.uid()
  ));

create policy "atividades_fisicas_rotas_insert_own"
  on atividades_fisicas_rotas for insert
  with check (exists (
    select 1 from atividades_fisicas_treinos t
    where t.id = atividades_fisicas_rotas.treino_id
      and t.usuario_id = auth.uid()
  ));

create policy "atividades_fisicas_rotas_delete_own"
  on atividades_fisicas_rotas for delete
  using (exists (
    select 1 from atividades_fisicas_treinos t
    where t.id = atividades_fisicas_rotas.treino_id
      and t.usuario_id = auth.uid()
  ));

grant select, insert, delete on atividades_fisicas_rotas to authenticated;

-- ============================================================================
-- GRANT (Parte 0.10): metricas_saude_diarias já concede select/insert/update
-- ao dono da linha via RLS/grant existentes — nenhuma alteração necessária
-- pelas 2 colunas novas (GRANT é por tabela, não por coluna).
