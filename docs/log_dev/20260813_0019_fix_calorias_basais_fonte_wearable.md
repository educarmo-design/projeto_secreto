# 20260813_0019_fix_calorias_basais_fonte_wearable — Correção: calorias basais só de wearable, nunca do app da balança

Log de Máquina (Regra 10.3 — append-only). Continuação do RELATÓRIO
20260813_0018: fundador reportou que `calorias_basais` só aparece na
tela em dias que também têm pesagem, e definiu que, conforme a
especificação, calorias devem vir do Garmin, não do Fitdays.

## Diagnóstico da causa raiz

Cruzando o log bruto do RELATÓRIO 20260813_0017 (30 dias): `BASAL_ENERGY_BURNED`
bruto só existia no Health Connect em `2026-07-28`, `2026-07-29`,
`2026-08-01` e `2026-08-10` — **exatamente os mesmos 4 dias que têm
`WEIGHT`**. Confirmado com o dado cru de `08-10`:

```
BASAL_ENERGY_BURNED: valor=1890.0 KILOCALORIE fonte=cn.fitdays.fitdays de=2026-08-10T09:00:24 até=2026-08-10T09:00:24
WEIGHT:               valor=80.6   KILOGRAM   fonte=cn.fitdays.fitdays de=2026-08-10T09:00:24 até=2026-08-10T09:00:24
```

Mesmo segundo exato, mesma fonte. O app da balança "Fitdays" não mede
metabolismo basal continuamente — ele **calcula** uma estimativa de TMB
por fórmula usando o peso que acabou de medir, e grava isso como um
ponto único no instante da pesagem. Levantamento de todas as fontes de
`BASAL_ENERGY_BURNED`/`ACTIVE_ENERGY_BURNED` nos 30 dias: `ACTIVE_ENERGY_BURNED`
sempre e só do Garmin; `BASAL_ENERGY_BURNED` só de `cn.fitdays.fitdays`
e `com.google.android.apps.fitness` — **o Garmin nunca reportou
`BASAL_ENERGY_BURNED` nenhuma vez nos 30 dias**. Como `aplicarMaiorFonte`
(a função que decide "maior fonte" pra calorias) não tinha nenhuma
noção de prioridade/exclusão de fonte (diferente da Hierarquia de Fontes
de passos/distância), qualquer fonte que reportasse o tipo virava
candidata — e como só a balança reportava, ela sempre "vencia" por ser a
única.

## Correção

Novo `_ehFonteValidaParaCalorias`: exclui `cn.fitdays.fitdays`
explicitamente (comentado como "balança inteligente — estimativa
pontual no instante da pesagem, não medição contínua") e reaproveita
`_ehPedometroNativo` pra também excluir as suítes de
celular/fabricante (Google Fit/Samsung Health/Apple Health) — mesmo
raciocínio: não são wearables de verdade. Aplicado como filtro antes de
alimentar `caloriasPorDiaFonte`/`caloriasBasaisPorDiaFonte` em
`_mesclarPorDia`.

Diferente da Hierarquia de Fontes de passos/distância (que aceita fonte
nativa como último recurso quando não há wearable naquele dia — ver RELATÓRIO
20260813_0018), calorias NUNCA caem para uma fonte excluída: sem
wearable reportando naquele dia, o campo fica `null`, nunca preenchido
com a estimativa de um app de balança/celular — decisão explícita do
fundador, não um comportamento "best-effort".

## Verificação

- 2 testes de regressão novos em `health_sync_service_test.dart`: dia só
  com Fitdays fica sem `calorias_basais`; dia com Fitdays E Garmin no
  mesmo dia, Garmin vence mesmo que Fitdays reporte valor maior (1890 >
  1650) — prova que não é mais "maior fonte" pra calorias, é exclusão.
- `flutter test test/features/dashboard/data/services/health_sync_service_test.dart`:
  91 testes passando (89 anteriores + 2 novos).
- `flutter test test/features/dashboard/`: 168 testes passando, sem
  regressão (inclui o teste pré-existente de "maior fonte" Garmin vs
  Google Fit — continua passando porque Garmin já era a fonte de maior
  valor nesse caso específico, mesmo resultado, razão diferente: agora é
  a única fonte válida, não a "maior" entre válidas e inválidas).
- `flutter analyze` nos dois arquivos tocados: sem issues novos.

## Não resolvido

Assim como o RELATÓRIO 20260813_0018, esta correção ainda não chegou no
device físico — precisa de rebuild + reinstalação pra confirmar
visualmente. Consequência esperada e aceita: em dias sem nenhum dado do
Garmin, `calorias_basais`/`calorias_totais` ficam ausentes da tela —
mais honesto que uma estimativa pontual da balança mascarada de dado
contínuo do dia inteiro.
