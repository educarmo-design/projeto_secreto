# 4 bugs da jornada de renovação da Anamnese — 3 corrigidos, 1 investigado e descartado

**Tipo:** Bugs reais no device físico (race condition, UI desatualizada) +
1 investigação que concluiu "não é bug" (pedido explícito do fundador:
"faça o diagnóstico, não altere").

## Bug 1 — Duplo envio / race condition (CORRIGIDO)

**Causa real**: `ConfirmarAnamnesePage._confirmarEEnviar` já tinha
`bool _enviando` e `onPressed: _enviando ? null : _confirmarEEnviar` —
mas a ÚNICA proteção era o rebuild do `FilledButton` desabilitado, que só
acontece no frame SEGUINTE ao `setState`. Um duplo-toque rápido (2 eventos
de ponteiro no mesmo frame, comum em telas sensíveis/dedos grandes)
chegava ANTES desse rebuild — o botão ainda via `onPressed` não-nulo e
disparava `_confirmarEEnviar` de novo, chamando
`AnamneseRepository.salvarAnamnese` 2x. A 2ª gravação batia
`duplicate key value violates unique constraint
"anamneses_atividades_dias_pkey"` (2 INSERTs de atividades pro mesmo dia/
anamnese) e, pior, já tinha criado uma 2ª linha em `anamneses` antes de
falhar nas atividades.

**Correção**: `if (_enviando) return;` **síncrono**, logo no topo da
função, ANTES de qualquer `setState`/`await` — nunca depende de um
rebuild já ter acontecido. A 2ª chamada, mesmo chegando no mesmo frame da
1ª, cai nesse guarda e retorna sem fazer nada.

**Teste novo**: simula o duplo-toque de verdade — 2 `tester.tap()` SEM
`pump()`/`pumpAndSettle()` entre eles (pra reproduzir "chegou antes do
rebuild"), com a 1ª chamada de `salvarAnamnese` deliberadamente presa num
`Completer` não resolvido — confirma que `salvarAnamnese` só é chamado 1
vez mesmo assim.

## Bug 2 — "Histórico de Avaliação" com régua de carência própria (CORRIGIDO)

**Causa real**: a MESMA divergência de 2 réguas já corrigida no
RELATÓRIO `20261101_0001` para `AnamneseSelfServicePage` — só que numa
3ª tela que eu não tinha tocado naquela tarefa.
`HistoricoAnamnesesPage._proximaRevisao` calculava
`dataPreenchimento + 30 dias` com conta própria, hardcoded, nunca olhando
`anamneses.data_validade`. Resultado relatado: Dashboard mostra "vencida",
mas o Histórico anuncia "Próxima revisão disponível em [30 dias depois do
preenchimento]" — uma régua a mais divergindo da mesma pergunta.

**Correção**: `HistoricoAnamnesesPage` passa a chamar
`AnamneseRepository.buscarDataValidadeAnamnese()` (já existia) e decidir
com a MESMA `AnamneseValidadeStatus` do Dashboard — zero cálculo próprio
de dias restando. `dataValidade == null` (sem dado real pra julgar) cai
no mesmo "disponível agora" dos níveis `atrasada`/`bloqueada`, nunca
inventa uma data.

## Bug 3 — "Histórico de Peso" não reagia à confirmação da balança (CORRIGIDO)

**Causa real**: `AnamneseSelfServicePage._confirmarSugestaoBalanca`
(botão "Usar" da sugestão lida da balança) só fazia `setState` local nos
`TextEditingController`s de Peso/%Gordura/Massa — nunca tocava em
`_historicoPeso`/`_seriePeso` (os dados da seção "Histórico de Peso",
agregados + gráfico, carregados uma única vez em `_carregar()`). A seção
abaixo ficava visualmente parada, sem reagir ao toque.

**Correção**: a função agora é `async` — depois de preencher os campos,
chama `buscarHistoricoPeso()`/`buscarSeriePeso()` de novo (as mesmas
chamadas que `_carregar()` já fazia) e atualiza `_historicoPeso`/
`_seriePeso` num único `setState`.

## Bug 4 — "replica a string da atividade" — INVESTIGADO, NÃO É BUG DE CÓDIGO

A tarefa pediu pra inspecionar "o serviço que agrega os dados do
HealthKit/GoogleFit" e "corrigir o loop de agrupamento por dia da semana
e a contagem de semanas distintas". Investigação completa, SEM alterar
nada (pedido explícito do fundador: "faça o diagnóstico, não altere"):

