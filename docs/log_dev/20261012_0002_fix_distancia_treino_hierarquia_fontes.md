# Correção — distância do treino via Hierarquia de Fontes (resolve RCA 20261012_0001)

Implementa a correção proposta no RCA `20261012_0001_RCA_distancia_duplicada.md`:
distância de atividades ao ar livre (GPS) vinha ~1,77-1,95× inflada desde
28/09/2026 porque `_processarTreinos` confiava direto em
`workout.totalDistance` (campo agregado que o pacote `health` devolve pra
sessão de treino inteira) — e esse campo, confirmado lendo o código-fonte
do plugin (`HealthDataReader.kt::handleWorkoutData`, versão `13.3.1`
instalada), soma CEGAMENTE todos os `DistanceRecord` que o Health Connect
tem na janela do treino, de qualquer fonte/app, sem filtro de origem. Bug
é do pacote de terceiros, não deste repositório; não há como corrigi-lo
mudando a versão (persiste na `13.3.1`, a mesma usada antes e depois de
28/09) — a correção precisa acontecer na nossa ponta, ignorando o valor
agregado do plugin.

## O que mudou

`lib/features/dashboard/data/services/health_sync_service.dart`:

- **Novo método `_distanciaTreinoPorHierarquiaDeFontes`**: recalcula a
  distância do treino a partir dos pontos granulares
  `DISTANCE_DELTA`/`DISTANCE_WALKING_RUNNING` do mesmo lote de sincronização
  (já lidos pra alimentar `metricas_saude_diarias`), filtrados pelo
  INTERVALO exato do treino (`dentroDoIntervalo`, mesmo padrão já usado pra
  FC/velocidade do treino), agrupados por
  `HealthMetricPoint.identificadorFonte`. Aplica a MESMA Hierarquia de
  Fontes que a distância diária já usa (`_ehPedometroNativo`: prioridade
  pra quem não é pedômetro nativo reconhecido, desempate pelo maior valor
  dentro da mesma prioridade) — nunca soma 2 fontes diferentes entre si,
  pega a vencedora e usa só ela.
- **`_processarTreinos`**: `distancia_metros` do treino agora vem desse
  novo método; só cai pra `workout.totalDistance` (comportamento antigo)
  quando a janela do treino não tem NENHUM ponto `DISTANCE_DELTA`/
  `DISTANCE_WALKING_RUNNING` — caso de modalidades sem amostra granular de
  GPS (ex. esteira, calculada internamente por cadência) — pra não perder
  o dado só porque a fonte granular não existe pra essa modalidade. É
  exatamente o caso do treino de esteira do fundador (05/10), que já vinha
  correto e continua vindo pelo mesmo caminho de antes.
- **Duração, calorias, passos, FC, velocidade: NADA mudou** (restrição da
  tarefa) — continuam vindo direto do `WorkoutHealthValue`, já confirmados
  corretos contra o Garmin no RCA.

## Por que a unidade bate

`DISTANCE_DELTA`/`DISTANCE_WALKING_RUNNING` já chegam em METROS no nosso
código (confirmado em `HealthPayloadModel` — `case
HealthDataType.DISTANCE_WALKING_RUNNING: case HealthDataType.DISTANCE_DELTA:
distanciaMetros: value`, sem nenhuma conversão), a mesma unidade que
`workout.totalDistance` já usava (`totalDistanceUnit: METER`, confirmado no
código do plugin) e que a coluna `atividades_fisicas_treinos.distancia_metros`
espera. Nenhuma conversão de unidade foi necessária.

## Verificação

- **2 testes novos** em
  `test/features/dashboard/data/services/health_sync_service_test.dart`
  (grupo "Treinos e Rotas"):
  1. Treino com `workout.totalDistance: 20000` (valor inflado, simula o bug
     real) + 2 fontes de `DISTANCE_DELTA` na mesma janela (Garmin, 8000m,
     alta prioridade; `com.android.healthconnect.phone.*`, 7000m, pedômetro
     nativo) — confirma que o valor gravado é **8000** (só a fonte
     vencedora), nem o valor cru do plugin (20000) nem a soma das 2 fontes
     (15000).
  2. Treino sem NENHUM ponto `DISTANCE_DELTA` na janela — confirma fallback
     pro `workout.totalDistance` (caso esteira), preservando o
     comportamento correto que já existia.
- `flutter analyze`: 30 issues (linha de base do projeto, zero novo).
- `flutter test`: **514/514** (era 512/512 antes desta tarefa, +2 novos),
  zero regressão — inclui o teste pré-existente de FC do treino (que usa
  `totalDistance: 8000` sem nenhum ponto `DISTANCE_DELTA` na janela,
  continua passando pelo caminho de fallback, valor idêntico).
- Não testado contra o device físico real nesta tarefa (ambiente sem
  acesso a device) — recomendação ao fundador: reinstalar o build e
  confirmar que a próxima corrida ao ar livre grava a distância real
  (bateu com o Garmin no RCA: 28/09=7,91km, 03/10=10,01km, 12/10=8,6km),
  não mais o valor inflado.

## Fora do escopo, documentado

- A causa raiz externa exata (por que uma 2ª fonte de distância por GPS
  passou a existir no Health Connect a partir de 28/09) continua sem
  confirmação — essa correção neutraliza o efeito (nunca mais soma 2
  fontes), mas não investiga a origem externa. Ver RCA `20261012_0001`
  pra detalhes e a sugestão de reportar o achado ao mantenedor do pacote
  `health`.
- Não foi adicionado nenhum guard de concorrência em
  `sincronizarDeltaDiario()` (mitigação secundária mencionada no RCA,
  descartada como causa deste bug específico) — fica como item separado,
  não pedido nesta tarefa.

Branch `fix/bug-distancia-calculo-delta`, a partir de `main`.
