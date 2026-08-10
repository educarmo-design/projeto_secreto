# Índice — Log de Desenvolvimento

Governança de logs de desenvolvimento (N25, Parte 10.3 do Mestre). Cada entrada é
um relatório de fim de tarefa, um arquivo por tarefa, nomeado `AAAAMMDD_NNNN.md`
(NNNN = sequencial do dia, começando em 0001).

| Arquivo | Data | Resumo |
|---|---|---|
| [20260807_0001.md](20260807_0001.md) | 2026-08-07 | Auditoria do estado do Git (N26): F10 Passo 3 + F34 + D2-PII já estavam mesclados na main desde 2026-07-30; build debug confirmado sem erros; 24 commits publicados em origin/main e as 3 branches obsoletas removidas (local+remoto) por autorização do fundador; inicialização deste log. |
| [20260807_0002.md](20260807_0002.md) | 2026-08-07 | N20: re-seed de embeddings reais em `alimentos_referencia` (637 linhas, não ~8.000 como o Mestre registrava), índice HNSW, secrets `EMBEDDING_MODEL_NAME`/thresholds, correção de bug de `taskType` ausente em `search-food`. |
| [20260808_0001.md](20260808_0001.md) | 2026-08-08 | N17+N18: persistência idempotente de telemetria de wearables — corrige `carregarHistoricoInicial` que só lia e nunca gravava (Carga Inicial de 30 dias), liga o delta diário automático ao abrir o app, adiciona `frequencia_cardiaca`/`massa_magra_kg`. |
| [20260809_0001.md](20260809_0001.md) | 2026-08-09 | Corrige bug "só 2 dias" da Carga Inicial (causa raiz: permissão `READ_HEALTH_DATA_HISTORY` ausente, restrição do próprio Health Connect) + N19: tela de Histórico de Telemetria com botões de debug "FORÇAR SYNC HOJE"/"FORÇAR CARGA 30 DIAS". |
