# 20261103_0002 — Calorias por refeição + total diário no Histórico; todos os Protocolos de Macros no Resultado

## Contexto

Refinamento das telas de Resultado da Avaliação (`ResultadoMotorMetabolicoPage` — a tarefa chamou de "ResultadoAvaliacaoPage", mesmo arquivo) e Histórico/Detalhes (`AnamneseDetalhesPage`). Duas auditorias prévias a qualquer código, pedidas implicitamente pela tarefa ("Garanta que esses dados sejam devidamente carregados... tanto no preenchimento recente quanto em consultas históricas antigas" / "cada um dos protocolos suportados pelo Motor Metabólico") — e as duas revelaram premissas da tarefa desalinhadas com o sistema real.

## Auditoria — achados antes de codar

**1. Calorias por refeição**: `DadosComplementaresAnamnese.refeicoesDiariasHabituais` (RELATÓRIO 20260922_0002) já é um `List<Map<String, dynamic>>` com `kcal`/`proteina_g`/`carboidrato_g`/`gordura_g` por refeição (preenchidos pela IA de interpretação de texto), já lido de volta corretamente por `dadosComplementaresDeJson` e já chegando em `AnamneseDetalheModel.complementares` — só nunca era renderizado em `AnamneseDetalhesPage`. Nenhuma migration nova precisou existir — o dado já estava lá, só faltava UI. Confirmado também que `kcal`/macros ficam **ausentes da chave** (não `null`) sempre que a refeição nunca passou pela IA — inclusive em QUALQUER anamnese (antiga ou recente), não é uma questão de "antiga vs. recente": é "rodou a IA" vs. "não rodou".

**2. Protocolos de macronutrientes**: a tarefa nomeou protocolos fictícios ("Equilibrado/Hipertrofia, High Protein, Low Carb, Ciclo de Carboidratos") que **não existem em nenhum lugar do sistema** (nem em `docs/motor_metabolico.txt`, nem no SQL, nem no Flutter). O catálogo real, já implementado desde o RELATÓRIO `20260920_0001` (`supabase/migrations/20260920100000_...sql`), é:

| Código | Nome real |
|---|---|
| MACRO-001 | Percentual energético |
| MACRO-002 | Proteína/gordura g/kg + carboidrato residual |
| MACRO-003 | Proteína por massa magra + gordura g/kg + carboidrato residual |
| MACRO-004 | Proteína prioritária + carboidrato variável |
| MACRO-005 | Personalizado pelo profissional |

A RPC `calcular_motor_metabolico_v1` **já calcula os 5** desde aquela migration — mas o modelo Dart (`MacrosRecomendadosResultado`) só expunha MACRO-001/002/003, e a UI (`_buildProtocoloSelector`) só oferecia esses 3 como `ChoiceChip` (seletor que PREENCHE campos, nunca uma exibição completa com VET/percentuais). MACRO-005 nunca vem com gramas calculadas pra este app (é "personalizado pelo profissional", calculado numa RPC separada do Painel Web, `validar_macro_personalizado`) — a RPC devolve só `disponivel`/`motivo`, nunca `proteina_g`/`carboidrato_g`/`gordura_g`.

Seguindo a Restrição explícita ("não criar tabelas duplicadas... se os cálculos puderem ser resolvidos via Motor Metabólico/UI"): nenhuma migration nova — só passamos a LER e EXIBIR o que a RPC já devolvia.

## 1. Calorias por refeição + total diário (AnamneseDetalhesPage)

- Novo `RefeicaoHabitualResumo` (`anamnese_models.dart`) — leitura tipada de cada elemento de `refeicoesDiariasHabituais`; `AnamneseDetalheModel.refeicoesHabituais` (getter) expõe a lista já parseada.
- Nova seção "Refeições diárias habituais" ao final da Alimentação: cada refeição mostra número, horário, badge "Fora de casa" (quando aplicável), descrição, e `{kcal} kcal` + `P/C/G` — ou o fallback "Sem cálculo de calorias/macros para esta refeição." quando a IA nunca rodou naquela linha.
- Card "Total do Dia" ao final da lista: soma só as refeições que TÊM o dado (nunca inventa um valor pra refeição sem cálculo); fallback "Sem dados suficientes para calcular o total do dia." quando NENHUMA refeição tem nada — nunca mostra "0 kcal".
- Seção inteira some quando não há nenhuma refeição habitual registrada (Regra 23 — nenhuma seção vazia inventada).

