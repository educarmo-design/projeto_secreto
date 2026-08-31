# RELATÓRIO 20260831_0001 — Fix: escala matemática errada quando o usuário digita gramas/ml explícitos

**Data:** 2026-08-31
**Branch:** `fix/calculo-multiplicador-texto` (a partir de `main`, não mesclada — ver "Estado das branches")
**Pedido:** "300 gramas de sorvete" gerava calorias muito maiores que o esperado no registro descritivo (texto), contexto Mestre v8.0 Parte 3.5 (G.7 — cálculo sempre determinístico).

## Investigação — o que o "~3x" realmente era

Antes de mexer em código, reproduzi a chamada real ao Gemini com o MESMO
system prompt e formato exatos que o servidor usa
(`SYSTEM_PROMPT_PRATO_REFEICAO_TEXTO`), pra "300 gramas de sorvete" e
variações:

```
"300 gramas de sorvete" -> {"nome":"sorvete","medida":"gramas","quantidade":300,"confianca":1.0}
"300 gramas de arroz"   -> {"nome":"arroz","medida":"gramas","quantidade":300,"confianca":1.0}
"200g de frango"        -> {"nome":"frango grelhado","medida":"g","quantidade":200,"confianca":1.0}
```

Confirmado: quando o usuário escreve um peso explícito, o Gemini devolve
`medida: "gramas"/"g"` com `quantidade` = o número literal — exatamente
como o prompt já permite ("NEVER grams... unless the user explicitly wrote
a gram/ml value themselves"). Até aqui, nenhum bug.

**Achado 1 (estrutural — o problema de fundo):** consultei o catálogo real
(1.056 medidas caseiras, service role) e confirmei que **nenhum alimento
tem uma medida caseira literalmente chamada "grama"/"gramas"/"g"/"ml"/
etc.** — são todas nomes de medida caseira (`colher de sopa`, `concha`,
`fatia`...). O backend nunca teve um caminho pra interpretar "gramas" como
peso direto; só sabia casar um NOME de medida contra a tabela
`alimentos_medidas_caseiras` daquele alimento específico. Resultado: pra
`medida="gramas"`, `encontrarMedida` nunca achava match exato/substring e
caía num dos fallbacks existentes (primeira medida cadastrada do alimento,
ou peso genérico) — multiplicando um peso-por-unidade **errado** (de uma
medida caseira qualquer) pela quantidade 300. Medido em casos reais
(arroz→"colher de sopa"=25g, frango→"filé médio"=120g): o fator de erro
variava entre **25x e 120x**, nunca um "3x" fixo — dependia inteiramente
de qual medida o alimento tinha cadastrada.

**Achado 2 (o vazamento matemático de verdade — mais fundamental que o
Achado 1):** ao testar a correção do Achado 1, encontrei o segundo bug,
esse sim explicando por que o founder viu um número "só" ~3x maior (não
25x-120x) em algumas tentativas: `parseRespostaGeminiPrato` aplica um teto
de sanidade em `quantidade` — `Math.min(quantidade, 20)` — desenhado pra
rejeitar um Gemini alucinando "50 colheres de sopa" (contagem de medida
caseira, 20 já é um teto generoso). Mas o MESMO campo `quantidade`
**também** carrega o peso em gramas/ml quando é unidade bruta —
`quantidade: 300` (gramas) passava pelo mesmo teto e virava
**silenciosamente `quantidade: 20`**. "300 gramas" processado como "20
gramas" é o vazamento real: a proporção que o usuário pediu nunca chegava
inteira no cálculo, exatamente como o pedido descreveu ("fator sendo
aplicado incorretamente").

**"sorvete" especificamente:** confirmei que sorvete não existe no
catálogo TACO de 637 alimentos (nem por nome, nem por alias) — a busca
semântica casaria com "Doce de leite" (similaridade 0,69, acima do
threshold 0,55), um alimento diferente com macros diferentes. Isso é uma
lacuna de COBERTURA do catálogo (fora do escopo desta tarefa — é o mesmo
tipo de achado já registrado em R29/decisão 35 do Mestre), não um bug
matemático — por isso valido o ACEITE com alimentos que existem de
verdade no catálogo (arroz, frango), não literalmente "sorvete".

## O que foi corrigido

`supabase/functions/extract-metric-photo/index.ts`:

1. **Unidade bruta agora é reconhecida e resolvida ANTES de qualquer
   tentativa de casar por nome** (`FATORES_UNIDADE_BRUTA`, novo, módulo
   nível): quando a medida normalizada é `grama`/`g`/`quilograma`/`quilo`/
   `kg`/`mililitro`/`ml`/`litro`/`l`, `encontrarMedida` devolve
   `{ medida: <texto original>, gramas: <fator por unidade> }`
   diretamente — nunca consulta `alimento.medidas`. `calcularItem` (que já
   existia, sem alteração) faz `gramas_total = fator * quantidade` — a
   regra de três continua acontecendo **uma única vez**, só que agora com
   a taxa de conversão certa (1g/unidade pra grama, 1000g/unidade pra
   quilo, etc.) em vez de pegar emprestado o peso de uma medida caseira
   aleatória de outro contexto.

2. **Teto de sanidade separado pra unidade bruta**
   (`QUANTIDADE_MAXIMA_UNIDADE_BRUTA_GRAMAS_OU_ML = 5000`, em
   `parseRespostaGeminiPrato`): quando a medida é uma unidade bruta,
   `quantidade` é limitado a 5000 (5kg/5L — generoso pra qualquer prato
   real, ainda protege contra um número alucinado tipo "999999 gramas"),
   não mais aos 20 usados pra CONTAGEM de medida caseira. O teto de 20
   continua valendo, sem alteração nenhuma, pra medida caseira normal
   ("300 colheres de sopa" continua absurdo e continua sendo capado).

Nenhuma mudança em `ItemPratoCalculado`/`ItemPratoNaoReconhecido`/contrato
HTTP — o fix é inteiramente interno ao cálculo, o formato da resposta não
muda.

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| Unidade bruta resolvida ANTES do casamento por nome, não como mais uma camada de fallback | É universal (nunca depende do alimento) — colocar depois arriscaria "grama" casar por acidente como substring de alguma medida caseira registrada |
| `FATORES_UNIDADE_BRUTA` devolve gramas **por unidade** (1, 1000...), não o total já multiplicado | `calcularItem` já multiplica por `quantidade` — devolver o total aqui multiplicaria duas vezes (exatamente o risco que o pedido avisou) |
| Teto de sanidade da unidade bruta é um valor NOVO e separado (5000), não removido | Sem teto nenhum, um número alucinado ("999999999 gramas") viraria um cálculo grotesco sem nenhuma blindagem — mesma filosofia do teto de 20 já existente, só calibrado pra uma unidade diferente |
| `ml`/`litro` tratados com o mesmo fator de `g`/`kg` (1 e 1000) | Mesma convenção já usada no resto do arquivo pra líquidos (`categoriaConsumo === 'liquido_frio'` guarda o valor em `gramas` mesmo sendo ml) |
| ACEITE validado com "arroz"/"frango" reais, não literalmente "sorvete" | Sorvete não existe no catálogo de 637 alimentos — lacuna de cobertura separada, documentada, fora do escopo de um fix matemático |
| Fallbacks antigos de `encontrarMedida` (primeira medida disponível / peso genérico) NÃO foram tocados nesta tarefa | Já são o alvo do N27 (branch separada `fix/falhar-visivel-medida-n27-n28-n14`, aguardando merge) — misturar as duas mudanças na mesma função dificultaria revisão; esta tarefa resolve o problema de escala independente de quando N27 mesclar |

## Infra/config

Nenhuma. Nenhuma migration, nenhum secret novo, nenhuma mudança de
contrato HTTP.

## Entidades novas

Nenhuma.

## Desvios de spec

Nenhum. O ACEITE pedia "300 gramas de sorvete retorna 3x macros_por_100g
exato" — cumprido para alimentos que existem no catálogo (o mecanismo
matemático é idêntico pra qualquer alimento); a ausência de "sorvete" no
catálogo é uma lacuna de dado pré-existente, documentada acima, não uma
falha desta correção.

## Problemas encontrados

- **Achado 2 (teto de sanidade compartilhado) era o bug mais fundamental**
  — descoberto só ao escrever o teste do ACEITE literal, que falhou com
  `gramas_estimados: 20` em vez de `300`. Registrado em detalhe acima
  porque é o tipo de achado que só aparece testando o caminho feliz até o
  fim, não só a função isolada.
- "sorvete" fora do catálogo TACO — não corrigido aqui (fora de escopo),
  mas fica registrado como um exemplo real de lacuna de cobertura (mesma
  categoria do R29/decisão 35 do Mestre).

## Riscos mapeados + mitigação

- **Risco novo, baixo:** o teto de 5.000g/5.000ml por item é arbitrário
  (escolhido como "generoso mas não absurdo"). Se um caso real legítimo
  precisar de mais (ex.: um prato compartilhado de "2kg de churrasco"),
  ficaria capado em 5kg — mitigação: fácil de ajustar (uma constante), e
  5kg já cobre qualquer refeição individual real.
- **Risco pré-existente, não deste fix:** os fallbacks antigos de
  `encontrarMedida` (primeira medida disponível/peso genérico) continuam
  ativos para medida caseira que não casa — mitigado pela branch N27, que
  os remove (ainda não mesclada). Este fix não piora nem resolve esse
  risco, é ortogonal.
- **Risco pré-existente, não deste fix:** cobertura do catálogo (637
  alimentos TACO nunca vai cobrir tudo que alguém escreve/fala) — já
  mapeado no Mestre (decisão 35, R29), fora do escopo de um fix
  matemático.

## Como o fundador testa (ACEITE)

1. Registro descritivo (texto): digitar "300 gramas de arroz" (ou
   qualquer alimento que exista no catálogo — "arroz", "frango grelhado",
   "feijão"...).
2. Esperado: o item aparece com **300g**, calorias = exatamente
   3 × calorias_por_100g do alimento casado (ex.: arroz branco cozido,
   128 kcal/100g → 384 kcal), sem nenhum múltiplo estranho.
3. Testar também `"200 gramas de X"`, `"1kg de X"`, `"500ml de Y"` (líquido)
   — todos devem bater com a regra de três direta, sem depender de
   nenhuma medida caseira cadastrada para aquele alimento.
4. Caso de regressão a NÃO acontecer: "2 colheres de sopa de arroz"
   continua funcionando exatamente como antes (medida caseira normal,
   teto de 20 intacto).

## Como a performance foi tratada

Sem impacto. A checagem de unidade bruta é um lookup O(1) num objeto fixo
de 9 chaves, feita uma vez por item, tanto no parser quanto em
`encontrarMedida` — nenhuma I/O nova, nenhuma chamada de rede adicional.

## Verificação

- `deno check` limpo em `index.ts`/`index_test.ts`.
- Deno: **110/110 passando** (100 já existentes + 10 novos: 4 de
  `encontrarMedida` com unidade bruta, 2 de `calcularPrato` com o ACEITE
  literal, 3 de `parseRespostaGeminiPrato` cobrindo os dois tetos de
  sanidade separados, 1 de nível handler reproduzindo o payload real do
  Gemini ponta a ponta). Zero regressão.
- Nenhum arquivo Flutter tocado — suíte Flutter não re-executada nesta
  tarefa (escopo 100% servidor).

## Estado das branches

Trabalho feito em `fix/calculo-multiplicador-texto`, criada a partir de
`main` (não da branch `fix/falhar-visivel-medida-n27-n28-n14`, ainda não
mesclada — as duas mudanças são independentes e não deveriam ser
misturadas numa revisão só). **Não mesclada.**

**Instruções de PR:**

```
git push -u origin fix/calculo-multiplicador-texto
gh pr create --base main --head fix/calculo-multiplicador-texto \
  --title "fix: escala matemática errada em gramas/ml explícitos no registro descritivo" \
  --body "Ver docs/log_dev/20260831_0001_fix_escala_matematica_registro_descritivo_gramas.md"
```

**Sugestão de merge rápido:** seguro e recomendado mesclar logo — mudança
pequena, cirúrgica, isolada a duas funções puras (`parseRespostaGeminiPrato`/
`encontrarMedida`), zero mudança de contrato, zero migration, suíte
inteira verde. Diferente do Bloco A (N27+N28+N14), este fix não muda o
formato de nenhum dado consumido por outra parte do sistema — não há
motivo pra esperar. Por Regra 18, ainda assim espera autorização explícita
do fundador antes do merge em si.
