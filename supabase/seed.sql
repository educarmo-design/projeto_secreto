-- ============================================================================
-- Seed de demonstração — Painel B2B (DEV/LOCAL apenas)
-- ============================================================================
-- Popula 10 pacientes fictícios vinculados ao profissional cadastrado com o
-- e-mail educarmo@gmail.com, com 6 meses de métricas diárias, para validar a
-- Sidebar/DashboardLayout, "Meus Pacientes/Alunos" e os gráficos de
-- `PatientDetails` (recharts, já lê `metricas_saude_diarias`).
--
-- Este script é para `supabase start`/`supabase db reset` local (roda com o
-- role `postgres`, que ignora RLS) — não é pensado para o projeto Supabase
-- hospedado referenciado em `web_painel/.env.example`. Insere direto em
-- `auth.users`, um atalho padrão de seed local que contorna a API do GoTrue;
-- nunca faça isso contra um projeto em produção.
--
-- Decisão de modelagem — por que os pacientes NÃO têm `nome`/`email` em texto
-- plano em `perfis_usuarios`: o resto do schema (ver
-- `20260713190000_perfis_profissionais_vinculados.sql` e
-- `20260713210000_resolver_usuario_id_por_email.sql`) documenta, repetidas
-- vezes, que essas colunas saem cifradas AES-256-GCM no cliente antes do
-- insert real (`CryptoStorageService`) — nenhuma linha legítima de paciente
-- tem texto legível ali. Gravar nomes/e-mails realistas em texto plano nessas
-- colunas simularia um formato de dado que NUNCA existe em produção e que a
-- própria RLS/arquitetura foi desenhada para impedir. Em vez disso, os nomes
-- fictícios abaixo vão para `nickname` — o único campo de identificação
-- textual que é plaintext por desenho (é o handle público de gamificação,
-- mesmo campo que `PatientList`/`PatientDetails` já exibem) — e o "e-mail
-- realista" pedido vira o e-mail de login em `auth.users` (que é sempre
-- plaintext, gerido pelo GoTrue). `nome`/`email`/`telefone` ficam NULL, como
-- ficariam de fato para qualquer paciente cujo dispositivo cifrou esses
-- campos.
--
-- Idempotente: IDs fixos (literais) + `on conflict ... do update/nothing` em
-- toda tabela com constraint única, e um `delete` prévio, tagueado por
-- `tipo_plano = 'seed_demo_baseline'`, antes do insert em
-- `planejamento_clinico` (que não tem constraint única própria). Rodar este
-- arquivo várias vezes nunca duplica linhas nem falha.
--
-- Nota de implementação: cada statement abaixo repete a mesma CTE
-- `seed_pacientes`/`seed_ctx` (em vez de uma tabela temporária criada uma vez
-- no topo) de propósito — `supabase db reset`/`db start` envia este arquivo
-- em pipeline/batch, e uma tabela `temporary` criada num statement não é
-- visível de forma confiável a um statement seguinte no mesmo batch. CTEs
-- ficam contidas dentro de um único statement, então não sofrem esse
-- problema.
--
-- PatientList.tsx hoje lista pacientes a partir de `planejamento_clinico`
-- (não de `vinculos_profissional_paciente` diretamente — ver o comentário
-- daquele componente), então este seed grava nas DUAS tabelas: o vínculo
-- "oficial" (unidade de faturamento, F.2) e uma prescrição-base mínima, só
-- para que os pacientes fiquem visíveis na tela sem precisar alterar código
-- de produção.

create extension if not exists pgcrypto;

-- ============================================================================
-- 0. Aviso se a conta do profissional ainda não existe.
-- ============================================================================
do $$
declare
  v_profissional_id uuid;
begin
  select id into v_profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1;
  if v_profissional_id is null then
    raise notice 'Seed: nenhuma conta encontrada para educarmo@gmail.com em auth.users. Crie a conta (Solicitar Acesso no painel) e aprove-a antes de rodar o seed — todo insert abaixo depende dessa conta e vira no-op sem ela.';
  end if;
end $$;

