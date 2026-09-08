# RELATÓRIO 20260908_0001 — Curadoria de Aliases + Blindagem do Algoritmo de Casamento (`encontrarAlimento`)

**Data**: 2026-09-08
**Branch**: `fix/catalogo-algoritmo-curadoria` (a partir de `main` — independente das branches ainda não mescladas `fix/medida-liquidos-ml` e `audit/catalogo-aliases-medidas`; não depende de nenhuma delas)
**Referências**: Documento Mestre v8.0, Regra 23 (Falhar Visível) e Regra 26 (Curadoria Humana). Execução do plano aprovado pelo fundador em cima do RELATÓRIO 20260902_0003 (auditoria completa do catálogo).

## O que foi pedido

Duas frentes, ambas já decididas pelo fundador — esta tarefa só executa, não decide nada novo:

1. **Curadoria de dados** (script Deno, só `UPDATE`, nunca `DELETE`): diferenciar as duplicatas exatas, apagar totalmente os aliases genéricos mais perigosos, eleger 1 dono para os aliases ambíguos "de família", e deixar 4 aliases deliberadamente intactos (a blindagem do algoritmo trata a ambiguidade deles).
2. **Fix de algoritmo** em `encontrarAlimento` (`extract-metric-photo/index.ts`): Regra Anti-Sequestro (alias de 1 palavra só resolve por match exato) + falha visível em empate (2+ alimentos diferentes batendo no mesmo passo vira `null`, nunca um chute).

## Parte 1 — Fix de algoritmo

`encontrarAlimento` tinha dois problemas, os dois vindos do mesmo `.find()` sem nenhum critério de desempate — usado nos 3 passos (exato/começa-com/substring):

- **Sequestro por substring**: um alias de 1 palavra só ("suco", "fruta") cadastrado numa linha "sequestrava" qualquer busca composta que o contivesse, mesmo sem o restante da frase existir no catálogo (achado original do RELATÓRIO 20260902_0002: "suco de abacaxi" → suco de laranja).
- **Empate silencioso**: mesmo no match EXATO (achado NOVO desta auditoria, não só no substring como o relatório anterior descrevia), quando 2+ linhas compartilhavam o mesmo alias, `.find()` sempre devolvia a primeira em ordem de array — arbitrário, nunca visível.

**Correções**:
- Aliases de 1 palavra (sem espaço após normalização) só participam do passo 1 (match exato); ficam de fora dos passos 2 (`startsWith`) e 3 (`includes`, nos dois sentidos). `nomeTaco` não foi restringido — só `aliases`, que é o dado editável em massa/por IA e a fonte real do risco.
- Cada passo agora avalia **todos** os candidatos (não só o primeiro achado), deduplicados por `id` (o mesmo alimento pode bater via nomeTaco E 2 aliases diferentes — isso não é ambiguidade). Se sobrar 2+ `id`s diferentes, a função devolve `null` imediatamente — nunca cai pro passo seguinte, mais fraco, que arriscaria "desempatar" por acidente.

## Parte 2 — Curadoria de dados

Script `scripts/curadoria_aliases.ts` — 100% leitura antes de decidir, só `UPDATE` depois, roda em `--dry-run` opcional (usado antes de aplicar de verdade), idempotente (rodar de novo, no estado já curado, reporta 0 linhas a atualizar — confirmado).

Executado contra o banco real: **27/27 linhas atualizadas com sucesso**, 0 falhas, nenhuma linha apagada.

### 1. Duplicatas (só `nome_taco` mudou, `aliases` intactos)

| id | antes | depois | motivo (grounded no próprio dado) |
|---|---|---|---|
| `38e42869...` | Pão de queijo | **Pão de queijo, tradicional** | 30g/unidade, sem modificador de tamanho nos aliases |
| `ab40c4ee...` | Pão de queijo | **Pão de queijo, grande** | 50g/unidade, já tinha alias "pão de queijo grande" |
| `52706959...` | Café, coado | **Café, coado, tradicional** | 2kcal/100g, única com 2 medidas cadastradas (xícara + xícara pequena) |
| `3341d3b8...` | Café, coado | **Café, coado, fraco** | 0kcal/100g, já tinha alias "cafe coado fraco" |

