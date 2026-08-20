# 20260819_0021_fix_treino_permissao_total_calories_e_novas_metricas_garmin — Corrige o bug real de treino (permissão faltante) + implementa calorias totais/andares subidos/velocidade

Log de Máquina (Regra 10.3 — append-only). Continuação direta do
RELATÓRIO 20260819_0020: fundador confirmou os achados daquele
relatório e pediu 4 coisas nesta tarefa (modo autônomo, sem device
físico disponível — só testes automatizados):
1. Implementar a mudança de calorias (`TOTAL_CALORIES_BURNED`).
2. Verificar e implementar, se existirem no pacote `health`, outras
   variáveis vistas na tela de permissões do Garmin: andares subidos,
   distâncias, exercícios, ganho de elevação, velocidade.
3. Corrigir "a funcionalidade de leitura da atividade não está
   funcionando" (treino não aparece na tela nem grava no banco).
4. Investigar mais fundo a divergência de passos/distância dos dias
   15/08 e 16/08.

## 1. Causa raiz real do bug de treino (achado, não suposição)

Confirmado lendo a stack trace completa capturada no logcat da sessão
anterior (device físico, `adb logcat -d`, ainda salvo localmente):

```
java.lang.SecurityException: android.health.connect.HealthConnectException:
java.lang.SecurityException: Caller requires
android.permission.health.READ_TOTAL_CALORIES_BURNED to read record type
class android.health.connect.datatypes.TotalCaloriesBurnedRecord
```

Lendo o source do pacote `health` 13.3.1
(`HealthDataReader.kt#handleWorkoutData`): ao processar
`HealthDataType.WORKOUT`, o plugin lê `TotalCaloriesBurnedRecord` POR
BAIXO DOS PANOS pra cada sessão de exercício encontrada (calcula a
energia total queimada do treino). Sem `READ_TOTAL_CALORIES_BURNED` no
Manifest, essa leitura interna lança `SecurityException`, que sobe até
o `catch (e: Exception)` externo de `getData()` — o plugin loga o erro
e devolve **lista vazia pro tipo WORKOUT inteiro**, não só o campo de
calorias. Não era um bug de parsing/lógica do lado Dart (nenhum código
nosso estava quebrado) — 100% uma permissão Android faltante.

## 2. Correção + implementação das métricas pedidas

- `AndroidManifest.xml`: 3 permissões novas —
  `READ_TOTAL_CALORIES_BURNED` (corrige o bug de treino E destrava
  calorias totais), `READ_FLOORS_CLIMBED`, `READ_SPEED`.
- `HealthSyncService.todosOsTipos`: `HealthDataType.TOTAL_CALORIES_BURNED`,
  `FLIGHTS_CLIMBED`, `SPEED` adicionados.
- `HealthPayloadModel`: campo novo `andaresSubidos` (FLIGHTS_CLIMBED) +
  round-trip completo (`fromHealthDataType`/`fromAiExtraction`/`fromJson`/
  `toJson`/`camposPreenchidos`). `caloriasTotais` já existia como campo
  (usado só pro round-trip da tela) — agora também populado direto por
  `TOTAL_CALORIES_BURNED`.
- `HealthSyncService._mesclarPorDia`:
  - `andares_subidos`: "maior fonte do dia" (mesmo padrão anti-double-
    counting de `calorias_ativas`), sem a exclusão de fonte de
    `_ehFonteValidaParaCalorias` — floors não tem o problema de
    "app de balança calculando estimativa pontual" que motivou aquela
    lista.
  - `calorias_totais`: agora prioriza a leitura DIRETA de
    `TOTAL_CALORIES_BURNED` (mesma exclusão de fonte de
    calorias_ativas/basais — nunca cai pro Fitdays/pedômetro nativo,
    maior fonte entre wearables válidos) quando o dia tiver; só cai pro
    fallback antigo (`ativas + basais`, tratando ausente como 0) nos
    dias/plataformas sem leitura direta (ex.: iOS — achado do RELATÓRIO
    20260810_0007/spike de que `TOTAL_CALORIES_BURNED` "não tem
    implementação real" lá segue válido; nunca foi um problema no
    Android, onde o app roda de verdade hoje).
- `HealthSyncService._processarTreinos`: `HealthDataType.SPEED` (m/s)
  filtrada ao intervalo exato do treino, mesmo tratamento de
  `fc_media`/`fc_maxima` — grava `velocidade_media_ms`/
  `velocidade_maxima_ms` só quando há pelo menos 1 ponto no intervalo
  (nunca zerado).
