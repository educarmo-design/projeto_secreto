# RCA — Distância duplicada em Atividades (desde 28/09)

**Tipo:** investigação pura (Root Cause Analysis). Nenhuma linha de código de
produção foi alterada nesta tarefa — só leitura de código/histórico/schema.

**Gatilho:** fundador reportou que o cálculo de "Distância" nas Atividades
está duplicando desde 28/09/2026. Duas hipóteses de partida: (1) o rollback
do pacote `health` no Flutter nessa data removeu deduplicação nativa; (2) a
refatoração de RPCs/CTEs no Supabase em 27-28/09 introduziu um produto
cartesiano.

## Resumo executivo

**Nenhuma das duas hipóteses originais (rollback do `health`; CTE/JOIN no
Supabase) se sustenta. Causa raiz confirmada com certeza alta, na linha de
código exata — mas não neste repositório: está dentro do próprio pacote
`health` (dependência de terceiros), não no nosso Flutter nem no SQL.**

O fundador confirmou, comparando direto com o app Garmin, que **duração e
calorias gravadas no banco batem exatamente com o Garmin** em 3 treinos
recentes — só a **distância** vem errada, e só em corridas AO AR LIVRE
(GPS); a esteira (indoor) bateu certo. Fui ler o código-fonte real do
pacote `health` instalado neste projeto (`health-13.3.1`, cache local do
Pub) e encontrei a causa exata: a função que monta cada treino
(`handleWorkoutData`, em
`cachet/plugins/health/HealthDataReader.kt`) faz uma query separada por
`DistanceRecord` dentro da janela de tempo do treino e **soma TODOS os
registros encontrados, de QUALQUER fonte/origem, sem filtrar por
`dataOrigin`** — ao contrário da distância diária no NOSSO código
(`health_sync_service.dart`), que já tem uma hierarquia de fontes
explícita pra evitar exatamente esse tipo de dupla contagem. Se o Health
Connect tiver 2 registros de `DistanceRecord` cobrindo a mesma corrida
(ex.: o relógio via Garmin Connect E outra fonte/app gerando distância por
GPS no mesmo intervalo), o plugin soma os dois achando que são
complementares — e não são.

---

## Hipótese 1 — Rollback do pacote `health` no Flutter (28/09)

**Descartada.**

Rastreei o histórico completo de `pubspec.yaml` em 28/09:

| Commit | Hora | `health` | O que mudou |
|---|---|---|---|
| `f434ae5` | 11:46 | `^13.3.1` → `^13.3.2` | Resolve aviso de KGP, libera `device_info_plus ^13.2.0`/`file_picker ^13.1.0` |
| `2ea759f` | 21:09 | `^13.3.2` → `^13.3.1` | Revertido: erro **fatal** de compilação Kotlin (`:health:compileDebugKotlin`, `Unresolved reference` + mismatch de tipo), não o aviso de KGP |

Ou seja: dentro do mesmo dia, `health` subiu e desceu de volta para a
**mesma versão exata** (`13.3.1`) que já estava em produção desde 25/07.
Dois pontos fecham esta hipótese:

1. **O erro era fatal de compilação Kotlin** — o build com `health 13.3.2`
   nunca chegou a gerar um APK instalável. Não existe build real rodando
   com essa versão em nenhum device.
2. `git show --stat 2ea759f` mostra que o revert tocou só
   `pubspec.yaml`/`pubspec.lock`, `missoes_exames_page.dart` (migração de
   API do `file_picker`, não relacionado a saúde/distância) e o relatório.
   **`health_sync_service.dart` (onde mora toda a lógica de leitura/merge/
   hierarquia de fontes de distância) não foi tocado neste commit nem em
   nenhum commit de 27-29/09** — o último commit que tocou esse arquivo é
   `173667e` (16/09), bem antes da janela investigada.

Conclusão: a lógica de coleta/dedup de distância no Flutter é **byte a byte
idêntica** antes e depois de 28/09.

---

## Hipótese 2 — Produto cartesiano em RPC/CTE no Supabase (27-28/09)

**Descartada**, com uma ressalva documentada abaixo.

