-- Spike N17/N18 (RELATÓRIO 20260810_0003) confirmou quais HealthDataType o
-- Health Connect/Android realmente expõe para FC e balança. Esta migration
-- acrescenta as colunas para as métricas absolutas decididas pelo fundador
-- a partir desse mapeamento — SEM nenhuma lógica de detecção de anomalia
-- (Parte 5/BL.1: Motor Clínico F02, backlog — ver RELATÓRIO desta tarefa).
alter table metricas_saude_diarias
  add column if not exists fc_maxima int,
  add column if not exists agua_corporal numeric(5, 2),
  add column if not exists imc numeric(4, 1);

comment on column metricas_saude_diarias.fc_maxima is
  'Máximo entre as leituras de HealthDataType.HEART_RATE do dia (mesma fonte que frequencia_cardiaca, que é a MÉDIA) — não é limite clínico nem evento, só o maior valor absoluto lido. HealthSyncService._mesclarPorDia.';
comment on column metricas_saude_diarias.agua_corporal is
  'HealthDataType.BODY_WATER_MASS mais recente do dia (kg) — balanças de bioimpedância. Nullable: sinal raro.';
comment on column metricas_saude_diarias.imc is
  'IMC do dia. Prioridade: (1) HealthDataType.BODY_MASS_INDEX, se o dispositivo/app de origem já calcular e publicar; (2) senão, inferido em HealthSyncService._aplicarInferenciasCruzadas como peso_kg / altura_m² usando a altura de perfis_usuarios.altura_cm, quando disponível.';

-- altura_cm em perfis_usuarios: infraestrutura mínima para a inferência de
-- IMC pedida nesta tarefa ("buscando a altura do perfil do usuário no
-- Supabase, se disponível") — a tabela não tinha nenhum campo de altura até
-- aqui. Nullable e sem tela de preenchimento ainda (fora do escopo desta
-- tarefa — ver RELATÓRIO): enquanto ninguém preencher, a inferência de IMC
-- por peso/altura simplesmente não roda para esse usuário, e IMC só é
-- gravado quando o próprio Health Connect entregar pronto.
alter table perfis_usuarios
  add column if not exists altura_cm numeric(5, 1);

comment on column perfis_usuarios.altura_cm is
  'Altura em centímetros, usada por HealthSyncService._aplicarInferenciasCruzadas para calcular IMC quando o Health Connect não entrega HealthDataType.BODY_MASS_INDEX pronto. Nullable — sem UI de preenchimento ainda (pendência registrada no RELATÓRIO).';

-- ============================================================================
-- GRANT (Parte 0.10): nenhum novo necessário — GRANT é por tabela, não por
-- coluna. metricas_saude_diarias e perfis_usuarios já concedem
-- select/insert/update ao dono da linha via RLS, sem referência a coluna
-- específica.
