# 20260819_0020_verificacao_device_fixes_0018_0019_e_achado_total_calories — Verificação em device físico dos fixes 0018/0019 + achado: `TOTAL_CALORIES_BURNED` nunca foi solicitado

Log de Máquina (Regra 10.3 — append-only). Continuação dos RELATÓRIOS
20260813_0018 (Hierarquia de Fontes — distância) e 20260813_0019
(calorias basais nunca do Fitdays), que ficaram sem chegar no device
físico. Sessão de hoje fecha essa pendência e abre uma nova frente.

## 1. Rebuild + instalação no device físico

`flutter pub get` → `flutter analyze` (limpo, só lints pré-existentes)
→ `flutter build apk --debug` (`exit code 0`) → `flutter install` no
Samsung SM S942B do fundador (conectado via ADB wireless,
`10.10.6.68:41043`). Primeira vez que os fixes 0018/0019 rodam em
device real.

## 2. Verificação via banco (service role, só leitura/leitura+delete controlado)

Sem MCP de banco disponível neste ambiente: usada a
`SUPABASE_SERVICE_ROLE_KEY` já presente em `web_painel/.env.local`
(gitignored) para consultar/alterar `metricas_saude_diarias` direto via
PostgREST (`Invoke-RestMethod`), resolvendo `atleta1000@teste.com` →
UUID pela RPC `resolver_usuario_id_por_email` (já existente,
`security definer`, só `service_role`).

### 2.1 Achado intermediário: botão "FORÇAR CARGA 30 DIAS" não gravou nada

Primeira rodada: fundador apertou o botão, mas todas as 31 linhas no
banco continuaram com `atualizado_em` de dias anteriores — nada foi
escrito. Cruzando com o logcat: a leitura bruta (Modo Raio-X) terminou
às 17:40:46, e ~13 min depois o log do sistema Android registra
`GMR: bg : <pid> br.com.atleta.app` — o app foi para background antes
da gravação (`_enviarLinhas`, loop sequencial de upsert, um
`await` de tela sem `WorkManager`/foreground service) terminar.
Registrado como achado operacional (não um bug de lógica): os botões
de debug da tela de Histórico de Telemetria exigem o app em primeiro
plano, tela ligada, até o snackbar de confirmação aparecer — do
contrário a gravação trava pela metade, silenciosamente, sem log de
erro nem crash.

### 2.2 Confirmação real dos fixes

A pedido do fundador, `metricas_saude_diarias` do `atleta1000` foi
**zerada** (41 linhas apagadas, DELETE por `usuario_id_anonimo`, sem
FK de nenhuma outra tabela apontando pra ela) e recarregada do zero
via "FORÇAR CARGA 30 DIAS" com o app em primeiro plano o tempo todo.
Resultado, comparando banco antes/depois:

| Dia | `calorias_basais` ANTES (linha pré-fix) | `calorias_basais` DEPOIS (recarga limpa) |
|---|---|---|
| 2026-07-28 | 1897,00 (estimativa Fitdays) | `null` |
| 2026-07-29 | 1884,00 | `null` |
| 2026-08-01 | 1694,75 | `null` |
| 2026-08-10 | 1890,00 | `null` |
| 2026-08-13 | 1876,00 | `null` |
| 2026-08-14 | 1874,00 | `null` |
| 2026-08-17 | 1897,00 | `null` |

**Fix 0019 confirmado**: nunca mais cai pra estimativa do Fitdays.
**Fix 0018 confirmado**: relatório de diagnóstico dos 31 dias, zero
avisos `⚠️` de distância zerada, fonte vencedora sempre
`com.garmin.android.apps.connectmobile` mesmo com o pedômetro nativo
do Health Connect (`com.android.healthconnect.phone.*`) presente todo
dia com STEPS.

## 3. Divergência de passos (15/08, 16/08) vs app do Garmin — decisão do fundador: manter como está

Fundador reportou passos do app do Garmin divergentes do "sistema" em
2 de 6 dias comparados manualmente. Investigado pós-recarga limpa: os
valores no banco (`4876`/`3451`) são idênticos antes e depois do
zera-e-recarrega, com `com.garmin.android.apps.connectmobile` como
fonte vencedora corretamente identificada nos dois dias — não é bug da
Hierarquia de Fontes (0018). É o Health Connect tendo, no momento da
leitura, um total diferente do que o app do Garmin mostra depois
(provável atualização tardia do lado do Garmin, fora do nosso
controle). **Decisão do fundador: deixar como está**, não é uma
correção deste projeto.

## 4. Achado novo: `HealthDataType.TOTAL_CALORIES_BURNED` nunca foi solicitado

Fundador reportou que o app do Garmin mostra "Repouso" + "Ativa" =
Total todo dia (não só em dias com pesagem ou atividade), e que a
permissão do Android confirma que o Garmin tem autorização pra
gravar tanto "calorias ativas queimadas" quanto **"calorias totais
queimadas"**. Investigação no código confirma a suspeita:

- `_tiposSuportados` (`health_sync_service.dart`) pede
  `ACTIVE_ENERGY_BURNED` e `BASAL_ENERGY_BURNED`, mas **nunca**
  `HealthDataType.TOTAL_CALORIES_BURNED`.
- `AndroidManifest.xml` declara `READ_ACTIVE_CALORIES_BURNED` e
  `READ_BASAL_METABOLIC_RATE`, mas **nunca**
  `READ_TOTAL_CALORIES_BURNED`.
- Confirmado no source do pacote `health` 13.3.1
  (`android/.../HealthConstants.kt`): `TOTAL_CALORIES_BURNED` existe
  como tipo de primeira classe, mapeado 1:1 pro
  `TotalCaloriesBurnedRecord` nativo do Health Connect — um tipo de
  registro **distinto** de `ActiveCaloriesBurnedRecord` (só cobre
  janelas de atividade/treino, por isso só aparece em dias com
  exercício) e de `BasalMetabolicRateRecord` (que o Garmin, confirmado
  no RELATÓRIO 20260813_0019 e de novo hoje, nunca grava).

Hipótese forte, ainda não verificada em device: o Garmin publica
`TotalCaloriesBurnedRecord` continuamente (o número "Repouso + Ativa"
que aparece na UI do app dele), e nosso pipeline simplesmente nunca lê
esse tipo — daí calorias só aparecerem em dias com atividade
(`ACTIVE_ENERGY_BURNED`, correto) e nunca de forma contínua.

## Não resolvido / próximo passo

`TOTAL_CALORIES_BURNED` não foi implementado nesta tarefa — é uma
mudança de escopo maior que rebuild+verificação (nova permissão
Android, novo tipo lido, e uma decisão de produto sobre como ele
interage com `calorias_ativas`/`calorias_basais`/`calorias_totais`
já existentes em `metricas_saude_diarias`: substituir, complementar, ou
servir de fonte pra derivar basal = total − ativa quando presente).
Fica registrado como candidato prioritário da próxima tarefa,
pendente de decisão do fundador sobre o desenho antes de implementar.
