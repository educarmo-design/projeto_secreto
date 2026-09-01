# RELATÓRIO 20260901_0002 — Hotfix pós-N27: deploy pendente + quantidade 0/null + UX de porção

**Data:** 2026-09-01
**Branch:** `fix/hotfix-ui-matematica-n27` (não mesclada — ver "Estado das branches")
**Pedido:** Teste físico do fundador apontou descompasso entre backend e frontend após o N27 — "bug do sorvete" (UI mostra 20 em vez de 300), "bug do café com leite" (foto retorna quantidade 0, item devolve calculado em vez de travar), e pedidos de UX (porção em passos de 0,5, unidade visível no card).

## Achado principal: "bug do sorvete" não era bug de UI — era deploy pendente

Antes de tocar em qualquer código (Regra 2), auditei o Flutter inteiro (`ConfirmacaoPratoPage`, `ConfirmacaoPratoController`, model) atrás de qualquer teto de quantidade igual a 20 — **não existe nenhum**. Nenhum `TextField` com `maxLength`, nenhum `clamp`, nenhuma constante `20` relacionada a quantidade em lugar nenhum do Flutter.

Investigação seguinte: `npx supabase functions list` mostrou `extract-metric-photo` com `updated_at` = **26/ago/2026**. O fix do bug de escala (RELATÓRIO 20260831_0001 — exatamente o "300 gramas vira 20" relatado) e o próprio N27 (RELATÓRIO 20260830_0001) foram mesclados em `main` só em **31/ago**, cinco dias DEPOIS do último deploy real. **O fundador testou fisicamente contra a Edge Function antiga** — o código corrigido já estava em `main`, só nunca tinha ido pro ar.

**Ação:** `supabase functions deploy extract-metric-photo` rodado nesta tarefa (versão 43 → 44, confirmado via `supabase functions list`). Isso sozinho resolve o "bug do sorvete" — nenhuma mudança de código Flutter foi necessária ou seria correta pra esse sintoma específico.

**Lição de processo registrada:** todas as tarefas anteriores desta sessão (N27/N28/N14, fix de escala, higiene de chaves) verificaram com `deno check`/`deno test` locais e consideraram a tarefa "pronta" ao mesclar em `main` — mas **mesclar no git não deploya a Edge Function**. Não existe CI/CD configurado neste repositório (`.github/workflows/` não existe). A partir de agora, qualquer tarefa que altere `supabase/functions/` deve terminar com `supabase functions deploy <nome>` explícito, não só o merge — vou registrar isso como item de atenção pro board.

## Bug real encontrado: "café com leite" (quantidade 0/null da IA)

Diferente do "bug do sorvete", este É um bug de código real, ainda presente (não coberto por nenhum deploy anterior). `parseRespostaGeminiPrato` tratava campo **ausente** (`quantidade` não veio no JSON — Gemini genuinamente não reportou) e campo **presente mas inválido** (`"quantidade": 0`, negativo, ou não-numérico — Gemini respondeu mas não conseguiu decidir um número, como numa foto de "café com leite" sem contagem clara de "quantas xícaras") do MESMO jeito: os dois caíam no fallback "assume 1". Isso arbitra silenciosamente um consumo que ninguém mediu — violação direta da Regra 23.

**Correção:**
- `parseRespostaGeminiPrato`: campo ausente continua assumindo 1 (comportamento documentado, correto). Campo presente-mas-inválido agora vira `0` — uma sentinela, não mais "1".
- `calcularPrato`/`resolverComBuscaSemantica`: checam `quantidade <= 0` logo depois de casar o alimento (antes até de tentar casar a medida) e empurram o item pra `itensNaoReconhecidos` com o novo motivo `'quantidade_nao_informada'`, **enriquecido com os mesmos campos do N27** (alimento casado, macros por 100g, medidas disponíveis) — reaproveita 100% a UI de resolução manual que o N27 já construiu (botão "Resolver", escolher medida ou digitar peso). Nenhum componente novo no Flutter foi necessário pra isso — só o novo motivo no contrato + uma entrada nova no i18n.

## UX: passo de 0,5 + unidade visível no card

- `ConfirmacaoPratoController._passo`/`_quantidadeMinima`: 1 → 0,5. Os botões +/- agora avançam meia unidade por toque (0,5 é exatamente representável em ponto flutuante binário — nunca acumula erro de arredondamento, diferente de um passo como 0,1). Piso desceu de 1 pra 0,5 pelo mesmo motivo (zerar de vez continua sendo só a ação explícita de remover).
- `_formatarQuantidade` já tratava fração corretamente (`1.5`, `0.5`) — nenhuma mudança necessária ali.
- Card do item ganhou um badge pequeno com a unidade (`original.medida`) logo abaixo do nome, além da menção que já existia junto da linha de quantidade — widget estático, sem `Listenable`/`setState` novo, não adiciona rebuild (Regra 21).
- **Máscara de input manual (Regra 4) intacta**: o campo de peso manual (dialog "Resolver"/"Editar peso") usa `TextInputType.numberWithOptions(decimal: true)`, independente do passo dos botões +/- — não foi tocado, continua aceitando qualquer valor decimal digitado.

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| Deploy da Edge Function em vez de "consertar" a UI | A causa raiz não era de UI — reproduzir o sintoma como bug de Flutter teria sido um fix errado por cima de um fix que já existia |
| Checagem de quantidade inválida ANTES do casamento de medida | Mesmo se a medida bater perfeitamente, quantidade 0 não pode virar "0 kcal calculado" — é mais fundamental que o problema de medida |
| Reaproveitar 100% a UI de resolução manual do N27 (não criar tela nova) | O mecanismo (alimento casado + macros + medidas disponíveis → botão Resolver) já resolve exatamente esse tipo de lacuna, só precisava de um motivo novo |
| Passo 0,5 em vez de qualquer fração menor (0,25 etc.) | Suficiente pra cobrir os casos reais citados (meia fatia, meio copo) sem complicar a UI com granularidade que ninguém pediu |
| Testes com "2 toques = dobra" em vez de reescrever todo valor esperado | Minimiza o tamanho do diff nos testes que já verificavam a REGRA DE TRÊS (não o tamanho do passo em si); testes novos dedicados cobrem o passo de 0,5 isoladamente |

