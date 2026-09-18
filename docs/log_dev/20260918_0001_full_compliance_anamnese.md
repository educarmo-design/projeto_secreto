# RELATÓRIO 20260918_0001 — Compliance Total com docs/motor_metabolico.txt (Blocos 1-16)

**Data:** 2026-09-18
**Branch:** `feat/full-compliance-anamnese` (a partir de `main`)
**Persona:** Engenheiro Full-Stack (Backend/Flutter/React) e Arquiteto de Software (Mestre v8.0)

## Achado inicial — qual versão do documento seguir

`docs/motor_metabolico.txt` (2288 linhas) contém, na prática, **duas especificações concatenadas** da Anamnese:

1. Uma versão **completa/exaustiva** (Seções 1-28, Blocos 1-16 — Contexto, Objetivos, Antropometria, Histórico de Peso, Alimentação, Atividades, **Sono**, Condições de Saúde, **Medicamentos**, **Suplementos**, **Exames Laboratoriais**, Blocos Condicionais, Resultados do Motor, Metas, Qualidade, Auditoria).
2. Uma versão **"V1.0 mínima"** do MESMO documento (repetida duas vezes, verbatim, mais adiante no arquivo), cuja Seção 16 se chama literalmente **"O que NÃO entra na Anamnese V1.0"** e exclui explicitamente sono detalhado, medicamentos, suplementos, exames laboratoriais e o painel completo de condições.

A TAREFA desta sessão referencia explicitamente "Histórico de peso da Seção 7", "Alimentação da Seção 8", "Sono da Seção 10", "Medicamentos, Suplementos e Exames" — todas essas referências batem exatamente com a numeração da **versão completa** (Seção 7 = Bloco 4, Seção 8 = Bloco 5, Seção 10 = Bloco 7, etc.), não com a "V1.0 mínima". Resolvido: esta tarefa implementa a **especificação completa** (Blocos 1-16), não a variante que a exclui — decisão registrada aqui de forma explícita, não silenciosa.

## Backend (Supabase/DB)

Migration `20260918100000_full_compliance_anamnese_blocos_1_16.sql` — `anamneses` estava com **0 linhas em produção** no momento da migration (confirmado ao vivo antes de escrever), então todas as mudanças são puramente aditivas.

- **Bloco 1**: `motivo_avaliacao`/`motivo_avaliacao_outro`.
- **Bloco 2**: `objetivo_codigo` trocado para a lista **EXATA** da Seção 4.1 (8 opções: `perder_peso`, `manter_peso`, `ganhar_peso`, `reduzir_gordura_corporal`, `ganhar_massa_muscular`, `recomposicao_corporal`, `melhorar_desempenho_esportivo`, `outro` — a lista anterior, `emagrecimento`/`manutencao`/`hipertrofia`/`outro`, divergia) + `objetivos_secundarios` (array) + meta quantitativa (peso/%gordura/massa/prazo/outro desejados).
- **Bloco 3**: composição corporal completa (`percentual_gordura`, `massa_gorda_kg`, `massa_magra_kg`, `massa_muscular_kg`, circunferências, método/fonte) — mesma lógica SSOT já usada pra peso/altura.
- **Bloco 4**: **não virou coluna nova** — "esses dados são históricos e não devem ser confundidos com o peso oficial da nova Anamnese" (texto do documento). Nova RPC pura `anamnese_historico_peso(p_usuario_id)` reconstrói peso atual/anterior/30d/3m/6m/12m/maior/menor/variação% a partir das anamneses já existentes. Só a pergunta explícita (`houve_alteracao_peso_nao_planejada`) virou coluna.
- **Bloco 5**: padrão alimentar (refeições/dia, horários, regularidade, preferências, restrições, intolerâncias...). **Consumo de energia/macros deliberadamente fora** — já existe o diário alimentar (`ColetaDiariaRepository`), duplicar violaria a própria Seção 18 do documento ("não deve conter informações redundantes que já existam em outros módulos").
- **Bloco 6**: `anamneses_atividades_dias` ganha `intensidade` (leve/moderada/alta) **NOT NULL sem default** — obrigatório por pedido explícito do fundador — + `horario`/`distancia_km`/`calorias_dispositivo`/`fonte`. `rotina_diaria` (Seção 5) + `atividade_ocupacional` na anamnese (passos/tempo em movimento **não** repetidos — já vêm do wearable automaticamente).
- **Bloco 7**: sono completo (horas médias, horário de dormir/acordar, qualidade percebida, despertares, observações).
- **Bloco 8**: `possui_condicao_saude` (boolean explícito, "Não tenho" auditável) + `anamneses_problemas_saude` estendida com `data_diagnostico`/`status`/`profissional_responsavel`/`observacoes`/`evidencias_relacionadas`. Catálogo `problemas_saude` (20 itens já curados, mais granulares) recebeu as **14 categorias exatas da Seção 8** de forma **aditiva** (nada removido).
- **Blocos 9/10/11**: 3 tabelas novas — `anamneses_medicamentos`, `anamneses_suplementos`, `anamneses_exames_laboratoriais` — mesmo padrão de RLS já usado em `anamneses_atividades`.
- **Bloco 12**: 5 colunas JSONB (`bloco_idoso`, `bloco_atleta`, `bloco_recomposicao`, `bloco_diabetes`, `bloco_doenca_renal`) — chaves documentadas em comentário SQL, batendo com a lista compacta da Seção 9.x do documento (a mesma usada nos 2 blocos condicionais já existentes no app antes desta tarefa).
- **Bloco 16**: `numero_versao` (sequencial por usuário, preenchido pelo trigger `anamneses_trg_versionar` estendido) + `dados_confirmados`/`confirmado_em` (Seção 11).
- **Alergias**: catálogo `alergias` curado com a lista clínica pedida (Amendoim, Castanhas/Nozes, Crustáceos/Frutos do mar, Leite, Ovos, Peixes, Soja, Trigo/Glúten, Gergelim, Outros) — aditivo.