-- ============================================================================
-- 1. auth.users — necessário porque `perfis_usuarios`/`vinculos_*` referenciam
--    `auth.users(id)` via FK. Senha fixa só para permitir login manual do
--    dev caso queira inspecionar a conta; nunca use isto fora de local/dev.
-- ============================================================================
with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id, idx, email_auth, nome_display, data_nascimento, sexo_biologico, geo_ranking_id, peso_base_kg) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid, 1,  'ana.paula.ferreira@pacientes.seed.dev',     'Ana Paula Ferreira',     '1988-03-14'::date, 'feminino',  'SP', 68.4),
    ('a1b2c3d4-0000-4000-8000-000000000002', 2,  'bruno.henrique.costa@pacientes.seed.dev',   'Bruno Henrique Costa',   '1975-11-02', 'masculino', 'RJ', 84.2),
    ('a1b2c3d4-0000-4000-8000-000000000003', 3,  'carla.souza.lima@pacientes.seed.dev',       'Carla Souza Lima',       '1992-07-21', 'feminino',  'MG', 61.9),
    ('a1b2c3d4-0000-4000-8000-000000000004', 4,  'diego.almeida.santos@pacientes.seed.dev',   'Diego Almeida Santos',   '1980-01-30', 'masculino', 'RS', 91.5),
    ('a1b2c3d4-0000-4000-8000-000000000005', 5,  'elisa.martins.rocha@pacientes.seed.dev',    'Elisa Martins Rocha',    '1998-09-09', 'feminino',  'PR', 58.7),
    ('a1b2c3d4-0000-4000-8000-000000000006', 6,  'felipe.oliveira.dias@pacientes.seed.dev',   'Felipe Oliveira Dias',   '1968-05-17', 'masculino', 'BA', 79.3),
    ('a1b2c3d4-0000-4000-8000-000000000007', 7,  'gabriela.pereira.nunes@pacientes.seed.dev', 'Gabriela Pereira Nunes', '2001-12-05', 'feminino',  'SC', 55.2),
    ('a1b2c3d4-0000-4000-8000-000000000008', 8,  'henrique.barbosa.melo@pacientes.seed.dev',  'Henrique Barbosa Melo',  '1985-04-23', 'masculino', 'PE', 88.0),
    ('a1b2c3d4-0000-4000-8000-000000000009', 9,  'isabela.carvalho.moraes@pacientes.seed.dev','Isabela Carvalho Moraes','1990-08-11', 'feminino',  'CE', 64.6),
    ('a1b2c3d4-0000-4000-8000-000000000010', 10, 'joao.vitor.ribeiro@pacientes.seed.dev',     'João Vitor Ribeiro',     '1977-02-28', 'masculino', 'DF', 95.8)
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
select
  '00000000-0000-0000-0000-000000000000',
  sp.id,
  'authenticated',
  'authenticated',
  sp.email_auth,
  crypt('SeedPaciente#2026', gen_salt('bf')),
  now(),
  now(),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  '', '', '', ''
from seed_pacientes sp
cross join seed_ctx
on conflict (id) do nothing;

-- ============================================================================
-- 2. perfis_usuarios — nickname (plaintext por desenho) carrega o nome
--    fictício; nome/email/telefone ficam NULL (ver nota de arquitetura acima).
-- ============================================================================
with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id, idx, email_auth, nome_display, data_nascimento, sexo_biologico, geo_ranking_id, peso_base_kg) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid, 1,  'ana.paula.ferreira@pacientes.seed.dev',     'Ana Paula Ferreira',     '1988-03-14'::date, 'feminino',  'SP', 68.4),
    ('a1b2c3d4-0000-4000-8000-000000000002', 2,  'bruno.henrique.costa@pacientes.seed.dev',   'Bruno Henrique Costa',   '1975-11-02', 'masculino', 'RJ', 84.2),
    ('a1b2c3d4-0000-4000-8000-000000000003', 3,  'carla.souza.lima@pacientes.seed.dev',       'Carla Souza Lima',       '1992-07-21', 'feminino',  'MG', 61.9),
    ('a1b2c3d4-0000-4000-8000-000000000004', 4,  'diego.almeida.santos@pacientes.seed.dev',   'Diego Almeida Santos',   '1980-01-30', 'masculino', 'RS', 91.5),
    ('a1b2c3d4-0000-4000-8000-000000000005', 5,  'elisa.martins.rocha@pacientes.seed.dev',    'Elisa Martins Rocha',    '1998-09-09', 'feminino',  'PR', 58.7),
    ('a1b2c3d4-0000-4000-8000-000000000006', 6,  'felipe.oliveira.dias@pacientes.seed.dev',   'Felipe Oliveira Dias',   '1968-05-17', 'masculino', 'BA', 79.3),
    ('a1b2c3d4-0000-4000-8000-000000000007', 7,  'gabriela.pereira.nunes@pacientes.seed.dev', 'Gabriela Pereira Nunes', '2001-12-05', 'feminino',  'SC', 55.2),
    ('a1b2c3d4-0000-4000-8000-000000000008', 8,  'henrique.barbosa.melo@pacientes.seed.dev',  'Henrique Barbosa Melo',  '1985-04-23', 'masculino', 'PE', 88.0),
    ('a1b2c3d4-0000-4000-8000-000000000009', 9,  'isabela.carvalho.moraes@pacientes.seed.dev','Isabela Carvalho Moraes','1990-08-11', 'feminino',  'CE', 64.6),
    ('a1b2c3d4-0000-4000-8000-000000000010', 10, 'joao.vitor.ribeiro@pacientes.seed.dev',     'João Vitor Ribeiro',     '1977-02-28', 'masculino', 'DF', 95.8)
)
insert into perfis_usuarios (
  id, nickname, data_nascimento, sexo_biologico, pais, geo_ranking_id,
  eh_profissional, tipo_profissional, status_aprovacao, is_admin
)
select
  sp.id, sp.nome_display, sp.data_nascimento, sp.sexo_biologico, 'BR', sp.geo_ranking_id,
  false, null, 'aprovado', false
