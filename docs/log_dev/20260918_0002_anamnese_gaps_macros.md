# RELATÓRIO 20260918_0002 — Fecha Gaps do Painel Web + Implementa Macronutrientes, Score de Qualidade e Recomendação Energética

**Data:** 2026-09-18
**Branch:** `fix/anamnese-gaps-macros` (a partir de `main`)
**Persona:** Engenheiro de Software e Arquiteto (Mestre v8.0)

## Mea-culpa — o achado real por trás desta tarefa

A tarefa anterior (RELATÓRIO 20260918_0001) leu `docs/motor_metabolico.txt` usando `Get-Content | Measure-Object -Line` no PowerShell para decidir onde parar de ler — esse comando devolveu **2288**. O arquivo real tem **3512 linhas** (confirmado agora lendo com o Read tool até o fim de verdade, sem depender de contagem externa). A diferença — quase 1.300 linhas — continha 3 seções inteiras nunca lidas:

* `# Motor Metabólico — Protocolos de Macronutrientes V1.0` (linha 2590) — MACRO-001 a MACRO-005, com fórmulas explícitas.
* `# Motor Metabólico — Definição da Meta Energética V1.0` (linha 2980) — regras de manutenção/déficit/superávit.
* `## Definição de Cálculos, Metas e Prescrição — V1.0` (linha 3345) — ME-001 a ME-009, os princípios arquiteturais que já vínhamos seguindo (separação cálculo×meta) sem saber que estavam formalizados ali.

Não foi "falsa premissa de que não havia fórmula" por escolha — foi a leitura ter parado 1.224 linhas antes do fim por confiar numa contagem de linhas que se mostrou errada para este arquivo especificamente (não investigado o motivo exato — possivelmente um caractere de quebra de linha não padrão em algum trecho; o Read tool, que lê por conteúdo e não por contagem prévia, não tem esse problema). Lição registrada: para arquivos grandes, ler até o Read tool não devolver mais conteúdo, nunca confiar numa contagem de linhas de uma ferramenta externa para decidir "isso é o fim".

O restante deste relatório trata do fechamento dos 5 gaps do Painel Web já documentados na tarefa anterior (com plano) e da implementação da matemática de macros/meta energética/qualidade que a leitura completa revelou.

## Backend — `calcular_motor_metabolico_v1` (migration `20260919100000`)

Função continua **pura** (ME-005/ME-006 — nenhum `insert`/`update`/`delete`). Passa a ler também `objetivo_codigo`, `massa_magra_kg` e `percentual_gordura` da mesma anamnese SSOT que já fornecia peso/altura, e devolve 3 blocos novos, todos informativos:

### 1. `macros_recomendados` — Protocolos de Macronutrientes V1.0

**MACRO-001 (percentual energético)** — Seção 4 do bloco, matemática copiada literalmente:

```
gramas_proteina = kcal × percentual_proteina ÷ 4
gramas_carboidrato = kcal × percentual_carboidrato ÷ 4
gramas_gordura = kcal × percentual_gordura ÷ 9
```

Parâmetros default versionados (`MACRO-001-default-v1`): 25% proteína / 45% carboidrato / 30% gordura (soma 100%, conforme exigido pela Seção 3: "X + Y + Z = 100%").

**MACRO-002 (proteína/gordura g/kg + carboidrato residual)** — Seção 5, também copiada literalmente:

```
P(g) = peso × meta_proteína_g/kg
G(g) = peso × meta_gordura_g/kg
C(kcal) = energia-alvo − proteína(kcal) − gordura(kcal)
C(g) = C(kcal) ÷ 4
```

Parâmetros default versionados (`MACRO-002-default-v1`): 1,6 g/kg proteína, 0,8 g/kg gordura (acima do piso clínico de 0,6 g/kg já travado em `validar_e_salvar_meta`/N08).

