# 20260813_0016_fix_volume_diagnostico — Correção: relatório de diagnóstico não terminava de imprimir

Log de Máquina (Regra 10.3 — append-only). Fundador rodou o botão "GERAR
LOG DIAGNÓSTICO (30 DIAS)" (RELATÓRIO 20260813_0015) num device físico e
reportou "não apareceu nada na tela" — investigação a seguir.

## Diagnóstico da causa raiz

Sem acesso ao terminal do `flutter run` do fundador, usei `adb logcat -d`
(device já conectado via wireless debugging) pra ler o buffer real do
Android direto daqui, sem depender do terminal de ninguém. Achados:

- O relatório **rodou de verdade** — 41.446 pontos brutos convertidos com
  sucesso na janela de 30 dias (`2026-07-14` a `2026-08-13`).
- **`HEART_RATE` sozinho respondeu por 23.437 desses pontos** (leitura
  contínua do Garmin, a cada 1-2 minutos — até 956 leituras num único
  dia). Sono granular (estágios) e HRV também contribuem bastante.
- O relatório imprimia detalhe ponto a ponto de **todo** tipo, sem
  exceção — inclusive HEART_RATE. `debugPrint` tem um limitador de taxa
  embutido (existe pra não afogar o `adb logcat`/Android Runtime).
  Resultado real, medido pelos timestamps do próprio log: **33+ minutos
  pra imprimir 26 dos 30 dias**, e ainda não tinha terminado quando
  capturei o buffer. Na prática, "não apareceu nada" — a saída existe,
  mas leva tempo demais pra alguém perceber ou esperar.
- **Nenhum alerta `⚠️` de distância zerada disparou** nos 26 dias
  capturados (`07-14` a `08-09`) — todo dia teve pelo menos 2 pontos de
  `DISTANCE_DELTA` com soma > 0, incluindo `2026-07-26` e `2026-07-29`
  (2 das 5 datas originalmente reportadas como problemáticas no
  RELATÓRIO 20260812_0013). Achado interessante, não conclusivo: o
  banco tinha `distancia_metros IS NULL` pra essas duas datas na época
  daquela auditoria, mas o Health Connect TEM o dado agora — consistente
  com a hipótese já registrada de "o Garmin sincroniza pro Health Connect
  com atraso" (dado ausente no momento do sync original, preenchido
  depois). Os dias mais recentes e mais relevantes pro sintoma relatado
  (`08-10` a `08-13`) não chegaram a ser capturados — ainda estavam na
  fila de impressão quando o buffer foi lido.

## Correção

`_logDiagnosticoProfundo`: tipos de leitura CONTÍNUA/alta-frequência
(`HEART_RATE`, `HEART_RATE_VARIABILITY_SDNN`/`RMSSD`, os 4 estágios de
sono) agora imprimem **só a contagem** por dia, nunca o detalhe ponto a
ponto — nenhum deles é um dos 4 sinais do pedido original (distância/
calorias basais/peso/treinos), então o detalhe nunca ajudava o
diagnóstico, só afogava as linhas que importam. Para os demais tipos
(baixa frequência em qualquer cenário real — no máximo algumas dezenas de
pontos/dia), o detalhe completo é mantido, agora com um teto de
segurança de 50 pontos detalhados por tipo/dia (com "... e mais N
omitido(s)" pro resto) — proteção contra qualquer tipo futuro que
surpreenda com volume alto sem estar na lista de alta frequência.

## Verificação

- `flutter analyze lib/features/dashboard`: sem issues novos.
- `health_sync_service_test.dart`: 84 testes passando (82 anteriores + 2
  novos — HEART_RATE com 200 pontos simulados só imprime a contagem;
  teto de segurança com 70 pontos de WEIGHT detalha 50 e resume 20).
- `flutter test test/features/dashboard/`: 160 testes passando, sem
  regressão.
- `flutter build apk --debug`: build completo, `.apk` verificado em disco.

## Não resolvido

Ainda não há uma captura COMPLETA dos 30 dias (a mais recente, incluindo
`08-10` a `08-13`, os dias mais próximos do sintoma relatado) — precisa
de uma nova rodada do botão, agora rápida o bastante pra terminar de
imprimir. O achado de `07-26`/`07-29` já terem distância no Health
Connect hoje é um indício a favor de "atraso de sincronização do Garmin",
mas não fecha a investigação sozinho.