from seed_pacientes sp
cross join seed_ctx
on conflict (id) do update set
  nickname = excluded.nickname,
  data_nascimento = excluded.data_nascimento,
  sexo_biologico = excluded.sexo_biologico,
  geo_ranking_id = excluded.geo_ranking_id;

-- ============================================================================
-- 3. vinculos_profissional_paciente — a unidade de faturamento (F.2). Datas
--    de início espalhadas nos últimos 6 meses para parecer uma carteira real
--    formada aos poucos, não 10 altas no mesmo dia.
-- ============================================================================
with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id, idx, email_auth, nome_display, data_nascimento, sexo_biologico, geo_ranking_id, peso_base_kg) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid, 1,  'ana.paula.ferreira@pacientes.seed.dev',     'Ana Paula Ferreira',     '1988-03-14'::date, 'feminino',  'SP', 68.4),
    ('a1b2c3d4-0000-4000-8000-000000000002', 2,  'bruno.henrique.costa@pacientes.seed.dev',   'Bruno Henrique Costa',   '1975-11-02', 'masculino', 'RJ', 84.2),
    ('a1b2c3d4-0000-4000-8000-000000000003', 3,  'carla.souza.lima@pacientes.seed.dev',       'Carla Souza Lima',       '1992-07-21', 'feminino',  'MG', 61.9),
    ('a1b2c3d4-0000-4000-8000-000000000004', 4,  'diego.almeida.santos@pacientes.seed.dev',   'Diego Almeida Santos',   '1980-01-30', 'masculino', 'RS', 91.5),
    ('a1b2c3d4-0000-4000-8000-000000000005', 5,  'elisa.martins.rocha@pacientes.seed.dev',    'Elisa Martins Rocha',    '1998-09-09', 'feminino',  'PR', 58.7),
    ('a1b2c3d4-0000-4000-8000-000000000006', 6,  'felipe.oliveira.dias@pacientes.seed.dev',   'Felipe Oliveira Dias',   '1968-05-17', 'masculino', 'BA', 79.3),
    ('a1b2c3d4-0000-4000-8000-000000000007', 7,  'gabriela.pereira.nunes@pacientes.seed.dev', 'Gabriela Pereira Nunes', '2001-12-05', 'feminino',  'SC', 55.2),
    ('a1b2c3d4-0000-4000-8000-000000000008', 8,  'henrique.barbosa.melo@pacientes.seed.dev',  'Henrique Barbosa Melo',  '1985-04-23', 'masculino', 'PE', 88.0),
    ('a1b2c3d4-0000-4000-8000-000000000009', 9,  'isabela.carvalho.moraes@pacientes.seed.dev','Isabela Carvalho Moraes','1990-08-11', 'feminino',  'CE', 64.6),
    ('a1b2c3d4-0000-4000-8000-000000000010', 10, 'joao.vitor.ribeiro@pacientes.seed.dev',     'João Vitor Ribeiro',     '1977-02-28', 'masculino', 'DF', 95.8)
)
insert into vinculos_profissional_paciente (
  profissional_id, paciente_id, status, tipo_pagador, tipo_produto, data_inicio
)
select
  seed_ctx.profissional_id,
  sp.id,
  'ativo'::status_vinculo,
  'profissional'::tipo_pagador_vinculo,
  'sem_garmin'::tipo_produto_vinculo,
  (current_date - ((sp.idx * 17) % 180) * interval '1 day')::date
