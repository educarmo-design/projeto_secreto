# 20260813_0015_instrumentacao_telemetria — Modo de Diagnóstico Profundo

Log de Máquina (Regra 10.3 — append-only). Instrumentação de telemetria
pedida depois das duas auditorias anteriores (20260812_0013/20260813_0014)
não conseguirem reproduzir em código as falhas relatadas em device físico
(distância zerada/ausente em vários dias, calorias basais inconsistentes,
peso de "hoje" ignorado, treinos não aparecendo).

## Parte 1 — Proteção Extrema no Parsing

Três lugares em `health_sync_service.dart` convertiam listas inteiras de
pontos brutos com `.map(...).toList()` (ou um `for` sem try/catch) —
qualquer exceção em UM ponto lançava e derrubava a conversão do LOTE
INTEIRO, não só do ponto problemático:

1. `HealthMetricPoint.fromHealthDataPoint` — conversão do `HealthDataPoint`
   cru (pacote `health`) pro tipo interno, dentro de `_lerComPermissao`.
2. `HealthSyncResult.toPayloads()` — conversão pro `HealthPayloadModel`
   (`.round()` num `double`; `NaN`/`Infinity` lança `UnsupportedError`).
3. **`_detectarEregistrarAnomalias`** (Caixa Preta clínica) — **achado
   real, não hipotético**, confirmado escrevendo o teste ANTES da
   correção: este método chama `ponto.toPayload()` sem proteção nenhuma,
   pra CADA ponto do lote, e roda **dentro de `_lerComPermissao`, antes do
   método sequer retornar**. Um único ponto com valor `NaN`/`Infinity`
   (ex.: `STEPS`, que usa `.round()`) lançava ali, o catch externo de
   `_lerComPermissao` (RELATÓRIO 20260813_0014) tratava isso como
   "permissão negada" e o `_lerEGravar` abortava o upsert do **lote
   inteiro** — todos os dias, todos os tipos (distância, calorias basais,
   peso, treinos), mesmo os sem nenhuma relação com o ponto ruim. **Este é
   o mecanismo mais plausível pro sintoma relatado**: um ponto ruim
   isolado em qualquer lugar de um lote de 30 dias apaga o lote inteiro em
   silêncio, sem exceção visível pro fundador — só um `debugPrint`
   genérico que, até a correção anterior (20260813_0014), nem sequer
   existia.

Correção nos 3 pontos: loop explícito com try/catch por ponto/payload —
um ponto ruim é pulado e logado com `[SYNC_DIAGNOSTICO]`, os demais
(mesmo dia ou outros dias) continuam sendo processados normalmente.
Também protegido, por consistência, o loop principal de agregação em
`_mesclarPorDia` (corpo inteiro por iteração agora dentro de try/catch).

`_processarTreinos` já tinha proteção por treino desde o RELATÓRIO
20260811_0002 — não precisou de mudança.

## Parte 2 — Instrumentação (logs `[SYNC_DIAGNOSTICO]`)

Novo `_logDiagnosticoProfundo`, ligado só quando `diagnosticoProfundo:
true` é passado pra `_lerComPermissao`/`_lerEGravar` (desligado por padrão
em todo o resto do app — delta diário automático e Carga Inicial ao
conectar wearable nunca ficam mais verbosos). Imprime, por chamada:

- Os limites exatos `startTime`/`endTime` pedidos ao pacote `health`
  (`endTime` já era `DateTime.now()` puro desde sempre — nunca truncado à
  meia-noite; o log só torna isso verificável sem ler código).
- Por dia da janela: contagem de pontos por tipo (`DISTANCE_DELTA`,
  `BASAL_ENERGY_BURNED`, `WEIGHT`, `WORKOUT` e qualquer outro tipo
  presente).
- Por ponto: valor bruto, `runtimeType` do valor nativo (`rawValue.
  runtimeType`), unidade, fonte e janela `dateFrom`/`dateTo`.
- Alerta específico: se um dia tem pontos de distância mas a soma deu
  0/null, imprime o dump bruto completo desses pontos (`⚠️`), pra
  distinguir "Health Connect devolveu 0 de verdade" de "nosso código
  descartou/converteu errado".

## Parte 3 — Botão de diagnóstico

Novo método `HealthSyncService.executarDiagnosticoProfundo({dias: 30})`
— reaproveita o mesmo `_lerEGravar` de `carregarHistoricoInicial` (sync
real de 30 dias, não é só leitura) com `diagnosticoProfundo: true`. Novo
`SyncUiController.gerarDiagnosticoProfundo()` (mesmo `_executar` de
loading/sucesso/offline/erro dos outros 2 botões). Novo botão "GERAR LOG
DIAGNÓSTICO (30 DIAS)" em `historico_telemetria_page.dart`, abaixo dos 2
botões de debug já existentes ("FORÇAR SYNC HOJE"/"FORÇAR CARGA 30
DIAS"). Chaves i18n novas nos 3 idiomas (pt/en/es).

## Verificação

- `flutter analyze lib/features/dashboard`: 5 issues, baseline mantida
  (2 infos pré-existentes e não relacionados encontrados ao rodar analyze
  no diretório `test/` inteiro pela primeira vez nesta sessão — não são
  regressão desta tarefa, confirmado via `git diff`).
- `health_sync_service_test.dart`: 82 testes passando (74 pré-existentes +
  8 novos: 2 de resiliência a ponto ruim — incluindo o teste que
  **encontrou** o bug real do item 3 acima antes da correção — e 6 do
  Modo de Diagnóstico Profundo).
- `sync_ui_controller_test.dart`: +2 testes novos (`gerarDiagnosticoProfundo`).
- `historico_telemetria_page_test.dart`: +1 teste novo (botão de diagnóstico).
- `flutter test test/features/dashboard/`: 158 testes passando, sem
  regressão em nenhuma tela/serviço.
- `flutter build apk --debug`: build completo, `.apk` verificado em disco.

## Não resolvido (aguardando saída real de device físico)

O ACEITE desta tarefa pede a saída real do console `[SYNC_DIAGNOSTICO]`
rodando num aparelho físico — isso só o fundador pode gerar (rodar o app
no device, clicar no botão, colar a saída). Sem isso, a hipótese do item 3
da Parte 1 (ponto ruim isolado apagando o lote inteiro) é a mais forte
candidata a causa raiz encontrada até agora, mas segue não confirmada em
produção — só reproduzida em teste controlado.
