# RELATÓRIO 20260902_0003 — Auditoria Completa do Catálogo (Colisão de Aliases × Cobertura de Medidas)

**Data**: 2026-09-02
**Branch**: `audit/catalogo-aliases-medidas` (a partir de `main` — independente da cadeia de branches de fixes ainda não mescladas; esta tarefa é 100% investigativa, zero código de produção tocado)
**Referências**: Documento Mestre v8.0, Regra 23 (Falhar Visível) e Regra 26 (Curadoria Humana). Continuação direta do RELATÓRIO 20260902_0002.

## Contexto

O RELATÓRIO 20260902_0002 encontrou, ao investigar "copo de suco", um bug real de falso-positivo: o alias solto `"suco"` fazia `encontrarAlimento` casar "suco de abacaxi" com suco de LARANJA, silenciosamente. O fundador pediu uma auditoria completa e read-only do catálogo pra mapear o tamanho real do problema, cruzando com cobertura de medidas caseiras.

## Metodologia

Script novo `scripts/auditoria_catalogo.ts` — **100% leitura**, nenhum `UPDATE`/`DELETE`/`INSERT` em lugar nenhum. Baixa `alimentos_referencia` (637 linhas) e `alimentos_medidas_caseiras` (1.056 linhas) uma vez cada, processa tudo em memória. Importa `encontrarAlimento` DIRETO de `supabase/functions/extract-metric-photo/index.ts` (não uma reimplementação) — os achados abaixo são o comportamento REAL de produção, não uma simulação aproximada.

**Achado metodológico no meio da própria auditoria**: a primeira rodada do script trouxe só 1.000 das 1.056 linhas de `alimentos_medidas_caseiras` — o teto padrão de paginação do PostgREST (1.000 linhas/resposta), sem nenhum erro ou aviso. Isso inflou falsamente a Parte 2 (chegou a reportar "Uva, suco concentrado, envasado" como sem nenhuma medida cadastrada — falso, confirmado por consulta manual direta que ela TEM "copo"/"copo americano"). Corrigido com paginação real via `.range()` em loop antes de qualquer conclusão ser tirada — os números abaixo já são da versão corrigida.

## Parte 1 — Colisão de aliases

**Técnica**: para cada alimento do catálogo, busquei o PRÓPRIO nome e cada um dos PRÓPRIOS aliases contra o catálogo inteiro (a mesma função de produção) — se um alimento não encontra a si mesmo, é prova concreta (não suposição) de que outro alimento está roubando o match.

**404 falhas de autoconsistência** — bem mais do que o esperado. Categorizando por severidade:

### 1a. Duplicatas exatas de linha (achado novo, mais básico que o do relatório anterior)

Pelo menos **2 pares de linhas com `nome_taco` idêntico**, confirmados por consulta direta: `"Pão de queijo"` (2 linhas, ids diferentes, aliases quase iguais) e `"Café, coado"` (2 linhas, mesma situação). Nestes casos nem o passo 1 (match exato) de `encontrarAlimento` ajuda — `.find()` devolve a primeira das duas em ordem de array, arbitrariamente. Não é o mesmo bug do "suco" (não é um alias genérico demais) — é uma linha do catálogo literalmente repetida. Recomendo conferir se são duplicatas reais de importação (mesclar) ou dois produtos que só coincidem no nome (renomear um).

### 1b. Colisão de EXACT MATCH, não só substring (correção do relatório anterior)

O RELATÓRIO 20260902_0002 descreveu o mecanismo como "passo 3 (substring, último recurso)". A auditoria mostra que **o passo 1 (match exato) também colide**, sempre que a MESMA palavra está cadastrada como alias em duas linhas diferentes — não precisa de substring nenhum. Exemplo confirmado por consulta direta: a palavra `"dobradinha"` está cadastrada como alias tanto na linha `"Dobradinha"` (o prato pronto) quanto na linha `"Carne, bovina, bucho, cozido"` (o ingrediente cru cozido) — `encontrarAlimento(catalogo, "Dobradinha")` empata entre as duas no passo 1, e o `.find()` devolve `"Carne, bovina, bucho, cozido"` (ordem alfabética de `nome_taco`, "Carne" < "Dobradinha") — **a própria linha "Dobradinha" nunca resolve pra si mesma**. Corrige a causa raiz que eu tinha atribuído erradamente só ao passo 3: `.find()` não tem nenhum critério de desempate em NENHUM dos 3 passos, sempre que duas linhas competem pelo mesmo termo.