from seed_pacientes sp
cross join seed_ctx
on conflict (profissional_id, paciente_id) where status <> 'encerrado'
do update set
  status = 'ativo',
  atualizado_em = now();

-- ============================================================================
-- 4. planejamento_clinico — `PatientList.tsx` ainda lista pacientes a partir
--    daqui (não do vínculo diretamente), então sem isto os 10 pacientes acima
--    ficariam invisíveis em "Meus Pacientes/Alunos". Tag `seed_demo_baseline`
--    isola estas linhas de prescrições reais para o delete-antes-de-inserir
--    ser seguro em reexecuções.
-- ============================================================================
with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid), ('a1b2c3d4-0000-4000-8000-000000000002'),
    ('a1b2c3d4-0000-4000-8000-000000000003'), ('a1b2c3d4-0000-4000-8000-000000000004'),
    ('a1b2c3d4-0000-4000-8000-000000000005'), ('a1b2c3d4-0000-4000-8000-000000000006'),
    ('a1b2c3d4-0000-4000-8000-000000000007'), ('a1b2c3d4-0000-4000-8000-000000000008'),
    ('a1b2c3d4-0000-4000-8000-000000000009'), ('a1b2c3d4-0000-4000-8000-000000000010')
)
delete from planejamento_clinico pc
using seed_ctx
where pc.profissional_id = seed_ctx.profissional_id
  and pc.tipo_plano = 'seed_demo_baseline'
  and pc.paciente_id_anonimo in (select id from seed_pacientes);

with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id, idx) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid, 1), ('a1b2c3d4-0000-4000-8000-000000000002', 2),
    ('a1b2c3d4-0000-4000-8000-000000000003', 3), ('a1b2c3d4-0000-4000-8000-000000000004', 4),
    ('a1b2c3d4-0000-4000-8000-000000000005', 5), ('a1b2c3d4-0000-4000-8000-000000000006', 6),
    ('a1b2c3d4-0000-4000-8000-000000000007', 7), ('a1b2c3d4-0000-4000-8000-000000000008', 8),
    ('a1b2c3d4-0000-4000-8000-000000000009', 9), ('a1b2c3d4-0000-4000-8000-000000000010', 10)
)
insert into planejamento_clinico (
  profissional_id, paciente_id_anonimo, tipo_plano, sincronizado_garmin, criado_em
)
select
  seed_ctx.profissional_id,
  sp.id,
  'seed_demo_baseline',
  false,
  now() - ((sp.idx * 17) % 180) * interval '1 day'
from seed_pacientes sp
cross join seed_ctx;

-- ============================================================================
-- 5. metricas_saude_diarias — 6 meses (182 dias) por paciente, o que
--    `PatientDetails` (recharts) já lê para os gráficos de evolução. Peso com
--    leve tendência de queda + ruído diário, para o gráfico não ficar uma
--    linha reta.
-- ============================================================================
with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id, idx, peso_base_kg) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid, 1,  68.4),
    ('a1b2c3d4-0000-4000-8000-000000000002', 2,  84.2),
    ('a1b2c3d4-0000-4000-8000-000000000003', 3,  61.9),
    ('a1b2c3d4-0000-4000-8000-000000000004', 4,  91.5),
    ('a1b2c3d4-0000-4000-8000-000000000005', 5,  58.7),
    ('a1b2c3d4-0000-4000-8000-000000000006', 6,  79.3),
    ('a1b2c3d4-0000-4000-8000-000000000007', 7,  55.2),
    ('a1b2c3d4-0000-4000-8000-000000000008', 8,  88.0),
    ('a1b2c3d4-0000-4000-8000-000000000009', 9,  64.6),
    ('a1b2c3d4-0000-4000-8000-000000000010', 10, 95.8)
)
insert into metricas_saude_diarias (
  usuario_id_anonimo, data_referencia, passos, distancia_metros, fc_repouso, hrv_medio,
  calorias_ativas, minutos_sono, peso_kg, percentual_gordura,
  pressao_sistolica, pressao_diastolica, glicose_jejum, saturacao_oxigenio,
  temperatura_corporal, origem
)
select
  sp.id,
  serie.dia::date,
  (4000 + floor(random() * 7000))::int,
  round((2000 + random() * 7000)::numeric, 2),
  (54 + (sp.idx % 6) * 3 + floor(random() * 8 - 4))::int,
  round((28 + random() * 45)::numeric, 2),
  round((220 + random() * 480)::numeric, 2),
  (300 + floor(random() * 180))::int,
  round(
    (sp.peso_base_kg
      - ((current_date - serie.dia::date)::numeric / 182.0) * 3.2
      + (random() - 0.5) * 0.8
    )::numeric, 2
  ),
  round((16 + (sp.idx % 5) * 2.5 + random() * 3)::numeric, 2),
  (108 + floor(random() * 24))::int,
  (66 + floor(random() * 18))::int,
  round((80 + (sp.idx % 4) * 6 + random() * 10)::numeric, 2),
  round((95.5 + random() * 3.4)::numeric, 2),
  round((36.1 + random() * 0.8)::numeric, 2),
  'seed_demo'
