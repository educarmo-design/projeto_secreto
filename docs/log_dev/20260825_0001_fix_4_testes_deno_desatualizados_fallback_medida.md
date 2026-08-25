# RELATÓRIO 20260825_0001 — Corrige 4 testes Deno desatualizados (fallback de medida F46)

**Data:** 2026-08-25
**Pedido:** fundador perguntou se as 4 falhas de Deno "pré-existentes, não
relacionadas" (carregadas por vários relatórios desde 20260823_0004) estavam
mesmo resolvidas e pediu pra corrigir.

## Causa raiz — não era bug de produção, eram testes desatualizados

As 4 falhas eram sempre as mesmas: `encontrarMedida`, `calcularPrato`,
`resolverComBuscaSemantica` e o handler, todas girando em torno de "medida
não cadastrada pra aquele alimento".

Investigando a fundo: os testes esperavam o comportamento ANTIGO —
`encontrarMedida` devolvendo `null` quando a medida pedida (ex.: "xícara")
não bate com nenhuma das cadastradas pro alimento (ex.: feijão só tem "concha
média"), fazendo o item cair em `itensNaoReconhecidos` com motivo
`medida_nao_encontrada`.

Só que a função **já não funciona mais assim há tempos** — um fix documentado
no próprio código (`FIX (31/jul)`) mudou `encontrarMedida` pra NUNCA mais
devolver `null` quando o alimento tem QUALQUER medida cadastrada: cai num
fallback em camadas (primeira medida disponível → peso genérico de 100g →
peso padrão da categoria). A intenção, também documentada: "melhor usar algo
que deixar o alimento cair em não reconhecido". O código dentro de
`resolverComBuscaSemantica` até já tinha um comentário do RELATÓRIO
20260823_0004 dizendo explicitamente que esse `null` "é inalcançável na
prática" (só acontece se a medida vier como string vazia) — ou seja, o
próprio código já sabia que os testes antigos não faziam mais sentido, mas
ninguém tinha atualizado os testes.

**Nenhuma mudança de produção foi feita** (`index.ts` intacto) — só os 4
testes em `index_test.ts`, pra bater com o comportamento intencional já em
produção.

## O que mudou nos testes

- `encontrarMedida`: a asserção de feijão + "colher de sopa" agora espera o
  fallback pra "concha média" (80g, a única medida do feijão) — e prova que o
  fallback continua ESCOPADO ao alimento certo (nunca pega emprestado os 25g
  da colher de sopa do arroz).
- `calcularPrato`: o teste antigo virou **2 testes** — um cobrindo o fallback
  de verdade (medida não cadastrada mas o alimento tem outra → resolve, não
  cai em `itensNaoReconhecidos`) e um novo cobrindo o único caso onde
  `encontrarMedida` ainda devolve `null` (medida vazia).
- `resolverComBuscaSemantica`: mesma correção (1 teste vira 2, mesmo padrão).
- Handler: o teste de ponta a ponta agora confirma que "xícara" (não
  cadastrada pro feijão) entra normalmente em `itens` (fallback pra concha
  média, 80g), não em `itens_nao_reconhecidos`.

**Achado no caminho:** o campo `medida` do item calculado é o texto
ORIGINAL pedido (ex.: "xícara"), não o nome da medida do catálogo usada no
fallback (ex.: "concha média") — só o peso (`gramasEstimados`) reflete a
medida real. Corrigido nas primeiras versões das asserções novas (erro meu,
não um achado de produção) antes de fechar o teste.

## Verificação

`deno check` limpo. Suíte completa do `extract-metric-photo`:
**97/97 passou, zero falhas** — primeira vez 100% verde nesta função desde
que o rastreamento destas 4 falhas começou a ser citado (relatórios desde
20260823_0004).

Nenhum arquivo Dart tocado — suíte Flutter inalterada (427/427, confirmada
no relatório anterior, 20260824_0003).
