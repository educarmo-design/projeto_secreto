-- RELATÓRIO 20260811 (correção pós-teste físico N17/N18) — decisão de
-- produto: em vez de um único total de sono (que já estava incorreto por
-- somar SLEEP_SESSION+SLEEP_ASLEEP em dobro, ver migration 20260810 e
-- RELATÓRIO daquela tarefa), aproveitar a riqueza de estágios que o Garmin
-- já reporta ao Health Connect e gravar cada fase separada.
--
-- `minutos_sono` (coluna já existente, 20260708174650) deixa de ser
-- alimentada diretamente por um único HealthDataType — passa a ser
-- CALCULADA no app (HealthSyncService._mesclarPorDia) como
-- sono_leve_minutos + sono_profundo_minutos + sono_rem_minutos,
-- estritamente EXCLUINDO sono_acordado_minutos. Continua existindo porque é
-- o número que a maior parte da UI (N19, dashboards futuros) quer exibir
-- direto sem somar 3 colunas toda vez.
alter table metricas_saude_diarias
  add column sono_leve_minutos int,
  add column sono_profundo_minutos int,
  add column sono_rem_minutos int,
  add column sono_acordado_minutos int;

comment on column metricas_saude_diarias.sono_leve_minutos is
  'HealthDataType.SLEEP_LIGHT somado no dia (bucketizado pela manhã do despertar, não pelo dia calendário em que o estágio caiu — ver HealthSyncService._dataDoSonoLocal). Também recebe SLEEP_ASLEEP (fallback de dispositivos sem estágio granular).';
comment on column metricas_saude_diarias.sono_profundo_minutos is
  'HealthDataType.SLEEP_DEEP somado no dia — mesma bucketização de sono_leve_minutos.';
comment on column metricas_saude_diarias.sono_rem_minutos is
  'HealthDataType.SLEEP_REM somado no dia — mesma bucketização de sono_leve_minutos.';
comment on column metricas_saude_diarias.sono_acordado_minutos is
  'HealthDataType.SLEEP_AWAKE somado no dia — tempo acordado DENTRO da sessão de sono (ex.: acordou às 3h, mexeu no celular). NUNCA entra no total de minutos_sono.';

comment on column metricas_saude_diarias.minutos_sono is
  'Total de sono real do dia = sono_leve_minutos + sono_profundo_minutos + sono_rem_minutos (exclui sono_acordado_minutos). Calculado em HealthSyncService._mesclarPorDia, não escrito diretamente por nenhum HealthDataType desde 20260811 — ver RELATÓRIO daquela tarefa.';

-- ============================================================================
-- GRANT (Parte 0.10): nenhum novo necessário — GRANT é por tabela, não por
-- coluna (mesma nota já registrada em 20260727120000/20260808120000);
-- metricas_saude_diarias já concede select/insert/update ao dono da linha
-- via RLS (20260708174650), sem referência a coluna específica.