from seed_pacientes sp
cross join seed_ctx
cross join generate_series(current_date - interval '182 days', current_date, interval '1 day') as serie(dia)
on conflict (usuario_id_anonimo, data_referencia) do update set
  passos = excluded.passos,
  distancia_metros = excluded.distancia_metros,
  fc_repouso = excluded.fc_repouso,
  hrv_medio = excluded.hrv_medio,
  calorias_ativas = excluded.calorias_ativas,
  minutos_sono = excluded.minutos_sono,
  peso_kg = excluded.peso_kg,
  percentual_gordura = excluded.percentual_gordura,
  pressao_sistolica = excluded.pressao_sistolica,
  pressao_diastolica = excluded.pressao_diastolica,
  glicose_jejum = excluded.glicose_jejum,
  saturacao_oxigenio = excluded.saturacao_oxigenio,
  temperatura_corporal = excluded.temperatura_corporal,
  origem = excluded.origem,
  atualizado_em = now();

-- ============================================================================
-- 6. progresso_gamificacao — usado pelo HealthScore aproximado em `PatientList`.
-- ============================================================================
with seed_ctx as (
  select id as profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1
),
seed_pacientes (id, idx) as (
  values
    ('a1b2c3d4-0000-4000-8000-000000000001'::uuid, 1), ('a1b2c3d4-0000-4000-8000-000000000002', 2),
    ('a1b2c3d4-0000-4000-8000-000000000003', 3), ('a1b2c3d4-0000-4000-8000-000000000004', 4),
    ('a1b2c3d4-0000-4000-8000-000000000005', 5), ('a1b2c3d4-0000-4000-8000-000000000006', 6),
    ('a1b2c3d4-0000-4000-8000-000000000007', 7), ('a1b2c3d4-0000-4000-8000-000000000008', 8),
    ('a1b2c3d4-0000-4000-8000-000000000009', 9), ('a1b2c3d4-0000-4000-8000-000000000010', 10)
)
insert into progresso_gamificacao (
  usuario_id_anonimo, ofensiva_atual, pontuacao_ranking, ultima_atividade_data, status_usuario
)
select
  sp.id,
  (2 + floor(random() * 30))::int,
  (40 + (sp.idx % 6) * 8 + floor(random() * 12))::int,
  current_date,
  'ativo'
from seed_pacientes sp
cross join seed_ctx
on conflict (usuario_id_anonimo) do update set
  ofensiva_atual = excluded.ofensiva_atual,
  pontuacao_ranking = excluded.pontuacao_ranking,
  ultima_atividade_data = excluded.ultima_atividade_data,
  status_usuario = excluded.status_usuario;

-- ============================================================================
-- 7. Resumo
-- ============================================================================
do $$
declare
  v_profissional_id uuid;
begin
  select id into v_profissional_id from auth.users where lower(email) = lower('educarmo@gmail.com') limit 1;
  if v_profissional_id is not null then
    raise notice 'Seed OK: 10 pacientes fictícios vinculados a educarmo@gmail.com, com 6 meses de métricas diárias cada.';
  end if;
end $$;
