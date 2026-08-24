# 20260823_0004_correcao_catalogo_alimentos_e_categoria_consumo — Curadoria em massa do catálogo TACO + fix do achado categoria_consumo + reformulação AdminAlimentos.tsx

Log de Máquina (Regra 10.3 — append-only). Modo autônomo (autorização
ampla do fundador). Continuação direta das investigações 20260823_0001/
0003 — correção completa do achado "categoria_consumo nunca chega no
Flutter" + pedido explícito de curadoria em massa do catálogo de
alimentos.

## Entendimento confirmado com o fundador antes de começar

3 decisões perguntadas e confirmadas (todas as recomendadas):
1. Curadoria dos 637 alimentos via IA em lote (Gemini), com
   `revisao_necessaria` marcado quando a própria IA reportar baixa
   confiança.
2. Apagar as 266 medidas caseiras genéricas existentes (aplicadas
   cegamente a todo alimento por `seed_taco_completa.ts`) e regenerar
   do zero para os 637, de forma consistente por alimento.
3. Manter o comportamento atual da UI condicional em
   `ConfirmacaoPratoPage` (só aparece quando a quantidade é estimativa)
   — só corrigir a PROPAGAÇÃO do dado, não a regra de quando mostrar.

## 1. Migration — campos de revisão humana

`20260823100000_revisao_alimentos_e_medidas_caseiras.sql` — novas
colunas `revisao_necessaria boolean not null default false` +
`observacao_revisao text` em `alimentos_referencia` E em
`alimentos_medidas_caseiras` (o pedido do fundador cobria as duas
tabelas separadamente), com índice parcial em cada (`where
revisao_necessaria = true`, já que a maioria das linhas não precisa de
revisão). Aplicada no banco remoto.

## 2. Curadoria em massa do catálogo (script novo, Gemini)

Estado real encontrado ANTES desta tarefa (investigado, não presumido):

| Métrica | Antes | Depois |
|---|---|---|
| `aliases` vazio | 594/637 | **0/637** |
| `categoria_consumo`/`unidade_medida_padrao` nulos | 620/637 | **0/637** |
| Alimentos com alguma medida caseira | 38/637 (genéricas, sem sentido pra muitos) | **637/637** |
| Total de linhas em `alimentos_medidas_caseiras` | 270 | **1.056** |
| Marcados `revisao_necessaria=true` (alimento) | — | 9 |
| Marcados `revisao_necessaria=true` (medida) | — | 12 |

Novo script `web_painel/scripts/curar_catalogo_alimentos_ia.ts`
(`npm run curar:catalogo-alimentos`): apaga as medidas caseiras
existentes, busca os 637 alimentos, e em lotes de 15 (43 chamadas)
pede ao Gemini (`gemini-flash-lite-latest` — `gemini-flash-latest`
estava com HTTP 503 de sobrecarga no momento da execução, trocado via
`GEMINI_MODEL_CURADORIA`) uma classificação completa por alimento:
aliases reais, `categoria_consumo`, `unidade_medida_padrao`,
`medida_padrao_nome`/`qtd`, 1-3 medidas caseiras REALISTAS pra aquele
alimento específico (não uma lista genérica), confiança 0-1 e
observação. Confiança < 0.6 → `revisao_necessaria=true` +
`observacao_revisao`. Validação defensiva de cada item da resposta
(Regra 0.15 — nunca confia cego no formato da IA): item malformado ou
lote inteiro ilegível cai num fallback seguro (peso_livre, 100g) e
também vai marcado pra revisão — nunca fica null nem quebra a corrida
inteira por causa de 1 item.

Rodado contra o banco remoto real: **637/637 processados, 0 falhas
técnicas, 9 alimentos + 12 medidas marcados para revisão humana** (ex.:
"Leite, de vaca, integral" — dados nutricionais zerados na base de
origem; "Porquinho, cru" — nome ambíguo de espécie de peixe;
"Feijão, roxo, cru" — alimento cru, raramente fotografado sem preparo).

Conferido manualmente contra os exemplos que o fundador deu: azeitona →
`unidade`, 3g/unidade (+ colher de sopa, 15g); presunto → `fatia`,
15-20g; coxinha → `unidade`, 30-160g (pequena/média/grande) — exatamente
o padrão pedido, nada de lista genérica.

## 3. Fix do achado — categoria_consumo agora chega no Flutter

`supabase/functions/extract-metric-photo/index.ts`:
- `ItemPratoCalculado` ganhou os 4 campos (`categoriaConsumo`/
  `unidadeMedidaPadrao`/`medidaPadraoNome`/`medidaPadraoQtd`) que antes
  eram lidos do catálogo só pra escolher o TEXTO do fallback e depois
  descartados — nunca chegavam ao objeto de retorno.
- `calcularItem` agora copia esses 4 campos de `params.alimento` pro
  item calculado (sempre que presentes, não só quando `quantidadeEstimada`).
- A resposta HTTP final (`itens: itensFinais.map(...)`) agora inclui
  `categoria_consumo`/`unidade_medida_padrao`/`medida_padrao_nome`/
  `medida_padrao_qtd` — as mesmas chaves que `ItemPratoExtraidoModel.
  fromJson` (Flutter) já sabia ler desde sempre, só nunca recebia.