Primeiro, uma busca em todas as migrations por qualquer `JOIN` envolvendo
`atividades_fisicas_treinos` (a tabela de origem de "Atividades", 1 linha
por treino real) deu **zero resultados em todo o histórico do repositório**
— não existe, nunca existiu, um JOIN nessa tabela em SQL. Toda leitura dela
é um `SELECT ... FROM atividades_fisicas_treinos WHERE ... GROUP BY` direto,
sem join prévio que pudesse multiplicar linhas antes da agregação.

A mudança real de 27/09 (`a77881b`, migration
`20260927100000_anamnese_qa_refinements.sql`) modificou
`processar_medias_smartwatch` — e o commit **já relata** "bug de escopo de
CTE entre with statements na 1a tentativa, corrigido" antes de ser mesclado.
Analisei essa função linha a linha (dry run mental com 2 treinos no mesmo
dia):

- **`distancia_metros`** nessa RPC é `avg(distancia_metros) FROM
  metricas_saude_diarias` — uma tabela só, sem join nenhum, 1 linha por
  dia. Duas atividades no mesmo dia não mudam esse número: ele já é a
  distância diária "vencedora" calculada pelo Flutter (hierarquia de
  fontes), não uma soma de treinos.
- **`atividades_agrupadas`** (duração por modalidade/dia da semana) faz
  `GROUP BY dow, modalidade` **direto na tabela base**, sem join. Só depois
  do `GROUP BY` (quando já é 1 linha por combinação dow+modalidade) é que
  há um `JOIN` com `contagem_dow` — e esse join é 1:1 pela chave `dow`
  (contagem de dias daquele dia-da-semana no período), não multiplica nada.
- Dry run com 2 corridas no mesmo dia: `count(*) as ocorrencias` vira `2`,
  `sum(duracao)` vira a soma real das 2 — matematicamente correto, nenhuma
  linha é contada 2x.
- O bug de CTE mencionado no commit era sobre **escopo de `with` entre
  blocos SQL diferentes** (um `WITH ... SELECT INTO` não vê as CTEs de um
  bloco anterior já encerrado) — um erro de sintaxe/execução, não um erro
  de multiplicação de linhas. Foi corrigido **antes** do commit (via
  `migration repair --status reverted` + novo push), então o que está em
  produção desde 27/09 já é a versão corrigida.
- Essa RPC alimenta a revisão de smartwatch da Anamnese (tela nova,
  `AnamneseSelfServicePage`/`AnamneseProfissionalView.tsx`), **não** a tela
  de histórico de treinos do dashboard (`HistoricoTreinosPage`).

**Ressalva:** não testei a função rodando contra um banco real (dry run só
mental/leitura, como pedido). Se o fundador quiser 100% de certeza aqui
também, dá para rodar isso num ambiente local (`supabase db reset` + chamar
a RPC com dado sintético de 2 treinos no mesmo dia) sem nenhum risco — é
`security definer` mas só leitura.

---

## Onde "Atividades" de fato lê distância hoje

Mapeei os 2 caminhos reais de distância no app, para deixar claro que são
independentes:

1. **`atividades_fisicas_treinos`** (1 linha por treino real) — lido por
   `TreinosHistoricoRepository.buscarUltimosTreinos()`
   (`lib/features/dashboard/data/repositories/treinos_historico_repository.dart`):
   um `SELECT *, tipos_atividades_fisicas(nome_exibicao)` simples, com embed
   FK 1:1 (lookup de nome de modalidade) — não multiplica linhas. Escrito
   pelo Flutter via **upsert idempotente**:
   `onConflict: 'usuario_id,inicio_atividade'`
   (`health_sync_service.dart:1856`), batendo exatamente com a constraint
   `unique (usuario_id, inicio_atividade)` da tabela (migration
   `20260811160000`). Reprocessar os mesmos dias atualiza a mesma linha,
   nunca duplica — **por design**, confirmado no schema real.

2. **`metricas_saude_diarias.distancia_metros`** (1 linha por dia,
   distância "vencedora" já deduplicada entre fontes pela hierarquia do
   `health_sync_service.dart`) — também upsert, `onConflict:
   'usuario_id_anonimo,data_referencia'`, **um upsert por linha** (não em
   lote — bug histórico documentado no próprio código,
   `health_sync_service.dart:1122-1153`, já corrigido em agosto) com o
   valor do dia inteiro recalculado e sobrescrito a cada sync, nunca
   somado incrementalmente. Também idempotente por design.

