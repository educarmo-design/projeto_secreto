# 20260823_0003_investigacao_medidas_caseiras_categoria_consumo — Investigação: relação alimentos_referencia × alimentos_medidas_caseiras + achado de bug (categoria_consumo nunca chega no Flutter)

Log de Máquina (Regra 10.3 — append-only). Tarefa só de INVESTIGAÇÃO,
pedida pelo fundador antes de reportar um bug visto em tela — sem
nenhuma mudança de código nesta tarefa. Motivo explícito do pedido:
o fundador vai pedir uma reformulação da tela/processo de cadastrar
refeição (ver [[pendencia-reformulacao-cadastro-refeicao]] em memória)
e queria mapear o terreno antes de escrever o relatório do bug.

## Perguntas do fundador e respostas

### 1. Relação entre `alimentos_medidas_caseiras` e `alimentos_referencia`

1:N por FK, `alimentos_medidas_caseiras.alimento_id references
alimentos_referencia(id) on delete cascade`, com
`unique(alimento_id, medida)` (`20260716120000_alimentos_referencia_taco.sql`).
`alimentos_referencia` é um alimento por linha (composição por 100g,
TACO/USDA, + os campos de categorização adicionados depois:
`categoria_consumo`/`unidade_medida_padrao`/`medida_padrao_nome`/
`medida_padrao_qtd`, migration `20260802120000_categorias_alimentos_pesos_padrao.sql`).
`alimentos_medidas_caseiras` guarda quanto cada "medida caseira"
(colher de sopa, concha, unidade, fatia...) pesa PARA aquele alimento
específico — não é uma tabela de conversão genérica (1 colher de arroz
≠ 1 colher de feijão em gramas).

### 2. Onde são usadas (React + Flutter, investigação completa nos dois lados)

| Camada | Arquivo | Uso |
|---|---|---|
| Backend/câmera | `supabase/functions/extract-metric-photo/index.ts` | Lê as duas tabelas juntas (`alimentos_referencia` com `alimentos_medidas_caseiras(...)` aninhado, `~linha 1577`) pra casar o texto livre do Gemini e calcular calorias/macros |
| Backend/busca | `supabase/functions/search-food/index.ts` | Lê só `alimentos_referencia` (id, nome, aliases, macros/100g) — nunca toca `alimentos_medidas_caseiras` nem `categoria_consumo` |
| React (painel) | `web_painel/src/features/admin/components/AdminAlimentos.tsx` | CRUD admin das duas tabelas (alimento + "Porções") — mas o formulário NÃO expõe `categoria_consumo`/`unidade_medida_padrao`/`medida_padrao_nome`/`medida_padrao_qtd` em lugar nenhum, só os 4 macros/100g + porções |
| Flutter/câmera | `ConfirmacaoPratoPage._buildContenudoEstimado` | UI condicional que troca de aparência conforme `categoria_consumo` do item (líquido frio/quente, unidade/fatia, peso livre) |
| Flutter/manual | `CriarFavoritaPage` (nova, RELATÓRIO 20260823_0002) + `ManualFoodSearchPage` | Usam só `search-food` → `alimentos_referencia` (macros/100g); nunca tocam `alimentos_medidas_caseiras` nem `categoria_consumo` — por isso `CriarFavoritaPage` só tem "gramas" com stepper de 10g, sem medida caseira nenhuma |
| Scripts one-off | `scripts/etl_carga_taco.ts`, `seed_taco_completa.ts`, `seed_food_embeddings.ts`, `gerar_csv_medidas_pendentes.ts` | Importação/seed, não é runtime do produto |

### 3. Campo de "revisão" — não existe como coluna

Nenhuma das duas tabelas tem coluna chamada "revisão". O comentário da
migration `20260802120000` diz que `categoria_consumo IS NULL` =
"pendente de revisão", mas isso nunca virou flag/tela dentro do
produto. O fluxo real de revisão é EXTERNO e offline: um script
(`scripts/gerar_csv_medidas_pendentes.ts`) gera um CSV
(`docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA*.csv`) pra revisão manual
fora do app — não é banco, não é tela.

