# RELATÓRIO 20260920_0001 — Motor Metabólico V1: MACRO-003/004/005, Tabela de Déficit Multicritério, Integração no Flutter

**Branch:** `feat/motor-macros-deficit-final` (a partir de `main`, que já continha `fix/anamnese-gaps-macros` mesclada).
**Data:** 2026-09-20.

## Contexto

O relatório anterior (`20260918_0002_anamnese_gaps_macros.md`) documentou explicitamente, como "fora de escopo", 3 gaps: MACRO-003/MACRO-004/MACRO-005 não implementados; a "tabela parametrizada" de déficit da Seção 5 substituída por 1 parâmetro fixo (15%); e o App Flutter não exibindo nada disso. O fundador não aceitou essas simplificações — esta tarefa fecha os 3 gaps, sem cortar escopo.

## 1. Backend — MACRO-003/004/005

Migration `20260920100000_motor_v1_macros_003_004_005_deficit_multicriterio.sql`, `create or replace` sobre `calcular_motor_metabolico_v1` (continua função **pura** — ME-005/ME-006, nenhum insert/update/delete).

- **MACRO-003** (Seção 6 — proteína por massa livre de gordura): `P(g) = massa_magra_kg × 2,0 g/kg_MLG` (constante `MACRO-003-default-v1`); `G(g) = peso × 0,8 g/kg` (mesmo parâmetro de gordura do MACRO-002, "g/kg de peso" explicitamente autorizado pelo texto); carboidrato residual. **Validação de disponibilidade exigida pela tarefa**: só calculado quando `massa_magra_kg` não é nulo — senão o bloco vem com `disponivel: false` e um aviso `macro_003_sem_massa_magra_kg_disponivel` é adicionado à lista de avisos (nunca um fallback silencioso). Fonte/data da MLG preservadas (`massa_magra_data_medicao`, a mesma `peso_data_medicao` da anamnese — único campo de data de composição corporal existente no schema).
- **MACRO-004** (Seção 7 — proteína prioritária + carboidrato variável): proteína por g/kg de peso com parâmetro próprio (1,8 g/kg, mais alto que o 1,6 do MACRO-002, pra genuinamente diferenciar "prioridade"), gordura como **limite mínimo fixo** (25% da energia-alvo — o "parâmetro de gordura" que o texto pede), carboidrato absorve toda a energia restante ("variável", por construção). Validado como os demais (carboidrato não pode ficar negativo).
- **MACRO-005** (Seção 8 — personalizado pelo profissional): por definição, não é um valor que o motor calcula sozinho (o profissional define os números). O catálogo de 5 protocolos passa a incluir a entrada `macro_005` com `disponivel: true, calculo_automatico: false` e o motivo explicando a arquitetura. A exigência real do texto para este protocolo — "o sistema deverá validar a consistência matemática dos valores" — foi implementada como uma função nova e independente, **`validar_macro_personalizado(energia_alvo, proteina_g, carboidrato_g, gordura_g)`**, pura, que confere `kcal proteína + kcal carboidrato + kcal gordura = energia-alvo` (mesma tolerância de 2kcal da Seção 16) e devolve `{valido, soma_kcal_calculada, diferenca_kcal}`. Não grava nada; fica disponível pra ser chamada de onde o profissional definir a meta (não wireada no Painel Web nesta tarefa — Web não estava no `ARQUIVOS`/`ENTREGÁVEL`).

## 2. Backend — Tabela de Déficit Multicritério (`DEFICIT-002-multicriterio-v1`)

Substitui o `DEFICIT-001-conservador-v1` (15% fixo). O documento não define os números da tabela — só exige que ela **exista, considere os 6 fatores mínimos e seja versionada** ("Os parâmetros deverão ser versionados e passíveis de atualização"). A tabela implementada:

| Fator | Fonte | Efeito |
|---|---|---|
| **Nível de atividade** | `anamneses.rotina_diaria` (5 níveis, já coletado mas nunca lido pelo motor antes) | Define o **percentual base**: sentado 20% → trabalho fisicamente intenso 10% (protege desempenho/energia disponível em quem já é muito ativo). Sem valor informado → 15% (padrão) + aviso. |
| **TDEE** | `tdee_medio` calculado | Ajuste em pontos percentuais por faixa absoluta: <1800kcal → −3pp (mais conservador perto da TMB); ≥2600kcal → +2pp; faixa intermediária → 0. |
| **Presença de condição relevante** | `anamneses.possui_condicao_saude` | `true` → −5pp (mais conservador, sem avaliação profissional). |
| **Qualidade dos dados** | `qualidade.score` (já calculado nesta mesma função) | `'media'` → −3pp; `'alta'` → 0. (`'baixa'` nunca chega aqui — TMB nulo já bloqueia toda a recomendação energética antes.) |
| **Peso** | `peso_kg` | Não entra como ajuste percentual — vira **teto absoluto** do déficit em kcal/dia: `min(déficit_calculado, peso_kg × 10)`. |
| **Objetivo** | `objetivo_codigo` | Decide SE este ramo roda (`perder_peso`/`reduzir_gordura_corporal`) — inalterado desta migration. |

Fluxo: percentual base + ajustes → limitado a **[5%, 20%]** → déficit em kcal → limitado pelo teto de peso → recomendação final = `TDEE − déficit`, **nunca abaixo da TMB** (mesmo piso que a trava clínica de `validar_e_salvar_meta`/N08 já aplica na gravação — esta recomendação informativa nunca sugere algo que a trava de gravação rejeitaria). O JSON de saída (`energia_recomendacao.fatores_considerados`) expõe cada fator e ajuste aplicado, pra auditoria/transparência.

## 3. Verificação ao vivo (backend)