Ambos os upserts são, por construção, seguros contra reprocessamento ou
reexecução duplicada — **o que torna qualquer explicação de "duplicação"
baseada em reexecução simples (rodar o sync 2x) difícil de sustentar**, a
menos que as 2 execuções vejam timestamps ligeiramente diferentes para o
mesmo treino real (ex.: arredondamento, fuso), escapando da chave de
conflito.

---

## Achado quantitativo — dados reais de produção vs. Garmin (ground truth)

Com autorização explícita do fundador, consultei (só `SELECT`, via
`supabase db query --linked`, nenhuma escrita) o banco de produção (conta
`atleta1000@teste.com`). Depois, o fundador conferiu 3 treinos recentes
direto no app Garmin e me passou os valores reais. Comparação direta:

| Dia | Modalidade | Garmin: distância | Garmin: tempo | Garmin: calorias | **Banco: distância** | Banco: duração | Banco: calorias | Razão distância |
|---|---|---|---|---|---|---|---|---|
| 28/09 | RUNNING | 7,91 km | 49:19 | 608 kcal | **14,616 km** | 49:18 | 608 kcal | **1,85×** |
| 03/10 | RUNNING | 10,01 km | 1:16:43 | 738 kcal | **19,509 km** | 1:16:43 | 738 kcal | **1,95×** |
| 12/10 | RUNNING | 8,6 km | 52:14 | 663 kcal | **15,219 km** | 52:12 | 663 kcal | **1,77×** |
| 05/10 | RUNNING_TREADMILL (esteira) | — | — | — | 10,029 km | 49:42 | 685 kcal | **confirmado correto pelo fundador** |

**Duração e calorias batem EXATAS com o Garmin nos 3 casos** (ao
segundo/kcal) — só a distância vem errada, e só em atividades **ao ar
livre com GPS**; a esteira (sem GPS) veio certa. Isso isola o problema com
precisão: não é um bug geral de leitura/parsing do treino (duração e
calorias usam o mesmo ponto de dados e vêm perfeitas), é especificamente
o cálculo de distância de atividades por GPS.

## Causa raiz exata (código de terceiros, não deste repositório)

Procurei no código-fonte real do pacote `health` instalado
(`health-13.3.1`, baixado no cache local do Pub,
`AppData\Local\Pub\Cache\hosted\pub.dev\health-13.3.1\android\src\main\kotlin\cachet\plugins\health\HealthDataReader.kt`).

A função `handleWorkoutData()` (linhas 581-660), que monta cada treino pra
devolver ao Flutter, faz isto para a distância (linhas 598-611):

```kotlin
// Get distance data
val distanceRequest = healthConnectClient.readRecords(
    ReadRecordsRequest(
        recordType = DistanceRecord::class,
        timeRangeFilter = TimeRangeFilter.between(
            record.startTime,
            record.endTime,
        ),
    ),
)
var totalDistance = 0.0
for (distanceRec in distanceRequest.records) {
    totalDistance += distanceRec.distance.inMeters
}
```

**Isto lê TODOS os registros `DistanceRecord` que o Health Connect tem
para aquela janela de tempo, de QUALQUER fonte/app, e soma todos — sem
filtrar por `dataOrigin`.** Se existir mais de um registro de distância
cobrindo a mesma corrida (ex.: um do relógio via Garmin Connect e outro de
qualquer outra fonte que também produza distância por GPS/localização no
mesmo intervalo), o plugin trata os dois como complementares e soma — na
prática, dobrando (ou quase) o valor real.

Por comparação, o bloco de calorias e de passos, 10-15 linhas abaixo no
mesmo arquivo, faz exatamente o mesmo tipo de soma sem filtro — mas nos 3
exemplos reais isso não causou problema, o que indica que só existe UM
registro de calorias/passos no Health Connect pra essas janelas, mas DOIS
(ou mais) registros de distância. A esteira bater certo reforça isso: sem
GPS em ambiente indoor, não há uma segunda fonte de distância concorrendo.

**Confirmei também que o nosso código Flutter nunca usa o parâmetro
`recordingMethodsToFilter`** que o pacote `health` expõe (bateria zero
ocorrência em `lib/`) — e mesmo que usássemos, ele filtra por TIPO de
registro (manual vs. automático), não por ORIGEM/app, então não teria
evitado este problema mesmo se estivesse configurado.