## Infra/config

Nenhuma migration. Nenhum secret novo. **Deploy real de Edge Function** (`extract-metric-photo`, v43→v44) — a única mudança de infraestrutura desta tarefa, e a mais importante.

## Entidades novas

Nenhuma. Novo `motivo: 'quantidade_nao_informada'` é um valor a mais na união de string já existente, não uma entidade.

## Desvios de spec

O pedido descrevia o "bug do sorvete" como um problema de UI Flutter ("teto de 20 no campo de quantidade"). Não encontrei esse teto — é uma Edge Function desatualizada. Not fixed a UI que não tinha esse bug; documentado aqui em vez de forçar uma mudança de código que não correspondia à causa raiz real (Regra 2).

## Problemas encontrados

- **Deploy pendente de Edge Function há duas tarefas** (N27 em 30/ago, escala em 31/ago, nenhuma delas deployada até agora) — causa raiz do "bug do sorvete" reportado. Corrigido nesta tarefa (deploy rodado).
- Nenhum outro problema novo encontrado além do já corrigido (quantidade 0/null).

## Riscos mapeados + mitigação

- **Risco de processo, novo:** sem CI/CD, "mesclado em main" e "deployado em produção" são coisas diferentes, e essa lacuna já causou pelo menos um relato de bug fantasma. Mitigação de curto prazo: checklist mental (mesclar Edge Function ⇒ deployar Edge Function, sempre); mitigação de longo prazo (fora do escopo desta tarefa): pipeline de deploy automático no merge pra `main`, quando fizer sentido pro tamanho do time.
- Nenhum risco novo introduzido pelas mudanças de código (checagem de quantidade é aditiva, não remove nenhum caminho existente; passo 0,5 é uma constante isolada, sem efeito colateral em outro lugar).

## Como o fundador testa (ACEITE)

1. **Bug do sorvete**: digitar "300 gramas de arroz" (ou qualquer alimento real do catálogo) no registro descritivo — deve mostrar 300, calorias = 3× o valor por 100g. (Já deployado; testável imediatamente.)
2. **Bug do café com leite**: fotografar algo onde a quantidade seja ambígua o bastante pra IA não decidir um número — o item deve aparecer na seção "Não reconhecidos" com botão "Resolver", não como um item calculado com "0 kcal" ou uma quantidade inventada.
3. **UX de porção**: tocar +/- num item confirmado deve andar de 0,5 em 0,5 (ex.: 1 → 1,5 → 2). O card deve mostrar a unidade (ex.: "colher de sopa") num badge visível, além da menção já existente junto da quantidade.

## Como a performance foi tratada

Badge de unidade é um `Container`/`Text` estático dentro da árvore que já existe por item — não escuta nada, não adiciona nenhum `ValueListenableBuilder`/`setState` novo, não muda o escopo de rebuild já existente (que continua sendo a tela inteira via um único `ValueListenableBuilder` — arquitetura pré-existente, não alterada nesta tarefa; um refactor pra rebuild por item seria uma melhoria real de Regra 21, mas é um escopo maior, fora de um hotfix). A checagem de quantidade inválida no backend é um `if` a mais por item, custo desprezível.

## Verificação

- `deno check` limpo. Deno: **116/116 passando** (110 + 6 novos: 2 de `parseRespostaGeminiPrato` pra sentinela 0/negativa/NaN, 2 de `calcularPrato`, 1 de `resolverComBuscaSemantica`, 1 de nível handler reproduzindo "café com leite" ponta a ponta).
- `flutter analyze`: 30 avisos pré-existentes, mesmos de sempre, nenhum novo.
- Flutter: suíte completa rodada após os ajustes — controller 31/31, page 24/24 (10 testes atualizados pro passo 0,5 + 2 novos dedicados + 1 novo pro badge de unidade).
- Deploy de `extract-metric-photo` confirmado via `supabase functions list` (v44, `updated_at` atualizado).

## Estado das branches

Trabalho em `fix/hotfix-ui-matematica-n27`, criada a partir de `main` (já incluindo N27, o fix de escala e a higiene de chaves, todos mesclados antes desta tarefa). **Não mesclada.**

**Instruções de PR:**

```
git push -u origin fix/hotfix-ui-matematica-n27
gh pr create --base main --head fix/hotfix-ui-matematica-n27 \
  --title "fix: quantidade 0/null trava item (Regra 23) + UX de porção 0,5 — bug do sorvete era deploy pendente" \
  --body "Ver docs/log_dev/20260901_0002_hotfix_ui_matematica_n27_deploy_pendente.md"
```

**Sugestão de merge:** seguro mesclar — mudança pequena e aditiva (novo motivo no contrato, novo teste, ajuste de constante de UI), zero migration, suíte inteira verde. **O deploy da Edge Function já foi feito nesta tarefa** (independente do merge do PR, já que o deploy usa o código local, não o que está publicado no GitHub) — mesclar o PR só sincroniza o histórico do git com o que já está no ar.