**Validação matemática (Seção 16 do bloco de macros)** — `kcal proteína + kcal carboidrato + kcal gordura = energia-alvo`, com tolerância de arredondamento de 2 kcal (o documento explicitamente pede essa tolerância, sem especificar o valor — 2 kcal foi escolhido por ser bem abaixo de qualquer erro perceptível numa dieta e por sobrar folga generosa sobre o arredondamento de 1 casa decimal usado nos gramas). `validacao_soma_ok: boolean` fica no JSON de cada protocolo.

`energia-alvo` = a `recomendacao_media_diaria` calculada no bloco 2 abaixo — nunca a meta que o usuário/profissional digitou (essa continua 100% manual, ME-005).

### 2. `energia_recomendacao` — Definição da Meta Energética V1.0

* `objetivo_codigo = 'manter_peso'` → `recomendação = TDEE médio` (Seção 4: "Meta energética = TDEE").
* `objetivo_codigo in ('perder_peso', 'reduzir_gordura_corporal')` → `recomendação = TDEE médio × (1 − 15%)` (Seção 5: "Meta energética = TDEE − déficit", déficit parametrizado e versionado como `DEFICIT-001-conservador-v1`).
* Demais objetivos (ganho de peso/massa muscular/recomposição/performance esportiva) → **sem recomendação automática** — o próprio documento diz, nas Seções 6/7/8 desse mesmo bloco, que esses exigem avaliação profissional ("não deverá aplicar automaticamente um superávit elevado", "não deverá ser tratada simplesmente como TDEE±X", "a definição da meta energética deverá ser do profissional").

**Simplificação documentada, não escondida**: a Seção 5 pede "uma tabela parametrizada de déficit energético por perfil" considerando no mínimo 6 fatores (objetivo, peso, TDEE, nível de atividade, condições relevantes, qualidade dos dados). Implementei **1 parâmetro único versionado** (15% fixo), não a tabela completa de 6 dimensões — decisão de escopo pelo tempo disponível, registrada aqui e na tabela de compliance, não escondida. Uma tarefa futura pode expandir para a tabela completa sem quebrar o contrato desta.

### 3. `qualidade` — Score de Qualidade (Bloco 15/Regra 25)

O documento não define fórmula (só exige "o registro do score de qualidade"). Heurística explícita pedida pelo fundador, implementada literalmente:

* **Alta**: usa decomposição (NEAT+EAT, `estrategia_tdee = 'decomposicao_parcial'`) **e** tem massa magra **e** percentual de gordura confirmados.
* **Média**: usa PAL como fallback **ou** falta composição corporal.
* **Baixa**: TMB não pôde ser calculada (dados antropométricos insuficientes).

## Verificação ao vivo — conferência manual completa

`atleta1000@teste.com`, peso=80kg, altura=175cm, idade=30 (calculada de `data_nascimento`), sexo=M:

* **TMB** = 10×80 + 6,25×175 − 5×30 + 5 = **1748,75** — bateu exato com o valor devolvido pela RPC.
* **Teste 1** (perder_peso, 1 atividade registrada + massa_magra/percentual_gordura preenchidos): `qualidade.score = "alta"`; `energia_recomendacao.estrategia = "deficit_conservador"`, `recomendacao_media_diaria = tdee_medio × 0,85` batendo exato; MACRO-001 com proteína ≈25% da energia e soma das kcal dentro de 2kcal do alvo; MACRO-002 com proteína = 80×1,6 = **128g** exato, gordura = 80×0,8 = **64g** exato, carboidrato residual fechando a soma exatamente.
* **Teste 2** (manter_peso, sem atividade registrada, sem composição corporal): `qualidade.score = "media"` com os 2 motivos esperados (`estrategia_fallback_pal`, `sem_composicao_corporal_confirmada`); `energia_recomendacao.estrategia = "manutencao"`, `recomendacao_media_diaria = tdee_medio` exato.
* 21/21 checks. Perfil do usuário de teste (data de nascimento/sexo, alterados temporariamente para o teste) restaurado ao valor original; anamneses de teste removidas.

## Painel Web (React) — os 5 gaps fechados