**Por que isso não é um bug deste repositório**: o trecho acima faz parte
do pacote `health` em si (código de terceiros, mesmo em `13.3.1`, a versão
que está em produção desde antes de 28/09 e continua até hoje — não é algo
que mudou nesta janela). O que precisa mudar pra isto ter começado
especificamente em 28/09 é o Health Connect ter passado a ter uma SEGUNDA
fonte de `DistanceRecord` pra essas janelas de GPS — algo externo ao nosso
código (outro app no celular, ou um comportamento do próprio Health
Connect/Google), que não consigo confirmar sem acesso ao device físico.
Isso é parecido, em espírito, com o achado da saga de telemetria de agosto
("`com.android.healthconnect.phone.*` competindo como pedômetro nativo") —
múltiplas fontes de dado de movimento coexistindo no mesmo Health Connect.

**Nota lateral, não relacionada a este bug**: a mesma consulta ao banco
revelou um padrão antigo e já resolvido — entre 22/07 e 12/08, várias
corridas aparecem como **linha duplicada exata** (mesmo treino, 2 linhas
idênticas na nossa tabela). Isso é anterior à introdução da constraint
`unique (usuario_id, inicio_atividade)` + upsert idempotente (migration
`20260811160000`, RELATÓRIO 20260811_0002) — **já estava resolvido antes
desta tarefa**, e é um mecanismo diferente do bug atual (que não tem
linhas duplicadas na nossa tabela — o valor já vem inflado de dentro do
plugin, numa linha só).

## Achado secundário (candidato fraco, mantido como mitigação): `workmanager` 0.9.0+3 → 0.10.10 (não revertido)

Única dependência do período 27-28/09 que **sobrevive** até hoje sem
reversão (diferente de `health`/`device_info_plus`/`file_picker`, todos
revertidos no mesmo dia):