### O que foi auditado, e está correto

- **SQL** (`processar_medias_smartwatch`, as 2 versões existentes no
  repositório): agrupa corretamente por `(dow, modalidade)`
  (`group by 1, 2`), com o denominador `semanas_do_periodo` calculado por
  `dow` via uma CTE própria (`contagem_dow`, `count(*)` de dias do
  período que caem naquele dia da semana) — cada combinação
  (dia-da-semana, modalidade) tem sua própria contagem, nunca
  compartilhada.
- **Dart** (`AtividadeSmartwatch.fromJson`, `MediasSmartwatchResultado.fromJson`,
  `_RevisaoSmartwatchPageState`, `i18n.tr()`): cada `AtividadeSmartwatch`
  é um objeto distinto, construído a partir do seu próprio item de JSON;
  `i18n.tr()` não tem cache nenhum (substitui `{{params}}` igual a cada
  chamada); nenhum laço de construção reutiliza a mesma referência entre
  iterações.

**Novo teste de regressão** (`revisao_smartwatch_page_test.dart`, arquivo
que não existia antes desta tarefa): monta um resultado com 2 modalidades
em dias diferentes, `ocorrencias`/`semanas` DIFERENTES, confirma que a
tela mostra os 2 textos distintos — trava a ausência do bug, pega uma
regressão real se um dia for introduzida.

### A explicação real — hipótese do fundador, confirmada por leitura de código

O fundador apontou, depois da investigação inicial: "o erro... está
ligado diretamente ao dia da última anamnese". **Confirmado**:
`iniciar_rascunho_anamnese` (RPC que calcula a janela de tempo da revisão
do smartwatch, chamada pelo botão "Buscar dados do relógio") define:

```sql
if v_anamnese_anterior_id is null then
  v_janela_inicio := now() - interval '30 days';
else
  v_janela_inicio := v_data_anterior;  -- data_preenchimento da anamnese MAIS RECENTE
end if;
v_janela_fim := now();
```

Na jornada de teste desta tarefa (Time Travel + Bug 1 testado
imediatamente antes, no MESMO dia), a anamnese "mais recente" no banco
tem `data_preenchimento` de HOJE — a janela `[v_janela_inicio,
v_janela_fim]` colapsa pra um período de 1-2 dias, não as semanas/meses
de uso normal. Com uma janela tão curta:

- `contagem_dow` (o denominador "semanas do período") vira `1` pra
  qualquer dia-da-semana presente — matematicamente correto, só que sem
  variação nenhuma pra mostrar.
- Se o device/relógio sincronizou 2 modalidades diferentes NO MESMO dia
  (dentro dessa janela de 1-2 dias), as duas caem no MESMO `dow`, com o
  MESMO denominador (`1`), e muito provavelmente a MESMA contagem de
  ocorrências (`1` sessão cada) — produzindo, por coincidência
  matemática genuína, a MESMA string "1 ocorrência em 1 semana do
  período" pra atividades diferentes.

**Não é bug de agrupamento** — é o resultado correto de uma janela
artificialmente curta, causada pela própria mecânica de teste (anamnese
"mais recente" = hoje, por Time Travel + re-preenchimento no mesmo dia).
Em uso real (anamneses espaçadas pelo ciclo normal de 30 dias), a janela
teria semanas reais de variação e este "achatamento" nunca apareceria.
**Nenhuma linha de código foi alterada para este item**, por pedido
explícito do fundador.

## Verificação

- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: inclui os testes novos/reescritos de
  `confirmar_anamnese_page_test.dart` (+1, duplo-toque),
  `historico_anamneses_page_test.dart` (régua unificada),
  `anamnese_self_service_page_test.dart` (sem mudança de teste pro Bug 3 —
  comportamento visual, cobertura por inspeção manual do fluxo) e o novo
  `revisao_smartwatch_page_test.dart` (+1, prova da ausência do Bug 4).

## Banco de dados

Nenhuma migration nova, nenhuma RPC nova — Restrição da tarefa ("Foco
100% client-side") cumprida; o Bug 4 não precisou de alteração nenhuma
(nem client, nem server).

Branch `fix/bugs-anamnese-ui-race-condition`, a partir de `main`.
