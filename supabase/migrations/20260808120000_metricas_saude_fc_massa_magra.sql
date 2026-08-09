-- N17/N18 (Fase 2, Parte 9.1) — Persistência da telemetria de wearables.
--
-- Duas colunas novas em `metricas_saude_diarias` (20260708174650), pedidas
-- explicitamente pela tarefa ("passos, sono, FC, FC repouso, gasto
-- energético, peso, massa magra e % gordura") e que o schema atual não
-- cobre:
--
--   - `frequencia_cardiaca`: até esta tarefa, `HealthDataType.HEART_RATE`
--     (a leitura contínua/genérica do wearable) era gravada na coluna
--     `fc_repouso` — não existia distinção entre "FC" e "FC repouso" no
--     schema, então o app usava a única coluna de FC que tinha. Passa a
--     existir `HealthDataType.RESTING_HEART_RATE` (métrica dedicada do
--     Health Connect, calculada pelo próprio SO/wearable, tipicamente
--     durante o sono) como fonte de `fc_repouso`; `HEART_RATE` genérico
--     passa a ir para esta coluna nova. Ver RELATÓRIO para a decisão
--     completa, incluindo o ajuste correspondente na detecção de anomalias
--     (Caixa Preta), que passa a checar esta coluna, não `fc_repouso`.
--   - `massa_magra_kg`: `HealthDataType.LEAN_BODY_MASS` não tinha nenhuma
--     coluna — sinal simplesmente não era lido nem gravado antes desta
--     tarefa.
--
-- Nenhuma das duas quebra dado existente: `add column` nullable, sem
-- default, sem backfill (não há como reconstruir massa magra retroativa a
-- partir do que já foi gravado; frequência cardíaca genérica retroativa
-- também não — o que estava em `fc_repouso` antes desta migration fica
-- como estava, histórico não é reclassificado).
alter table metricas_saude_diarias
  add column frequencia_cardiaca int,
  add column massa_magra_kg numeric(5, 2);

comment on column metricas_saude_diarias.frequencia_cardiaca is
  'Leitura de HealthDataType.HEART_RATE (genérica/contínua) mais recente do dia — distinta de fc_repouso (HealthDataType.RESTING_HEART_RATE). Nullable: nem todo wearable expõe os dois sinais separadamente.';
comment on column metricas_saude_diarias.massa_magra_kg is
  'HealthDataType.LEAN_BODY_MASS mais recente do dia (kg) — balanças de bioimpedância. Nullable: sinal raro, poucas balanças expõem.';

-- ============================================================================
-- GRANT (Parte 0.10): nenhum novo necessário — GRANT é por tabela, não por
-- coluna (mesma nota já registrada em 20260727120000 ao acrescentar
-- `embedding`); `metricas_saude_diarias` já concede select/insert/update ao
-- dono da linha via RLS (20260708174650) e essas policies não referenciam
-- coluna nenhuma explicitamente, então cobrem as duas novas automaticamente.