Script Node temporário (usuário real `atleta1000@teste.com`, autenticado via magic link — nunca `service_role` pra ler os dados do usuário), 4 cenários:

1. **Sedentário + condição relevante + sem massa magra**: base 20% − 5pp (condição) − 3pp (qualidade média) = 9% líquido (ajuste de TDEE também aplicado); `macro_003.disponivel = false` + aviso presente. ✅
2. **Trabalho fisicamente intenso + sem condição + com massa magra (ainda PAL)**: base 10%; qualidade continua "média" mesmo com composição corporal (a heurística de "alta" exige decomposição por atividade, não só composição corporal — confirmado como comportamento correto, não bug); MACRO-003 (proteína = MLG×2,0, gordura = peso×0,8) e MACRO-004 (proteína = peso×1,8, gordura = 25% mínimo) conferidos byte a byte contra o cálculo manual. ✅
3. **`validar_macro_personalizado`**: soma correta → `valido: true`; soma incorreta (diferença de ~200kcal) → `valido: false`, com a diferença exata reportada. ✅
4. **Regressão — `manter_peso`**: continua `estrategia: 'manutencao'`, `recomendacao_media_diaria = tdee_medio` exato, sem `fatores_considerados` (só existe no ramo de déficit). ✅

Todas as anamneses de teste inseridas foram removidas ao final; confirmado que a anamnese mais recente do usuário voltou a ser exatamente a original (nenhum dado real tocado — `anamneses` é INSERT-only, os testes só inseriram e depois apagaram linhas novas). Migration aplicada em produção via `supabase db push --linked`, `supabase migration list --linked` confirma `local=remote`.

## 4. Flutter — App consumindo a nova inteligência

`meta_bem_estar_repository.dart` ganha 4 classes novas espelhando o JSON da RPC (`QualidadeMotorResultado`, `EnergiaRecomendacaoResultado`, `MacroProtocoloResultado`, `MacrosRecomendadosResultado`), todas usadas por `MotorMetabolicoV1Resultado` (agora com `qualidade`, `energiaRecomendacao`, `macrosRecomendados`, `pesoKg`, `massaMagraKg`).

`ResultadoMotorMetabolicoPage`:

- **Seção A (só leitura)**: badge de Qualidade (Alta/Média/Baixa + motivos traduzidos) e card de Recomendação Energética (valor + "Manutenção"/"Déficit de X%"), ambos condicionais (`null` quando o motor não tem dado suficiente). O card de recomendação tem um botão "Usar este valor em Calorias" que só **copia** o número pro campo — continua editável, nada é salvo sozinho.
- **Seção B (editável)**: seletor de protocolos **MACRO-001/002/003** (exatamente os 3 citados como exemplo na tarefa) via `ChoiceChip`. Ao selecionar um protocolo, o app converte os percentuais/g-por-kg **do próprio JSON da RPC** (nunca um número reinventado no Dart) sobre o valor atual do campo Calorias, preenchendo Proteína/Carboidrato/Gordura — recalcula automaticamente se o usuário depois mudar Calorias com um protocolo já selecionado. MACRO-003 fica desabilitado (`ChoiceChip.onSelected: null` + tooltip) quando `massa_magra_kg` não está disponível. Em nenhum momento os campos deixam de ser editáveis, e a gravação continua exigindo o toque em "Salvar Minha Meta" (ME-005 preservada — verificado por teste que o usuário pode sobrescrever o valor pré-preenchido livremente).

35 chaves i18n novas em pt/en/es (score de qualidade, motivos, recomendação energética, seletor de protocolos) — diff automatizado confirma as 33 chaves `resultado_motor_*` idênticas nos 3 idiomas, e todas as chaves referenciadas no Dart (estáticas e a dinâmica `resultado_motor_qualidade_motivo_$motivo`) existem em `pt.json`.

## 5. Testes e verificação

- 5 testwidgets novos em `resultado_motor_metabolico_page_test.dart` (badge de qualidade + motivo, recomendação de déficit com o botão "usar", recomendação de manutenção, seleção de MACRO-002 convertendo g/kg em gramas exatas e mantendo os campos editáveis, recálculo ao trocar Calorias, MACRO-003 desabilitado sem massa magra).
- 2 arquivos de teste pré-existentes ajustados só pelos novos parâmetros obrigatórios do model (`confirmar_anamnese_page_test.dart`, e o próprio arquivo acima) — nenhuma asserção de comportamento pré-existente mudou.
- `flutter analyze`: 30 avisos pré-existentes, os mesmos de antes desta tarefa — zero novo.
- `flutter test`: **496/496** (491 anteriores + 5 novos), zero regressão.
- `web_painel`: `AdminComplianceAnamnese.tsx` atualizada pra refletir o Bloco 13/Meta Energética/Bloco 15 agora "implementado" no App (Web fica "parcial" no Bloco 13 — `MotorMetabolicoV1Card.tsx` ainda só mostra MACRO-001/002, fora do escopo desta tarefa); `npx tsc -b` limpo.

## Fora do escopo desta tarefa (documentado, não esquecido)

- `MotorMetabolicoV1Card.tsx` (Painel Web) não foi ampliado pra mostrar MACRO-003/004/005 nem os fatores do déficit multicritério — `ARQUIVOS`/`ENTREGÁVEL` desta tarefa pediram só Backend + Flutter.
- `validar_macro_personalizado` (MACRO-005) não está wireada em nenhuma tela ainda (nem Web nem App) — existe como função pura pronta pra uso futuro no fluxo de prescrição profissional.
- App não expõe um seletor pra MACRO-004 (só 001/002/003, conforme o exemplo literal da tarefa: "ex: MACRO-001, 002 ou 003") — a RPC já devolve MACRO-004 calculado, caso uma tarefa futura queira expor.