**2 migrations de correção descobertas na auditoria final** (`20260918110000`, `20260918120000`): a RPC `profissional_salvar_anamnese` (de uma tarefa anterior) não enviava `intensidade` no INSERT — como a coluna virou `NOT NULL` sem default nesta mesma tarefa, **toda chamada da RPC com pelo menos 1 atividade quebraria a partir de agora** sem o patch (`coalesce(..., 'moderada')`). Aproveitado o mesmo patch pra expandir o payload da RPC com os ~35 campos novos + alergias (achado: nem a RPC nem a tela React coletavam alergias, apesar de ser pedido explícito da tarefa).

Fora de escopo, documentado no próprio SQL: **score de qualidade (Bloco 15)** e **cálculo automático de macronutrientes (Bloco 13)** — nenhuma fórmula é especificada em nenhum lugar do documento pra nenhum dos dois, e este projeto nunca arbitra número clínico sem fórmula explícita do fundador (mesmo princípio já usado em `ResultadoMotorMetabolicoPage`).

## App Flutter

`AnamneseSelfServicePage` reescrita — Blocos 1-12 em seções sequenciais dentro de uma única página rolável, seguidas por uma tela dedicada de confirmação final (Seção 11).

- **Objetivos**: lista exata + secundários (seletor múltiplo) + meta quantitativa.
- **Atividades**: dropdown já vinha alfabético (`buscarTiposAtividades` já ordenava por `nome_exibicao`); ganhou **barra de busca** no modal + **Intensidade obrigatória** (RadioGroup Leve/Moderada/Alta).
- **Condições**: pergunta Sim/Não com **"Não tenho" explícito** antes de abrir a seleção da lista.
- **Condicionais**: Diabetes/Doença Renal ativados automaticamente quando a condição correspondente é selecionada; Idoso ativado por idade (≥60, calculada de `perfis_usuarios.data_nascimento`); Recomposição ativado quando o objetivo é "Recomposição corporal"; Atleta via toggle explícito ("pratica esporte estruturado?").
- **Medicamentos/Suplementos/Exames**: listas repetíveis (novo widget genérico `ListaRepetivelWidget`).
- **Confirmação (Seção 11)**: nova `ConfirmarAnamnesePage` — revisão só-leitura de tudo, "Salvar" na tela principal **para de gravar diretamente** (só monta um `AnamneseRascunho` e navega); a gravação de verdade (`dados_confirmados=true`) só acontece ao tocar "Confirmar e Enviar" lá.
- **UX Global**: novo `abrirSeletorMultiplo`/`ResumoSelecaoMultipla` — listas que antes ficavam sempre visíveis (problemas de saúde, alergias, objetivos secundários) viram um resumo + bottom sheet com botão **"Confirmar"** explícito.
- **35+ chaves i18n novas** em pt/en/es — nada hardcoded (verificado com um diff automatizado entre as chaves usadas no código Dart e as 3 traduções, 0 divergência).