- Comportamento de QUANDO mostrar a UI especializada em
  `ConfirmacaoPratoPage` **não mudou** (decisão confirmada com o
  fundador) — continua atrelado a `quantidadeEstimada`. A diferença é
  que agora, quando esse caso acontece, `categoriaConsumo` vem
  preenchido de verdade e a UI consegue diferenciar líquido/quente/
  unidade/fatia em vez de cair sempre no fallback genérico.
- Deployado: `supabase functions deploy extract-metric-photo`.

**Achados extras ao rodar `deno check` de verdade nesta função (nunca
tinha sido rodado limpo antes, aparentemente)**: `LinhaAlimentoBruta`
(tipo da linha bruta lida do banco) não declarava
`categoria_consumo`/`unidade_medida_padrao`/`medida_padrao_nome`/
`medida_padrao_qtd` mesmo a query já selecionando essas colunas desde
a migration `20260802120000` — corrigido (achado técnico, não afeta
comportamento em runtime, só o type-check). E um guard de null
ausente em `resolverComBuscaSemantica` (`encontrarMedida` pode
retornar `null` em teoria, o código assumia que não) — corrigido com
o mesmo padrão de tratamento já usado no branch léxico
(`itens_nao_reconhecidos`).

## 4. Reformulação de `AdminAlimentos.tsx` (Painel React)

Layout anterior: modal único, sem os 4 campos de categorização, sem
filtro de revisão (a estrutura de tipos `database.ts` nem sequer
conhecia essas colunas — por isso a tela nunca as expôs, confirmando o
achado da investigação 20260823_0003).

Reescrita completa: lista + detalhe (mesma tela, "completo
funcionalmente, cru visualmente").
- **Lista (esquerda)**: busca por nome + checkbox "Mostrar só
  alimentos que precisam de revisão" (filtra `revisao_necessaria=true`
  no servidor); cada linha mostra um selo "Revisão" quando aplicável.
- **Detalhe (direita)**: dois blocos INDEPENDENTES, cada um com seu
  próprio CRUD (pedido explícito do fundador: "manutenção separada"):
  - `AlimentoDetalhe` (topo) — dados TACO/USDA completos: nome,
    aliases, fonte, 4 macros, categoria de consumo (select com as 5
    opções), unidade padrão (g/ml), rótulo/quantidade da medida
    padrão, e o bloco de revisão (checkbox + observação, só editável
    quando marcado). Salvar/Remover/Criar.
  - `MedidasCaseirasPanel` (embaixo) — lista as medidas caseiras DO
    alimento selecionado, com seu PRÓPRIO checkbox "Só as que precisam
    de revisão", edição inline por linha (medida/gramas/revisão/
    observação), adicionar nova, remover.
- `web_painel/src/core/types/database.ts` — os tipos de
  `alimentos_referencia`/`alimentos_medidas_caseiras` (mantidos à mão
  nesse arquivo, sem geração automática) ganharam as 6 colunas que
  faltavam — causa raiz real de por que a tela antiga nunca as tinha.

## Verificação (feita só ao final, por pedido do fundador — "otimizar a execução")

- **Deno** (`extract-metric-photo`): `deno check` limpo (2 gaps de tipo
  pré-existentes corrigidos, ver seção 3). `deno test`: 80/84 passando
  — as outras 4 são **falhas pré-existentes confirmadas via `git
  worktree` isolado do HEAD antes desta tarefa** (mesma técnica já
  documentada no RELATÓRIO 20260821_0002): `encontrarMedida` tem um
  fallback "usar a primeira medida disponível" (adicionado 31/jul) que
  4 testes antigos nunca foram atualizados pra refletir — não
  relacionado a esta tarefa, não mexido.
- **Flutter**: `flutter analyze` limpo (mesmos 24 infos/warnings
  pré-existentes, nenhum arquivo Dart foi tocado nesta tarefa).
  `flutter test`: **407/407 passando**, sem regressão.
- **Painel React**: `tsc -b` limpo. `eslint` limpo nos arquivos
  tocados (2 warnings pré-existentes em `seed_taco_completa.ts`, não
  tocado nesta tarefa — script legado, superado pelo novo
  `curar_catalogo_alimentos_ia.ts`, mas não removido: fora do escopo
  pedido).

## Não resolvido / próximo passo

- Nada verificado em device físico ainda (trabalho local/CI).
  Recomendo o fundador testar o fluxo de fotografar café/suco/
  azeitona/presunto/coxinha e confirmar que a UI especializada por
  categoria aparece corretamente quando a medida do Gemini não bate
  exato com nenhuma medida caseira cadastrada.
- Os 9 alimentos + 12 medidas marcados `revisao_necessaria=true` estão
  visíveis e filtráveis na tela `AdminAlimentos.tsx` reformulada — a
  revisão humana em si é decisão/ação do fundador, não feita aqui.
- `scripts/seed_taco_completa.ts` (gerador das medidas genéricas
  antigas) e `docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA*.csv` (fluxo
  de revisão externo antigo) ficaram como código/documento legado, sem
  chamador real depois desta tarefa — candidatos a limpeza futura, não
  apagados agora (fora do escopo pedido).