## 2. Todos os protocolos de macros, com VET + gramas + porcentagem (ResultadoMotorMetabolicoPage)

- `MacrosRecomendadosResultado` ganhou `macro004`/`macro005` (a RPC já devolvia, só não eram lidos).
- `MotorMetabolicoResultadoView._buildMacrosRecomendadosEstatico` (widget compartilhado entre as duas telas) passou a mostrar um card por protocolo REALMENTE disponível E com gramas calculadas (filtro `disponivel && proteinaG != null` — exclui MACRO-005 automaticamente, sem lista hardcoded de exceções), cada card com: código + nome real, "VET / Meta Calórica" (a mesma energia-alvo em todos, já que os protocolos são formas diferentes de DISTRIBUIR o mesmo VET, nunca VETs diferentes) e `P {g}g ({%}) · C {g}g ({%}) · G {g}g ({%})` — percentuais calculados a partir dos gramas (`gramas × 4 ou 9 ÷ energia-alvo`), nunca um valor novo inventado pela RPC.
- Row horizontal rolável (`ListView.separated` com `scrollDirection: Axis.horizontal`) — "permita comparar ou navegar visualmente entre as opções", sem empurrar o resto da tela pra baixo.
- `ResultadoMotorMetabolicoPage` liga `mostrarMacrosRecomendados: true` na Seção A (antes só a tela de Detalhes usava); o seletor INTERATIVO da Seção B (`ChoiceChip`, preenche os campos editáveis) continua existindo — ganhou um 4º chip, MACRO-004, com a fórmula replicada exatamente da RPC (proteína g/kg + gordura por percentual mínimo da energia digitada + carboidrato residual). As duas UIs (comparativo leitura vs. seletor de preenchimento) coexistem, cada uma com sua função.
- `AnamneseDetalhesPage` ganha automaticamente os mesmos 4 protocolos no card de Resultado do Motor Metabólico (mesmo widget compartilhado, RELATÓRIO `20261103_0001`).

## Testes

- `anamnese_detalhes_page_test.dart`: +4 testes (seção some sem refeições; kcal/macros por refeição + total; fallback por refeição sem travar o total; fallback do total quando nenhuma refeição tem dado).
- `resultado_motor_metabolico_page_test.dart`: +1 teste (MACRO-004 na Seção B); +2 testes (novo grupo "Seção A — Comparativo de Protocolos", incluindo a confirmação explícita de que MACRO-005 nunca aparece).
- Ajuste de fixtures existentes (`MacrosRecomendadosResultado` agora exige `macro004`/`macro005`) e de 2 asserções que colidiram com o novo card de VET (texto duplicado "1788 kcal"/percentuais).

## Verificação

- `flutter analyze` (lib/test de nutrição): sem issues.
- `flutter test` completo: **593/593** (era 586/586, +7).
- Nenhuma migration/RPC nova — Restrição cumprida; tudo resolvido lendo dados que o Motor Metabólico já calculava.

## Arquivos

- `lib/features/nutricao/data/models/anamnese_models.dart` (`RefeicaoHabitualResumo` + getter).
- `lib/features/nutricao/presentation/pages/anamnese_detalhes_page.dart` (seção de refeições + total diário).
- `lib/features/nutricao/data/repositories/meta_bem_estar_repository.dart` (`macro004`/`macro005`).
- `lib/features/nutricao/presentation/widgets/motor_metabolico_resultado_view.dart` (comparativo de protocolos).
- `lib/features/nutricao/presentation/pages/resultado_motor_metabolico_page.dart` (`mostrarMacrosRecomendados: true` + chip MACRO-004).
- `assets/i18n/pt.json`, `en.json`, `es.json`.
- `test/features/nutricao/presentation/pages/anamnese_detalhes_page_test.dart`.
- `test/features/nutricao/presentation/pages/resultado_motor_metabolico_page_test.dart`.

Branch `feat/anamnese-historico-refeicoes-protocolos-macro`, a partir de `main`.