Nenhum dos 4 sufixos foi inventado — os dois "grande"/"fraco" já existiam como aliases nas próprias linhas; "tradicional" foi o complemento lógico pra quem sobrou, sem nenhum modificador próprio.

**Efeito colateral esperado, não um bug**: os `aliases` genéricos ("pão de queijo", "cafe") continuam idênticos nas 2 linhas de cada par — uma busca genérica por "pão de queijo" (sem "grande"/"tradicional") vai continuar batendo nas duas por match exato de alias, e agora (com o fix de algoritmo) devolve `null` (ambíguo) em vez de arbitrar. Isso é o comportamento CORRETO — antes desta tarefa a escolha era arbitrária e escondida.

### 2. Apagados totalmente (17 linhas, 4 aliases)

`fruta` (8 linhas: Atemóia, Banana prata, Goiaba vermelha, Laranja lima/pêra/valência cruas, Pêra Park/Williams), `suco` (4: Laranja lima/pêra/valência suco, Uva suco concentrado), `verdura` (3: Caruru, Catalonha, Couve manteiga), `hortalica`/`hortaliça` (2: Serralha, Taioba).

Removido só o alias EXATO (após normalização) — aliases compostos que só contêm a palavra como parte de uma frase maior (ex.: "achocolatado de fruta" em "Bebida láctea, pêssego") ficaram intactos, corretamente: não são o mesmo risco.

### 3. Eleição de dono único (6 linhas, 3 aliases)

| Alias | Dono mantido | Removido de |
|---|---|---|
| `leite` | Leite, de vaca, integral | Leite, de cabra · Leite, de vaca, desnatado, UHT · Leite, integral |
| `iogurte` | Iogurte natural | Bebida láctea, pêssego · Iogurte, sabor pêssego |
| `achocolatado` | Leite, de vaca, achocolatado (líquido) | Achocolatado, pó |

O script **verifica antes de escrever** que o dono realmente tem o alias hoje — abortaria com erro em vez de silenciosamente apagar o alias de todo mundo se o nome do dono estivesse errado/desatualizado.

### 4. Deliberadamente não tocados

`peixe`, `carne`, `salgado`, `acompanhamento` — nenhuma linha alterada. Ficam ambíguos no dado; é a blindagem de algoritmo (Parte 1) que resolve corretamente na hora da busca.

### Achado no caminho (fora do escopo desta tarefa, registrado)

Existe um 3º par de `nome_taco` idênticos — **"Refrigerante, cola" ×2** — não fazia parte do plano aprovado (só "Pão de queijo" e "Café, coado" foram mencionados). Não tocado. Registrado aqui pra decisão futura do fundador (mesmo padrão de tratamento: 2 ids reais, precisa de consulta pra decidir o sufixo certo antes de agir — Regra 26).

## Verificação do ACEITE (contra o catálogo real, já curado, com a função de produção já atualizada)

Rodei um script de verificação ad-hoc (não commitado — throwaway, mesmo padrão já usado nas tarefas anteriores desta série) chamando `encontrarAlimento` de produção contra o catálogo real pós-curadoria:

| Busca | Resultado real | Bate com o ACEITE? |
|---|---|---|
| `"leite"` | **Leite, de vaca, integral** (único) | ✅ Exatamente o pedido |
| `"carne"` | **null** (ambíguo, 3 alimentos) | ✅ Exatamente o pedido |
| `"suco de abacaxi"` | **null** (sem sequestro) | ✅ Exatamente o pedido |
| `"peixe"` | null (ambíguo, 4 alimentos) | Consistente — mesmo mecanismo de "carne" |
| `"salgado"` | null (ambíguo, 3 alimentos) | Consistente |
| `"iogurte"` | Iogurte natural (único) | Consistente |
| `"achocolatado"` | Leite, de vaca, achocolatado (único) | Consistente |
| `"fruta"` | null (`alimento_nao_encontrado`) | Consistente — alias removido de todo mundo |

