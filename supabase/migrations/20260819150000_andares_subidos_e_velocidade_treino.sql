-- RELATÓRIO 20260819_0020 (decisão do fundador, verificação em device físico
-- dos fixes 0018/0019): sobre a mesma investigação, achado real —
-- HealthDataType.TOTAL_CALORIES_BURNED nunca era solicitado nem tinha
-- permissão Android declarada, e essa MESMA lacuna derrubava a leitura de
-- HealthDataType.WORKOUT inteira (o pacote `health` lê TotalCaloriesBurnedRecord
-- por baixo dos panos ao processar cada sessão de treino — sem a permissão,
-- Health Connect lança SecurityException e o plugin devolve WORKOUT vazio).
-- Corrigido no app (AndroidManifest.xml + HealthSyncService); esta migration
-- cobre as 2 métricas novas que o fundador pediu pra verificar e que o
-- pacote `health` de fato suporta: andares subidos (métrica diária) e
-- velocidade (métrica de treino, mesmo tratamento de FC dentro da sessão).
--
-- calorias_totais NÃO precisa de coluna nova — já existe desde
-- 20260811160000; só passa a ser preenchida por leitura direta quando
-- disponível, em vez de só pelo fallback ativas+basais (ver HealthSyncService.
-- _mesclarPorDia).
--
-- ELEVATION_GAINED (ganho de elevação, também pedido pelo fundador) NÃO
-- entra aqui: o pacote `health` 13.3.1 (versão travada em pubspec.lock) não
-- expõe esse tipo — confirmado lendo o enum completo de HealthDataType em
-- lib/src/heath_data_types.dart, o Health Connect nativo tem
-- ElevationGainedRecord mas o pacote não o mapeia. Sem patch no pacote (fora
-- de escopo desta tarefa), não é implementável — registrado como backlog.

alter table metricas_saude_diarias
  add column if not exists andares_subidos int;

comment on column metricas_saude_diarias.andares_subidos is
  'HealthDataType.FLIGHTS_CLIMBED (FloorsClimbedRecord no Health Connect) — maior fonte do dia (mesmo padrão anti-double-counting de calorias_ativas, sem a exclusão de fonte de _ehFonteValidaParaCalorias). RELATÓRIO 20260819_0020, pedido do fundador.';

alter table atividades_fisicas_treinos
  add column if not exists velocidade_media_ms numeric(6, 2),
  add column if not exists velocidade_maxima_ms numeric(6, 2);

comment on column atividades_fisicas_treinos.velocidade_media_ms is
  'Média de HealthDataType.SPEED (m/s, SpeedRecord no Health Connect) filtrada ao intervalo exato do treino — mesmo tratamento de fc_media. RELATÓRIO 20260819_0020, pedido do fundador.';
comment on column atividades_fisicas_treinos.velocidade_maxima_ms is
  'Máximo de HealthDataType.SPEED (m/s) dentro do intervalo do treino — mesmo tratamento de fc_maxima. RELATÓRIO 20260819_0020.';