### 4. Câmera — qual tabela as medidas usam (e o BUG achado)

Fluxo real (`extract-metric-photo/index.ts`, função `encontrarMedida`):
1. Se o alimento casado tem uma linha em `alimentos_medidas_caseiras`
   batendo com a medida que o Gemini disse → usa ela (gramas reais).
2. Sem match → usa a primeira medida cadastrada daquele alimento.
3. Sem nenhuma medida cadastrada → cai pra `categoria_consumo`/
   `medida_padrao_qtd`/`unidade_medida_padrao` de `alimentos_referencia`
   (ex.: "200ml (est.)").
4. Nada disso → chuta 100g.

## Achado: `categoria_consumo` nunca chega no Flutter — UI condicional é código morto

### O caminho completo, com código exato

**Passo 1 — o servidor CARREGA os 4 campos do banco (funciona):**
```ts
// extract-metric-photo/index.ts, ~linha 1577
.select('id, nome_taco, aliases, calorias_kcal_100g, proteinas_g_100g, '
  + 'carboidratos_g_100g, gorduras_g_100g, categoria_consumo, '
  + 'unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd, '
  + 'alimentos_medidas_caseiras(medida, gramas)')
...
categoriaConsumo: linha.categoria_consumo ?? undefined,
unidadeMedidaPadrao: linha.unidade_medida_padrao ?? undefined,
medidaPadraoNome: linha.medida_padrao_nome ?? undefined,
medidaPadraoQtd: linha.medida_padrao_qtd ? Number(linha.medida_padrao_qtd) : undefined,
```
O objeto `AlimentoCatalogo` em memória tem os 4 campos, corretamente.

**Passo 2 — `encontrarMedida` USA esses campos só pra montar uma STRING
de fallback, sem devolver a categoria em si:**
```ts
// linha 1137-1151
if (!alimento.categoriaConsumo || !alimento.medidaPadraoQtd) {
  return { medida: '100g (est.)', gramas: 100 };
}
const qtdPadrao = alimento.medidaPadraoQtd;
const unidade = alimento.unidadeMedidaPadrao || 'g';
return { medida: `${qtdPadrao}${unidade} (est.)`, gramas: qtdPadrao };
```
Retorna só `{ medida: string, gramas: number }` (tipo
`MedidaCaseiraCatalogo`, sem campo de categoria).

**Passo 3 — `calcularItem` monta o item final; o TIPO DE RETORNO não
tem onde guardar a categoria:**
```ts
// interface ItemPratoCalculado, linha 544-573 — só tem:
nomeIdentificado, alimentoCasado, medida, quantidade, gramasEstimados,
calorias, proteinasG, carboidratosG, gordurasG, confianca,
origemCasamento?, similaridade?, quantidadeEstimada?, pesoTipicoGramas?
// NENHUM campo categoriaConsumo/unidadeMedidaPadrao/medidaPadraoNome/medidaPadraoQtd
```
`calcularItem` recebe `params.alimento` (que TEM `categoriaConsumo`)
mas nunca copia esse campo pro objeto que retorna — beco sem saída
estrutural, o tipo não comporta o dado.

**Passo 4 — a resposta HTTP final confirma a ausência:**
```ts
// linha 2015-2032
itens: itensFinais.map((item) => ({
  nome: item.alimentoCasado, nome_identificado: item.nomeIdentificado,
  medida: item.medida, quantidade: item.quantidade,
  gramas_estimados: item.gramasEstimados, calorias: item.calorias,
  proteinas_g: item.proteinasG, carboidratos_g: item.carboidratosG,
  gorduras_g: item.gordurasG, confianca: item.confianca,
  ...(item.origemCasamento ? { origem_casamento: item.origemCasamento } : {}),
  ...(item.similaridade !== undefined ? { similaridade: item.similaridade } : {}),
  ...(item.quantidadeEstimada ? {
    quantidade_estimada: item.quantidadeEstimada,
    peso_tipico_gramas: item.pesoTipicoGramas,
  } : {}),
}))
```
Nenhuma chave `categoria_consumo` no JSON.

