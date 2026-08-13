# 20260812_0013_fix_distancias — Investigação: distância sumindo em dias específicos

Log de Máquina (Regra 10.3 — append-only). Investigação completa (banco +
Flutter, sincronização + UI) do sintoma reportado: distância não aparece no
app para `atleta1000@teste.com` em 12/08, 11/08, 05/08, 29/07 e 26/07.

## Auditoria de banco (leitura real)

Consulta em `metricas_saude_diarias` (join com `auth.users` por email) para
as 5 datas pedidas, via `npx supabase db query --linked`:

- Nas 5 datas, `distancia_metros IS NULL` — confirmado, não é ilusão de UI
  nem confusão "0 vs null". `passos` está preenchido normalmente nesses
  mesmos dias (ex.: 8.000–12.000 passos), então não é "dia sem dados
  nenhum" — é especificamente a distância que falta.
- Ampliando a consulta para os últimos 34 dias do usuário: o mesmo padrão
  (`passos` presente, `distancia_metros` nulo) aparece em **11 dias**, não
  só os 5 reportados — sem correlação com dia da semana nem com volume de
  passos. Isso descarta qualquer causa pontual/um-dia-só.
- `atividades_fisicas_treinos` para as mesmas 5 datas: 0 linhas. Não há
  distância de treino (GPS) sendo ignorada por engano — não é esse o
  caminho de dado que falta.

## Auditoria Flutter — Sincronização (`health_sync_service.dart`)

- `HealthDataType.DISTANCE_WALKING_RUNNING` e `HealthDataType.DISTANCE_DELTA`
  **estão** na lista de tipos pedidos (`_tiposSuportados`) e a permissão é
  solicitada normalmente junto com todos os outros tipos — não há tipo
  faltando na requisição.
- Bucketização por dia: `distancia_metros` passa pela **mesma** função
  `_dataOnly` (mesma linha de código, mesmo loop) que `passos` usa dentro
  de `_mesclarPorDia`. Como `passos` nunca falha nesses dias, um bug de
  fuso/bucketing específico de distância não é plausível — o código trata
  os dois campos de forma idêntica e simétrica.
- Conversão de unidade: distância é carregada como `double`, em metros, sem
  nenhum arredondamento/truncamento na cadeia
  `HealthMetricPoint.toPayload()` → `HealthPayloadModel` (diferente de
  `passos`/`fc_repouso`, que usam `.round()` — mas isso não é bug, é
  intencional, e não há `int`/`double` quebrando nada na distância).
- "Fonte Vencedora" (Hierarquia de Fontes, RELATÓRIO 20260810_0007): passos
  e distância do dia vêm sempre da MESMA fonte vencedora — não achei
  nenhuma divergência aí. Testado também: ratio metro/passo nos dias que
  TÊM distância fica em ~0,8–1,0 m/passo (fisiologicamente normal), o que
  descarta double-counting por pedir `DISTANCE_WALKING_RUNNING` e
  `DISTANCE_DELTA` juntos.
- **Nenhum bug de aplicação foi encontrado** que explique a ausência
  especificamente da distância. A hipótese mais plausível e não
  descartável sem um device físico: a consulta única e combinada
  (`getHealthDataFromTypes` pedindo ~20 tipos de uma vez, incluindo
  `DISTANCE_DELTA` — tipicamente o tipo com MAIS registros por dia, mais
  granular que passos) pode sofrer um corte silencioso de paginação/limite
  no Health Connect ou no pacote `health`, sem lançar exceção. Não é
  reproduzível lendo código. A outra hipótese, igualmente plausível e
  totalmente fora do nosso controle: o Garmin genuinamente não gerou
  amostra de distância nesses dias específicos (GPS desligado, atividade
  indoor, etc.) — o dado nunca existiu no Health Connect para ser lido.

## Auditoria Flutter — UI (`historico_telemetria_page.dart`)

- O chip de "Distância" só some quando o valor subjacente é genuinamente
  `null` — segue a mesma convenção já usada em todo o app ("ausente ≠
  zero"), a mesma usada para IMC, peso, etc. **Não há bug de UI**: não
  existe nenhum `if (distancia == null)` escondendo o componente de forma
  incorreta quando o dado existe.

## Correção aplicada

Como não foi possível confirmar com certeza qual das duas hipóteses
externas é a real (ausência genuína no Health Connect vs. corte silencioso
da leitura combinada de ~20 tipos), e não há nenhum bug de aplicação para
corrigir, foi implementada uma mitigação defensiva, estritamente aditiva e
com risco zero de regressão: `_preencherDistanciaFaltante`, nova etapa
best-effort dentro de `_lerEGravar` (roda depois do sync principal já ter
terminado com sucesso):

- Identifica, dentre as linhas do lote, os dias que têm `passos` mas
  **não** têm `distancia_metros`.
- Se houver algum, faz **uma segunda leitura**, estreita, pedindo só
  `DISTANCE_WALKING_RUNNING`/`DISTANCE_DELTA` na mesma janela — reutiliza
  `_lerComPermissao` como está, sem modificá-la.
- Preenche `distancia_metros` **apenas** nos dias que ficaram faltando —
  nunca sobrescreve um dia que a leitura combinada já resolveu, então não
  há risco de contar a mesma distância duas vezes.
- Qualquer falha nessa segunda leitura (rede, permissão) é capturada e
  ignorada (`try/catch` com `debugPrint`) — nunca derruba o resultado do
  sync principal, que já terminou antes dela rodar.

## Verificação

- `flutter analyze lib/features/dashboard`: 5 issues, todas pré-existentes
  e sem relação com este arquivo (baseline mantida).
- `flutter test test/features/dashboard/data/services/health_sync_service_test.dart`:
  78 testes passando (73 pré-existentes + 5 novos cobrindo
  `_preencherDistanciaFaltante`: preenche quando a leitura estreita acha
  dado; não quebra quando a leitura estreita também vem vazia; NÃO dispara
  a segunda leitura quando a combinada já resolveu tudo; não dispara
  quando não há `passos` no dia; exceção na leitura estreita é engolida
  sem derrubar o sync).
- `flutter test test/features/dashboard/`: 145 testes passando (suíte
  completa do módulo, sem regressão em nenhuma outra tela/serviço).
- `flutter build apk --debug`: build completo, `.apk` verificado em disco.

## Não resolvido (fora do alcance de uma correção de código)

Os 11 dias com `distancia_metros` nulo no banco (incluindo os 5
reportados) **permanecem nulos** — esta correção é para o **próximo sync**
em diante, como o próprio ACEITE da tarefa previu ("ou o próximo sync
trará o dado correto"). Não há como popular retroativamente um dado que o
Health Connect não tem mais disponível para reler hoje.