- `546e4da`/`f434ae5` (28/09): `workmanager: ^0.9.0+3` → `^0.10.10`,
  motivado só por um aviso de build (KGP), **mantido de propósito** mesmo
  depois do revert de `health` (relatório `20260928_0003` confirma
  explicitamente: "`flutter_secure_storage`/`workmanager`/... mantidos —
  sem relação com este bug").
- Esse pacote governa `BackgroundSyncManager`
  (`lib/features/dashboard/data/services/background_sync_manager.dart`),
  que registra uma `registerPeriodicTask` (24h, nome único
  `sync_diario_wearables_unique`, `existingWorkPolicy:
  ExistingPeriodicWorkPolicy.keep`) chamando
  `HealthSyncService().sincronizarDeltaDiario()` — o mesmo método que o
  botão manual "sincronizar agora" chama em foreground.
- **Não encontrei nenhum lock/mutex/flag "já sincronizando" protegendo
  `sincronizarDeltaDiario()`** contra execução concorrente (nem entre o
  disparo em background e um toque manual do usuário no app, nem entre 2
  disparos em background).
- O relatório `20260928_0001` confirma que essa versão exigiu ajuste de um
  parâmetro novo da interface de plataforma (`foregroundServiceConfig`) no
  fake de teste — ou seja, é uma mudança de **major** na interface nativa
  do plugin, não um bump trivial de patch.

**Status desta hipótese após o achado quantitativo: rebaixada a
improvável.** Execução concorrente do sync explicaria duplicação por
LINHAS repetidas (como o bug antigo de julho/agosto) — mas confirmei (seção
acima, item 1) que não existe nenhuma linha quase-duplicada desde 28/09.
O padrão observado (1 linha só, valor ~1,8× inflado, outro caminho de
código do mesmo sync com valor normal) não é o que uma corrida duplicada
produziria. Mantenho a falta de lock como mitigação defensiva válida por
si só (ver proposta), não como explicação deste bug específico.

---

## Isolamento do ponto de falha

**Conclusão com certeza alta** (código do plugin + dados reais de
produção + confirmação direta do fundador contra o Garmin):

- **Não está na coleta Flutter** — `health_sync_service.dart` passa
  `workout.totalDistance` direto pro banco, sem nenhuma conta (linha
  1825-1826). Duração e calorias, lidas no mesmo ponto de dados, chegam
  perfeitas — confirma que a leitura/parsing do nosso lado está correta.
- **Não está no processamento SQL** — nenhum JOIN existe envolvendo
  `atividades_fisicas_treinos` em nenhuma migration.
- **Não é execução duplicada/concorrência nem linha duplicada** — a
  distância vem errada DENTRO de uma única linha; duração/calorias dessa
  MESMA linha estão certas.
- **Está no pacote `health` (terceiros)**: `HealthDataReader.kt`,
  função `handleWorkoutData()`, soma TODOS os `DistanceRecord` do Health
  Connect na janela do treino, de qualquer origem, sem filtro —
  confirmado lendo o código-fonte real da versão instalada (13.3.1).
  Afeta só GPS (outdoor), não esteira — consistente com uma 2ª fonte de
  distância por GPS coexistindo no Health Connect só nesses casos.
- **O "porquê começou em 28/09" continua sem causa 100% confirmada** —
  o trecho do plugin é código antigo, não mudou nesta janela; algo externo
  (fora deste repositório, possivelmente outro app no celular ou um
  comportamento do próprio Health Connect) passou a gerar um 2º registro
  de distância GPS pra essas janelas a partir dessa data.

## Proposta de solução (NÃO implementada — aguardando aprovação)

1. **Correção recomendada — parar de confiar em `workout.totalDistance`
   pra distância do treino, calcular a nossa própria a partir de
   `DISTANCE_DELTA`**: `_processarTreinos()` já recebe o mesmo lote de
   `points` que `_mesclarPorDia()` usa pra calcular a distância diária com
   hierarquia de fontes (dedup real, já comprovado correto nos dados
   acima). Dá pra filtrar os pontos `DISTANCE_DELTA` que caem dentro do
   intervalo `[treino.dateFrom, treino.dateTo]` (mesmo padrão já usado pra
   FC/velocidade do treino, `dentroDoIntervalo()`) e somar só a fonte
   vencedora daquele intervalo — reaproveitando a MESMA lógica de
   dedup que a métrica diária já usa, em vez de confiar no número cru que
   o plugin devolve pra sessão. Resolve na nossa ponta, sem depender de
   nenhuma correção externa (Garmin/Health Connect/plugin).
2. **Mitigação complementar — sanity check de plausibilidade**: mesmo
   depois da correção acima, logar um aviso (nunca descartar
   silenciosamente) se o pace implícito ficar abaixo de um limite
   fisiologicamente improvável (ex.: < 2,5 min/km sustentado por mais de
   10 min) — mesmo princípio já usado em outros pontos do arquivo (ex.
   `possivel_foto_de_tela`), deixando rastro visível em vez de confiar
   ciegamente em qualquer fonte.
3. **Fora do nosso controle, mas vale o fundador saber**: reportar ao
   suporte/comunidade do pacote `health` (projeto open-source,
   `cachet/flutter_health`) que `handleWorkoutData()` não filtra
   `DistanceRecord`/`TotalCaloriesBurnedRecord`/`StepsRecord` por origem —
   outros usuários do pacote com múltiplas fontes de wearable devem ter o
   mesmo problema. Não é bloqueante pra correção interna (item 1 resolve
   sem depender disso).

## Verificação técnica desta tarefa

Nenhum código alterado. Nenhum `flutter analyze`/`flutter test` necessário
(zero mudança de produção). Toda conclusão acima é rastreável via
`git log`/`git show`/leitura direta dos arquivos citados.

## Atualização — solução implementada (12/out/2026)

A correção recomendada no item 1 da "Proposta de solução" foi implementada
e verificada — ver RELATÓRIO
`20261012_0002_fix_distancia_treino_hierarquia_fontes.md`. Resumo: a
distância do treino deixou de vir de `workout.totalDistance` e agora é
recalculada a partir dos pontos `DISTANCE_DELTA`/`DISTANCE_WALKING_RUNNING`
do mesmo lote, com a mesma Hierarquia de Fontes já usada pela distância
diária — nunca soma 2 fontes. Fallback pro valor antigo do plugin só
quando não há nenhum ponto granular na janela (ex. esteira). 2 testes
novos, `flutter test` 514/514, `flutter analyze` 30 (linha de base, zero
novo). Branch `fix/bug-distancia-calculo-delta`.
