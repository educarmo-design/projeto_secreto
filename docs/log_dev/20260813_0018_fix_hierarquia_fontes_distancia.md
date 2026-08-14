# 20260813_0018_fix_hierarquia_fontes_distancia — Correção da causa-raiz: pedômetro nativo do Health Connect não reconhecido

Log de Máquina (Regra 10.3 — append-only). Continuação do RELATÓRIO
20260813_0017: fundador reportou que a tela ainda não apresentava
distância mesmo depois do diagnóstico rodar no device físico.

## Diagnóstico da causa raiz

Cruzando o log bruto do RELATÓRIO 20260813_0017 (dia `2026-08-11`) com o
código da Hierarquia de Fontes (`_mesclarPorDia`): o dia teve `STEPS`
vindo de duas fontes — `com.garmin.android.apps.connectmobile` (Garmin,
que também reportou `DISTANCE_DELTA: 2854m` naquele dia) e
`com.android.healthconnect.phone.j2a624ede62c5300086a4c5d757082ec3` (o
próprio Health Connect contando passos pelo acelerômetro do aparelho,
sem nenhum app terceiro envolvido — hash gerado por instalação).

`_pedometrosNativos` era uma lista EXATA com só 3 entradas (Google Fit,
Samsung Health, Apple Health) — essa fonte do Health Connect não batia
com nenhuma, então entrava em prioridade ALTA (mesmo nível de um
wearable de verdade) na "Fonte Vencedora". Se ela tivesse mais passos
que o Garmin num dia específico, ela vencia o desempate — e como nunca
reporta `DISTANCE_DELTA`/`DISTANCE_WALKING_RUNNING`, a distância real do
Garmin daquele dia era descartada em silêncio, mesmo com o dado bruto
presente no Health Connect (confirmado pelo diagnóstico de
20260813_0017).

Achado independente da hipótese de "atraso de sincronização do Garmin"
já registrada (RELATÓRIOs 20260812_0013/20260813_0016) — esta é uma
causa determinística de código, não uma race condition externa.

## Correção

`_ehPedometroNativo` agora também casa por `startsWith` contra uma nova
lista `_prefixosPedometrosNativos` (prefixo, não lista exata — o hash
`com.android.healthconnect.phone.<hash>` muda por device/instalação,
não dá pra cadastrar nominalmente). Único prefixo adicionado por agora:
`com.android.healthconnect.phone.`.

Teste de regressão novo em
`health_sync_service_test.dart` (grupo "Hierarquia de Fontes"): Garmin
com MENOS passos brutos mas COM distância vence a fonte com MAIS passos
e SEM distância — confirma que a distância do Garmin não é mais
descartada.

## Verificação

- `flutter test test/features/dashboard/data/services/health_sync_service_test.dart`:
  89 testes passando (88 anteriores + 1 novo).
- `flutter test test/features/dashboard/`: 166 testes passando, sem
  regressão.
- `flutter analyze` nos dois arquivos tocados: sem issues novos.

## Não resolvido

Esta correção ainda não foi para o device físico (só existe no
repositório/git até este commit) — precisa de rebuild + reinstalação do
app pra o fundador confirmar visualmente que `2026-08-11`/`2026-08-12`
passam a mostrar distância. `git push`/PR sozinho NÃO tem nenhum efeito
no app já instalado no celular — só publica o código no remoto.