### 1c. Confusão dentro da MESMA família (baixo impacto nutricional, geralmente)

A maioria dos 404 é isto: variedades/preparos do MESMO alimento, onde o alias genérico não distingue qual delas ("banana" → sempre "Banana, figo, crua", nunca importa se o usuário quis prata/maçã/nanica; "corvina"/"peixe grelhado"/"carne grelhada" → sempre a mesma variante). Macros entre variedades da mesma fruta/corte costumam ser próximos — imprecisão real, mas geralmente não muda a ordem de grandeza do resultado. **Exceção real dentro desta categoria**: cru×cozido (ex.: `"musculo"` de "cru" resolve pro registro COZIDO) muda calorias/100g de forma não-trivial (perda de água no cozimento) — vale atenção mesmo sendo "mesma família".

### 1d. Confusão ENTRE categorias/produtos diferentes (alto impacto — prioridade de curadoria)

O subconjunto que realmente importa. Além do já conhecido `"suco"` (Laranja/Uva, achado do relatório anterior — a auditoria confirma de novo: `"suco"` buscado a partir da própria linha "Uva, suco concentrado, envasado" volta "Laranja, lima, suco" — a Uva não se acha nem a si mesma), encontrei:

| Alias buscado | Alimento de origem | Resultado errado | Por quê importa |
|---|---|---|---|
| `"suco concentrado"` | Maracujá, suco concentrado | **Caju**, suco concentrado | Fruta trocada, mesma classe de bug do abacaxi |
| `"leite"` | Leite de vaca (2 linhas) | **Leite de cabra** | Espécie de origem diferente |
| `"iogurte"` | Iogurte natural / sabor pêssego | **Bebida láctea, pêssego** | Produto diferente (iogurte × bebida láctea) |
| `"achocolatado"` | Leite achocolatado (pronto) | **Achocolatado, pó** (concentrado) | Pronto-pra-beber × pó — densidade calórica bem diferente |
| `"leite fermentado"` | Leite, fermentado | **Iogurte natural** | Produtos próximos mas distintos |
| `"suco de caju"` | Caju, suco concentrado | **Caju, polpa, congelada** | Suco × polpa congelada (categoria errada: líquido vira sólido/sachê) |
| `"peixe"` | 4 peixes diferentes | Sempre o mesmo (Atum/varia) | Alias `"peixe"` só cadastrado em 4 das dezenas de linhas de peixe do catálogo |
| `"fruta"` | Banana/Goiaba/Laranja×3/Pêra×2 | **Sempre "Atemóia, crua"** | O alias mais perigoso do catálogo — 8 frutas diferentes, sempre a mesma resposta |
| `"carne cozida"` (múltiplos cortes) | vários cortes bovinos | **"Barreado"** (prato pronto, não corte simples) | Corte de carne simples vira prato temperado |

**Padrão comum**: palavras-CATEGORIA cadastradas como alias solto (`fruta`, `suco`, `peixe`, `carne`, `verdura`, `hortalica`, `salgado`, `acompanhamento`) são as mais perigosas — cruzam QUALQUER alimento daquela categoria pra sempre a mesma linha, não só variantes próximas. `"fruta"` sozinha é o pior caso: qualquer futuro alimento com esse alias (ou substring compatível) sempre daria Atemóia.

### 1e. Números agregados (Parte 1)

- **103 aliases de 1 palavra já compartilhados por 2+ alimentos** (colisão comprovada hoje).
- **241 aliases de 1 palavra usados por só 1 alimento hoje** — risco LATENTE (colidiriam se um alimento novo com o mesmo alias entrasse no catálogo, como aconteceu com "suco"/abacaxi). **Não é uma lista de bugs** — a maioria é perfeitamente segura hoje (ex. `"abacate"`→"Abacate, cru" não tem com o que colidir). Serve só como candidatos pra revisão preventiva, não uma fila de correção.

## Parte 2 — Cobertura de medidas (após corrigir a paginação)

Resultado bem mais saudável do que a primeira rodada (com bug) sugeria:

- **Líquidos sem medida de recipiente nomeado cadastrada: 3** — os 2 já conhecidos (Limão, cravo/galego, suco — só "colher de sopa") + **Tacacá, que é falso-positivo do MEU script**: a lista de palavras-recipiente que usei (`copo/xícara/taça/lata/garrafinha/garrafa/dose/cálice/caneca`) não incluía `"cuia"`/`"tigela"` — Tacacá TEM essas duas cadastradas (300g/250g), é um prato servido em cuia de verdade, não um alimento com lacuna real.
- **Itens de unidade/fatia sem nenhuma medida: 0** (a rodada com bug de paginação tinha reportado 5 — falso).
- **Total de alimentos sem nenhuma medida cadastrada: 0** (a rodada com bug tinha reportado 29 — falso).

Conclusão da Parte 2: **a cobertura de medidas está saudável** — os únicos 2 gaps reais são os mesmos 2 já corrigidos no fluxo de UX pelo RELATÓRIO 20260902_0002 (a UI já pede "ml" corretamente pra eles, mesmo sem "copo" cadastrado).

## Parte 3 — Cruzamento

**0 alimentos** com as duas vulnerabilidades ao mesmo tempo, depois da correção de paginação (a rodada com bug tinha reportado 2, ambos falsos).

## Correção da imprecisão do RELATÓRIO 20260902_0002 ("manga")

Confirmado: **não era um bug de cruzamento de fruta errada**. O alias responsable é `"suco de manga congelado"` (frase completa, específica), cadastrado em `"Manga, polpa, congelada"` — um produto genuinamente relacionado a suco de manga (a polpa congelada É o insumo pra fazer o suco), só categorizado como `peso_livre`/sachê em vez de líquido. Isso é uma lacuna de categorização, não uma colisão de alias — mais parecido com a Parte 2 do que com a Parte 1.

## Recomendações (sem decidir nada sozinho — Regra 26)

Duas frentes, complementares, nenhuma decisão tomada aqui:

1. **Curadoria de dados (ação mais rápida, maior valor imediato)**: revisar os **9 aliases-categoria genéricos** identificados na seção 1d (`fruta`, `suco`, `peixe`, `carne`, `leite`, `iogurte`, `achocolatado`, `verdura`/`hortalica`, `salgado`/`acompanhamento`) — remover onde não fizerem sentido como alias único, ou torná-los mais específicos. Prioridade sobre os 241 "risco latente" (que majoritariamente não precisam de ação).
2. **Fix de algoritmo** (discutido no relatório anterior, agora com evidência mais forte): dar ao `.find()` de `encontrarAlimento` algum critério de desempate — hoje não existe NENHUM, em NENHUM dos 3 passos (mesmo o "match exato" empata sem critério, achado novo desta auditoria). Mesmo princípio já usado no N27 para `encontrarMedida`: falhar visível (`alimento_nao_encontrado`) em vez de arbitrar, deixando `resolverComBuscaSemantica` (já existe) tentar achar algo melhor.
3. **Duplicatas de linha** ("Pão de queijo" × 2, "Café, coado" × 2): revisão separada, provavelmente mesclar ou renomear — não é a mesma classe de problema, é dado literalmente repetido.

## Entregáveis

- `scripts/auditoria_catalogo.ts` — script de auditoria, read-only, registrado no repo.
- `docs/log_dev/20260902_0003_auditoria_catalogo_saida_bruta.txt` — saída completa e crua do script (404+103+241 linhas, sem corte), pra revisão manual completa sem depender só do resumo acima.
- Este relatório.

## Verificação

`deno check scripts/auditoria_catalogo.ts` limpo. Script executado 2x contra o banco real (1ª rodada achou e corrigiu o próprio bug de paginação, 2ª rodada é a fonte dos números finais acima) — `EXIT 0` nas duas, confirmando que nenhuma escrita foi tentada nem falhou. Nenhuma linha de `alimentos_referencia`/`alimentos_medidas_caseiras` foi alterada (auditoria pura).

## Análise e sugestão de merge

Zero risco — nenhum código de produção tocado, só um script novo (não chamado por nenhuma Edge Function/app) e 2 documentos. Pode ser mesclado a qualquer momento sem afetar nada em produção; o valor real está nas decisões de curadoria que o fundador tomar a partir daqui, não no merge em si.