1. **Histórico de peso na Anamnese Profissional**: `AnamneseProfissionalView.tsx` agora chama `anamnese_historico_peso` ao carregar e após salvar, mostrando peso atual/anterior/30 dias/3 meses/6 meses/12 meses/maior/menor/variação — só os campos que vierem preenchidos.
2. **Busca de atividades**: campo de filtro acima da lista de linhas de rotina (só aparece quando o catálogo tem mais de 8 itens — hoje tem 99), filtra a lista de opções do `<select>` em tempo real.
3. **Blocos Idoso e Recomposição Corporal**: mesmo padrão "Ativar bloco" já usado em Atleta/Diabetes/Renal — checkbox explícito, o profissional decide clinicamente quando aplicar (sem inferência automática, diferente do app).
4. **`MotorMetabolicoV1Card.tsx`** ganhou: badge de Qualidade dos Dados (Alta/Média/Baixa com motivos), card de "Recomendação do sistema" (com o aviso explícito "nunca é gravado automaticamente como meta"), e os 2 protocolos de macros lado a lado (MACRO-002 em destaque como principal, MACRO-001 como alternativa), com alerta visual se `validacao_soma_ok` vier `false`.
5. **`AdminComplianceAnamnese.tsx`** atualizada — Blocos 4/6/12 passam a "Implementado" nas 3 camadas; Blocos 13/15 passam a "Implementado" em Backend/Web (App fica "Pendente" — fora do `ENTREGÁVEL` desta tarefa, que pediu explicitamente só Web + Backend); nova linha "Meta Energética" que não existia na tabela original.

**Verificado ao vivo** pelo caminho profissional (`educarmo@gmail.com` + paciente-seed): `anamnese_historico_peso` devolvendo peso atual/anterior corretos após 2 anamneses; `calcular_motor_metabolico_v1` devolvendo `qualidade`/`energia_recomendacao`/`macros_recomendados` populados. 8/8 checks. Dados de teste limpos.

`npx tsc -b` / `npm run build` / `npm run lint`: limpos (2 warnings pré-existentes em arquivo não tocado).

## Fora do escopo desta tarefa (explícito no ARQUIVOS/ENTREGÁVEL: só Web + Backend)

* **App Flutter** não foi tocado — os novos campos (`qualidade`, `energia_recomendacao`, `macros_recomendados`) já chegam no JSON que `ResultadoMotorMetabolicoPage` consome, mas a tela ainda não os exibe. Plano: estender a Seção A (Resultados Calculados) numa tarefa futura com ARQUIVOS incluindo Flutter.
* **Tabela completa de déficit** (6 fatores) da Seção 5 — implementado 1 parâmetro único versionado, não a tabela inteira (ver seção acima).
* **MACRO-003/004/005** (MLG, proteína prioritária, personalizado pelo profissional) — RESTRIÇÃO pediu "no mínimo MACRO-001 e MACRO-002"; os outros 3 ficam de fora por ora, catálogo `Código | Protocolo` já documentado no comentário SQL para quando forem implementados.

## ACEITE (conferido item a item)

* ✅ Web Panel com 100% dos blocos (Idoso/Recomposição, histórico de peso e busca).
* ✅ Backend calculando MACRO-001 e MACRO-002 e gravando o Score de Qualidade — "gravando" aqui significa "devolvendo no JSON de resultado do motor" (a função continua pura por desenho, ME-005/006; nada é persistido automaticamente como meta).

## Entregável

* Migration `20260919100000_motor_v1_macros_qualidade_recomendacao_energetica.sql` — já aplicada em produção e verificada ao vivo.
* Painel Web: `AnamneseProfissionalView.tsx`, `MotorMetabolicoV1Card.tsx`, `database.ts`, `AdminComplianceAnamnese.tsx` atualizados.
* Branch `fix/anamnese-gaps-macros`, a partir de `main`, **não mesclada** (Regra 18 — aguardando autorização explícita do fundador). 4 commits divididos por camada (backend, web-gaps, tabela de compliance).