**2 achados que divergem da minha expectativa inicial (não são bugs — comportamento correto, registrados por transparência)**:

1. **`"acompanhamento"` NÃO gera ambiguidade** — resolve direto pra "Catalonha, refogada". A auditoria original (20260902_0003) tinha classificado esse alias como "risco latente" (só 1 dono hoje), não como colisão comprovada — diferente de "peixe"/"carne"/"salgado", que já colidem de verdade. O pedido de "manter intacto" segue válido (nada foi tocado), só que o resultado prático hoje é resolução normal, não ambiguidade — a proteção só entra em ação se um segundo alimento vier a usar o mesmo alias no futuro.
2. **`"suco de laranja"` (busca genérica, sem variedade) agora devolve `null` (ambíguo entre 6 linhas)** — antes desta tarefa, `.find()` silenciosamente escolhia a primeira (`Laranja, lima, suco`) sempre. O alias "suco de laranja" é COMPOSTO (2 palavras), então a Regra Anti-Sequestro não o afeta — ele continua um candidato válido nos passos 2/3, e por estar cadastrado em 6 linhas diferentes (Laranja lima/pêra/valência/baía + 2 entradas genéricas "Suco de laranja, natural"/"Suco, de laranja natural"), a nova detecção de empate corretamente para de arbitrar. **Efeito prático**: uma busca comum tipo "suco de laranja" (sem dizer qual variedade) agora cai em `alimento_nao_encontrado` → depende do fallback de busca semântica (`resolverComBuscaSemantica`, já existente) pra resolver — que tem uma boa chance de achar uma das 2 entradas GENÉRICAS ("Suco de laranja, natural") por similaridade, mas isso não foi testado nesta tarefa (fora do escopo — não chamei o Gemini/embeddings de verdade). **Vale monitorar** se esse fallback resolve bem na prática ou se esse caso específico (busca de suco de laranja sem variedade) fica caindo demais na UI de resolução manual — decisão de acompanhar, não de agir agora.

## Testes

5 testes novos em `index_test.ts`, cobrindo exatamente os 3 mecanismos: Regra Anti-Sequestro (alias de 1 palavra não sequestra busca composta, mas continua funcionando no match exato), empate em match exato (`"carne"` sintético → `null`), resolução única pós-curadoria (`"leite"` sintético → único), empate em "começa com" e empate em substring (casos sintéticos isolados, cada um exercitando exatamente um dos 3 passos). `deno check` limpo; **124/124** (119 preexistentes + 5 novos), zero regressão.

## Entregáveis

- Código: `supabase/functions/extract-metric-photo/index.ts` (`encontrarAlimento` blindado).
- Script de curadoria: `scripts/curadoria_aliases.ts` (guardado no repo, já executado contra produção).
- 27 linhas de `alimentos_referencia` atualizadas em produção.
- Este relatório + `INDICE.md`.

## Análise e sugestão de merge

O fix de algoritmo é estritamente mais seguro que o comportamento anterior — nunca inventa um alimento, só troca "chute silencioso" por "ambiguidade honesta" (que já tem 2 caminhos de resolução prontos: busca semântica e UI manual, ambos existentes desde o N27). A curadoria de dados já foi aplicada em produção (não é uma migration pendente — é uma correção de dado, já em vigor). Risco residual conhecido e registrado: buscas genéricas de "suco de laranja" (e potencialmente outros aliases compostos ainda ambíguos, não mapeados nesta tarefa) agora dependem mais do fallback semântico — vale um teste real (device físico ou chamada de produção) antes ou logo depois do merge, para confirmar que esse fallback resolve bem esse padrão específico. Recomendo mesclar o código (branch `fix/catalogo-algoritmo-curadoria`) assim que autorizado — a curadoria de dado já está em produção independente do merge do código (mesmo padrão de outras tarefas desta série: dado e código de Edge Function nem sempre andam no mesmo commit). Depois do merge do código, lembrete de sempre: `supabase functions deploy extract-metric-photo` (sem CI/CD no repo).