- Migration `20260819150000_andares_subidos_e_velocidade_treino.sql`:
  `metricas_saude_diarias.andares_subidos` (int) e
  `atividades_fisicas_treinos.velocidade_media_ms`/`velocidade_maxima_ms`
  (numeric) — **aplicada no banco remoto** (`supabase db push`,
  confirmada via consulta PostgREST pós-aplicação). `calorias_totais`
  não precisou de coluna nova (já existia desde 20260811160000).
- UI: `historico_telemetria_page.dart` ganha o campo "Andares subidos"
  (calorias totais já existia na tela, sem mudança de UI — só passa a
  vir preenchida com dado real mais frequentemente).
  `historico_treinos_page.dart`/`treino_model.dart` ganham "Vel.
  média"/"Vel. máx." (convertidas de m/s pra km/h só na exibição), com
  chaves de i18n novas em `pt`/`en`/`es.json`.

### Achado colateral, não implementado: `ELEVATION_GAINED`

O fundador também pediu "ganho de elevação". Confirmado lendo o enum
completo `HealthDataType` de `health` 13.3.1
(`lib/src/heath_data_types.dart`): o pacote **não expõe** esse tipo —
o Health Connect nativo tem `ElevationGainedRecord`, mas o pacote não
o mapeia (nem em Kotlin nem em Dart). Sem patchar o pacote (fora do
escopo desta tarefa — mudaria uma dependência de terceiros, não código
do projeto), não é implementável. Registrado como backlog explícito no
comentário da migration e aqui.

## 3. Investigação adicional: passos/distância 15/08 e 16/08

Revisão de código mais profunda (sem device disponível nesta tarefa —
fundador reservou o celular pra uso pessoal) não encontrou nenhum
mecanismo NOVO de bug além do já concluído no RELATÓRIO 20260819_0020:
a Hierarquia de Fontes (`_fonteVencedoraDoDia`) escolhe corretamente o
Garmin como fonte vencedora nesses dias (confirmado via banco antes E
depois do zera-e-recarrega, mesmo resultado); os valores gravados
refletem exatamente o que o Health Connect tinha no MOMENTO da leitura
— o app do Garmin mostra um número diferente porque o próprio Garmin
sincroniza com o Health Connect de forma assíncrona/tardia em relação
ao que exibe na própria UI dele. Não existe, do lado do nosso
pipeline, um jeito de "puxar" um dado que o Health Connect ainda não
recebeu. Nenhuma mudança de código feita aqui — reafirma a decisão já
tomada pelo fundador de manter como está.

## Verificação

- `flutter analyze` limpo (0 erros/warnings novos; só os 5 lints
  pré-existentes de sempre, nenhum nos arquivos tocados nesta tarefa).
- `flutter test test/features/dashboard/data/services/health_sync_service_test.dart`:
  98 testes passando (91 anteriores + 7 novos: 3 de `calorias_totais`
  direto/fallback/exclusão-Fitdays, 2 de `andares_subidos`
  maior-fonte/ausência, 2 de velocidade de treino
  presente/ausência).
- `flutter test test/features/dashboard/`: 180 testes passando (168 +
  12 — os 7 acima + 5 novos em `health_payload_model_test.dart`:
  round-trip de `andares_subidos` e mapeamento de
  `FLIGHTS_CLIMBED`/`TOTAL_CALORIES_BURNED` via `fromHealthDataType`).
- `flutter test` (suíte inteira): 11 falhas pré-existentes, **não
  relacionadas** a esta tarefa — todas em
  `test/features/nutrition/presentation/pages/confirmacao_prato_page_test.dart`/
  `manual_food_search_page_test.dart` (feature de nutrição/foto de
  prato, nenhum arquivo tocado aqui). Não investigado nem corrigido —
  fora do escopo pedido; registrado pra visibilidade do fundador.
- `supabase db push`: aplicado com sucesso. Achado no caminho: o
  histórico de migrations local estava dessincronizado do remoto —
  `20260812230000_seed_problemas_saude_clinicos.sql` (commit `d6ae3c1`,
  branch `feat/seed-problemas-saude`) estava aplicado no banco real mas
  nunca tinha sido mesclado nesta branch; trazido via
  `git checkout d6ae3c1 -- <arquivo>` (commit `8895521`) antes do push
  da migration nova, sem tocar em nenhum dado.

## Não resolvido / próximo passo

**Nada desta tarefa chegou no device físico** — o fundador está usando
o celular pra uso pessoal durante esta sessão. Pendente, na próxima
janela com o device disponível:
- Confirmar que o treino agora aparece em `historico_treinos_page.dart`
  e grava em `atividades_fisicas_treinos` (o fix real desta tarefa).
- Confirmar `calorias_totais` vindo direto do Garmin (não mais só
  ativas+basais) nos dias com atividade.
- Confirmar `andares_subidos` e velocidade de treino aparecendo com
  dado real (nunca testados contra o Health Connect de verdade, só
  contra mocks).