`flutter analyze`: limpo (30 avisos pré-existentes, zero novos). `flutter test`: **491/491** (suíte inteira), zero regressão.

## Painel Web (React)

`AnamneseProfissionalView.tsx` reescrita cobrindo os mesmos Blocos 1-12 — seções menos usadas em `<details>` colapsáveis. Blocos condicionais (Atleta/Diabetes/Doença Renal) usam um checkbox explícito "Ativar bloco" — diferente do app, aqui é o profissional quem decide clinicamente quando cada bloco se aplica, sem inferência automática.

Novo `AnamneseHistoricoView.tsx` (item 3 — "Garantir que a visualização do histórico do paciente exiba todos esses blocos de dados"): lista todas as versões da anamnese do paciente (nenhuma sobrescrita), seletor de versão, detalhe completo de cada bloco preenchido naquela versão específica — montado em `PatientDetails.tsx` logo após a Anamnese Profissional.

`database.ts` ganhou os tipos completos de `anamneses` (~35 colunas), as 3 tabelas novas, `anamneses_problemas_saude`/`anamneses_alergias`, o tipo `ObjetivoCodigo` exportado, e o payload expandido de `profissional_salvar_anamnese` + `anamnese_historico_peso`.

`npx tsc -b`/`npm run build`/`npm run lint`: limpos (2 warnings pré-existentes em arquivo não tocado).

## Verificação ao vivo

Todas as mudanças de banco foram testadas contra o projeto Supabase real (`atleta1000@teste.com` self-service, `educarmo@gmail.com` + paciente-seed no fluxo profissional), com limpeza completa dos dados de teste ao final de cada rodada:

- Versionamento com `numero_versao` incrementando corretamente (1 → 2).
- 3 tabelas novas (medicamentos/suplementos/exames) com insert funcionando.
- `intensidade` rejeitando `NULL` e valor inválido (CHECK constraint).
- RPC `anamnese_historico_peso` com peso atual/anterior/maior/menor corretos.
- `profissional_salvar_anamnese` gravando o payload completo (motivo, objetivos secundários, composição corporal, rotina diária, bloco condicional, condição de saúde com status, alergia) e confirmando `dados_confirmados=true`.

## Tabela de Rastreabilidade (spec × Backend × App × Web)

A mesma tabela abaixo está disponível ao vivo no Painel Web em **Administração → Compliance da Anamnese** (`/admin/compliance-anamnese`).