### Exemplo concreto — fotografar um café

"Café, coado" (`categoria_consumo='liquido_quente'`,
`medida_padrao_qtd=200`, `unidade_medida_padrao='ml'`) não tem NENHUMA
linha em `alimentos_medidas_caseiras` — só os 5 alimentos do seed
original (arroz/feijão/carne/ovo/alface, `20260716120000`) têm.

1. `encontrarMedida` cai no fallback de categoria →
   `{ medida: '200ml (est.)', gramas: 200 }`.
2. `quantidadeEstimada = medida.medida.includes('est.')` → `true`.
3. JSON devolvido: `medida: "200ml (est.)"`, `quantidade_estimada: true`,
   `peso_tipico_gramas: 200` — **sem `categoria_consumo`**.
4. Flutter (`ItemPratoExtraidoModel.fromJson`):
   `categoriaConsumo: json['categoria_consumo'] as String?` → chave não
   existe no mapa → `null`. `quantidadeEstimada` chega `true`
   corretamente (esse campo o servidor manda).
5. `ConfirmacaoPratoPage`: como `quantidadeEstimada == true`, o card
   ENTRA no bloco condicional (`_buildContenudoEstimado`) — mas dentro
   dele:
   ```dart
   final categoria = item.original.categoriaConsumo; // null, sempre
   if (categoria == 'liquido_frio') { ... }
   else if (categoria == 'liquido_quente') { ... }   // nunca bate
   else if (categoria == 'unidade' || categoria == 'fatia') { ... }
   else {
     return _buildAvisoGenericoComEdicao(context, item); // SEMPRE cai aqui
   }
   ```

Resultado visível: em vez do card azul "Tamanho da xícara: Café (50ml)
/ Chá (200ml) / Customizar" (existe no código, faria sentido pro
café), aparece o aviso genérico âmbar "Quantidade estimada — edite se
necessário" com "Peso típico: 200g" — **rotulado em gramas**, mesmo
sendo um líquido de 200ml (a coluna `alimentos_medidas_caseiras.gramas`
/`medida_padrao_qtd` mistura g e ml no mesmo número, sem indicar a
unidade na UI genérica).

### Alcance do bug — por que é código morto pra QUALQUER alimento

- Os 5 itens do seed original (arroz, feijão, carne, ovo, alface) TÊM
  `alimentos_medidas_caseiras` cadastrada → casam pelo branch 1/2 de
  `encontrarMedida`, nunca passam por `quantidadeEstimada=true` →
  nunca entram em `_buildContenudoEstimado` (o `if` de fora nem abre).
- Os 12 itens categorizados na migration seguinte (café, chá, suco,
  refrigerante, leite, água, pão de queijo, azeitona, presunto, queijo,
  coxinha, pastel) NÃO têm medida caseira cadastrada → sempre caem no
  fallback de categoria → `quantidadeEstimada=true` → ENTRAM em
  `_buildContenudoEstimado`, mas `categoriaConsumo` chega `null` →
  sempre caem no `else` genérico.
- **Conclusão**: para todo e qualquer alimento, hoje, o card de líquido
  frio/quente e o de unidade/fatia (com botões de tamanho pré-definido)
  é código inalcançável — 100% das fotos caem ou na tela padrão (sem
  aviso) ou no fallback âmbar genérico, nunca na UI especializada por
  categoria.

## Não resolvido / próximo passo

Nenhuma mudança de código nesta tarefa — só investigação, por pedido
explícito do fundador. Achado registrado em memória
([[pendencia-reformulacao-cadastro-refeicao]]) e aqui, aguardando o
relatório do fundador com a reformulação pedida da tela/processo de
cadastrar refeição antes de qualquer conserto ou redesign.