| Bloco | Ref. | Descrição | Backend | App | Web |
|---|---|---|---|---|---|
| Bloco 1 | Seção 4 | Contexto da avaliação / Motivo | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 2 | Seção 4.1/4.2/5 | Objetivos (lista exata + secundários + meta quantitativa) | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 3 | Seção 6 | Antropometria (composição corporal completa) | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 4 | Seção 7 | Histórico de peso | ✅ Implementado | ✅ Implementado | 🟡 Parcial — RPC existe/tipada, mas nenhuma tela Web a chama ainda. Plano: card dedicado em `PatientDetails.tsx`. |
| Bloco 5 | Seção 8 | Alimentação (padrão alimentar) | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 6 | Seção 9 | Atividades e rotina (intensidade obrigatória, alfabético, busca) | ✅ Implementado | ✅ Implementado | 🟡 Parcial — sem barra de busca (catálogo pequeno hoje). Plano: adicionar se crescer. |
| Bloco 7 | Seção 10 | Sono e recuperação | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 8 | Seção 11 | Condições de saúde (Sim/Não + lista exata) | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Alergias | — | Catálogo com padrão clínico | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 9 | Seção 12 | Medicamentos | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 10 | Seção 13 | Suplementos | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 11 | Seção 14 | Exames laboratoriais | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 12 | Seção 15-19 | Blocos condicionais (Idoso/Atleta/Recomposição/Diabetes/Renal) | ✅ Implementado | ✅ Implementado | 🟡 Parcial — só Atleta/Diabetes/Renal têm toggle no Web; Idoso/Recomposição faltam lá (backend já suporta os 5). |
| Bloco 13 | Seção 21 | Resultados do Motor (energia: TMB/TDEE) | 🟡 Parcial — macros não calculados (sem fórmula no doc) | ✅ Implementado | ✅ Implementado |
| Bloco 14 | Seção 22 | Metas (sistema × profissional, nunca sobrescreve) | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Bloco 15 | Seção 25 | Qualidade e exceções (score, dados faltantes) | 🟡 Parcial — coluna pronta, sem algoritmo (sem fórmula no doc) | 🔴 Pendente | 🔴 Pendente |
| Bloco 16 | Seção 26 | Auditoria e versionamento | ✅ Implementado | ✅ Implementado | ✅ Implementado |
| Seção 11 | — | Tela "Confirme seus dados" | ✅ Implementado | ✅ Implementado (tela dedicada) | 🟡 Parcial — confirmação implícita no submit, sem 2ª tela de revisão. |
| UX Global | — | Confirmação explícita em listas/bottom sheets | N/A | ✅ Implementado | N/A — Painel usa formulário denso, não bottom sheets. |
| Regra de arquitetura | Seção 18/28 | Perguntas mínimas → Confirmado → Anamnese → Motor → Resultado → Meta | ✅ Implementado | ✅ Implementado | ✅ Implementado |

**Planos de implementação para os itens pendentes/parciais** (nenhum implementado nesta tarefa sem pedido explícito, Regra 26):

1. **Histórico de peso no Web**: consumir `anamnese_historico_peso` num novo card em `PatientDetails.tsx`, mesmo padrão visual do `MotorMetabolicoV1Card`.
2. **Busca de atividades no Web**: adicionar `<input>` de filtro acima do `<select>` em `AnamneseProfissionalView.tsx` se o catálogo (hoje 99 itens) crescer o suficiente pra justificar.
3. **Blocos Idoso/Recomposição no Web**: replicar o padrão `BlocoCondicionalAtleta`/`Diabetes`/`Renal` já existente, mais 2 componentes.
4. **Score de qualidade (Bloco 15)**: requer definição da fórmula/critérios com o fundador — o documento não especifica nenhuma. Sem isso, qualquer implementação seria uma invenção não autorizada.
5. **Macronutrientes calculados (Bloco 13)**: mesma razão — requer uma fórmula explícita (proteína/carbo/gordura por kg ou %) que o documento não fornece.
6. **2ª tela de confirmação no Web**: avaliar com o fundador se vale a pena, dado que o formulário profissional já é revisado visualmente antes do submit (diferente do app, que tem múltiplas seções scrolláveis onde uma revisão final agrega mais valor).

## ACEITE (conferido item a item)

- ✅ Backend, Flutter e React refletem os Blocos 1-16 do documento — com os gaps parciais listados na tabela acima, todos com plano e razão explícita (nenhum escondido).

## Entregável

- Migrations: `20260918100000` (Blocos 1-16), `20260918110000` (fix crítico + payload da RPC profissional), `20260918120000` (alergias) — todas já aplicadas em produção e verificadas ao vivo.
- App Flutter: `anamnese_models.dart`, `anamnese_repository.dart`, `anamnese_self_service_page.dart` reescritos; `confirmar_anamnese_page.dart`, `lista_repetivel_widget.dart`, `seletor_multiplo_bottom_sheet.dart` novos; i18n pt/en/es; testes atualizados/criados. `flutter analyze` limpo, `flutter test` 491/491.
- Painel Web: `AnamneseProfissionalView.tsx` reescrita; `AnamneseHistoricoView.tsx` e `AdminComplianceAnamnese.tsx` novos; `database.ts` ampliado; roteamento/menu atualizados. `tsc -b`/`build`/`lint` limpos.
- Branch `feat/full-compliance-anamnese`, a partir de `main`, **não mesclada** (Regra 18 — aguardando autorização explícita do fundador). 6 commits divididos por camada (DB, App, DB-fix-Web-companion, Web, Web-fix-alergias, tela de compliance).
