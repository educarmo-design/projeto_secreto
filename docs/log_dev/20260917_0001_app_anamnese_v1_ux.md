# RELATÓRIO 20260917_0001 — App Anamnese V1 UX (Captura Inteligente, Separação Cálculo×Meta, Histórico)

**Data:** 2026-09-17
**Branch:** `feat/app-anamnese-v1-ux` (a partir de `main`, que já inclui SSOT + Motor V1 mesclados)
**Persona:** Especialista em Flutter e UI/UX (Mestre v8.0)

## Item 0 — Migrations e Tipos (auditoria, sem código novo)

- **Migrations**: `supabase migration list --linked` confirma `20260916120000` (SSOT peso/altura + Motor V1, tarefa anterior) já sincronizada `local=remote` — nada pendente de aplicar. Este projeto nunca usou um Postgres local (Docker) em nenhuma tarefa desta sessão: `supabase db push`/`migration list` sempre operam direto contra o banco remoto linkado (`--linked`), então "aplicar no banco local" não se aplica à forma como este projeto é desenvolvido — documentado aqui, não silenciosamente ignorado.
- **`supabase gen types dart`**: **não existe** — `supabase gen types --help` (CLI instalada, v2.109.1) lista `--lang` com as opções `typescript, go, swift, python`; Dart não é um alvo suportado pela ferramenta oficial. Este projeto, em toda sua história, nunca usou tipos gerados — usa modelos Dart tipados à mão (`AnamneseAtiva`, `DadosFisicosAtuais`, `MetaResumo` etc., todos com `.fromJson()` manual), e esses modelos **já foram atualizados** na tarefa SSOT anterior (RELATÓRIO 20260916_0001) para refletir que `peso`/`altura` saíram de `perfis_usuarios`. Não há comando pra rodar aqui — item auditado e explicado, não fabricado.

## Item 1 — Captura Inteligente e Confirmação Obrigatória

`AnamneseRepository` ganhou `buscarSugestaoBalanca()` — lê a leitura mais recente de `metricas_saude_diarias` (peso e/ou % de gordura) via `.or('peso_kg.not.is.null,percentual_gordura.not.is.null')`, **verificado ao vivo** contra o banco real (retornou peso=79.3kg/gordura=15% de uma leitura real). Na `AnamneseSelfServicePage`, se houver dado, aparece um banner "Dado lido da balança: X kg (registrado em dd/mm/aaaa) — Confirmar" com um botão que copia o valor pro campo de peso — **nunca preenche sozinho**: o campo continua obrigatório/validado normalmente (Restrição do documento: leitura de balança é só sugestão até confirmação, Seção 1). Altura já era pré-preenchida como sugestão editável da última anamnese (tarefa anterior) — mantido.

## Item 2 — Tela Final: Separação de Cálculo vs Meta (ME-005/ME-006)

`ResultadoMotorMetabolicoPage` reescrita: troca `gerar_sugestao_meta` por **`calcular_motor_metabolico_v1`** (o Motor Centralizado da tarefa anterior, até agora sem nenhuma tela consumindo-o). Nova **Seção A — Resultados Calculados** (só leitura: TMB + TDEE médio, com aviso explícito "valores informativos... não são uma meta") e nova **Seção B — Minha Meta Diária** (4 campos `TextFormField` **em branco**, sem placeholder de valor nenhum — Calorias/Proteína/Carboidrato/Gordura). O usuário preenche e "Salvar Minha Meta" grava via `validar_e_salvar_meta` (mesmo Motor de Exceções N08 de `MetaBemEstarPage`, `tipo_dia = 'PADRAO'` → meta média replicada pros 7 dias, exatamente como o documento pede pra usuário sem profissional, Seção 23). Testado explicitamente que o valor GRAVADO é o **digitado** pelo usuário (1900), não o TDEE médio calculado (2200) — a Restrição "o app não pode calcular macronutrientes automaticamente e salvar como meta" é estruturalmente impossível de violar aqui: os 4 campos nunca recebem um valor programaticamente, só o que o dedo do usuário digitar.

O modal vermelho de bloqueio (trava clínica/carência/prioridade profissional) foi **extraído** de `MetaBemEstarPage` para `nutricao/presentation/widgets/meta_bloqueio_modal.dart` — reaproveitado pelas duas telas que agora gravam meta, sem duplicar o `switch` motivo→texto.

**Decisão registrada**: removida a "Sugestão de Meta" (`gerar_sugestao_meta`) desta tela — a RPC continua no banco (não foi tocada, ainda usada por quem quiser chamá-la diretamente), só parou de ter uma tela Flutter consumindo. `MetaBemEstarRepository.buscarSugestaoCalorias()`/o botão "Usar sugestão" de `MetaBemEstarPage` continuam intactos (fluxo diferente, fora do escopo desta tarefa).

## Item 3 — Histórico de Anamnese e Próxima Revisão

Nova tela `HistoricoAnamnesesPage` (`profile.anamnese_historico_item`, entrada logo abaixo de "Anamnese Nutricional" em Configurações). `AnamneseRepository.buscarHistoricoAnamneses()` lista TODAS as anamneses do usuário (qualquer `status_vigencia`, mais recente primeiro — nenhuma sobrescrita, confirmado pela própria natureza INSERT-only já garantida pelo trigger de versionamento). Topo da tela destaca a **Data da Próxima Revisão** (última anamnese + 30 dias, mesma regra de carência da tela de preenchimento) em card dourado. Cada item mostra data, peso/altura (ou "Sem peso/altura registrados", pra anamneses anteriores à SSOT), objetivo e rótulo Atual/Anterior.

**Gap conhecido, documentado no código e aqui (não escondido)**: "resultados" por anamnese passada não inclui TMB/TDEE — `calcular_motor_metabolico_v1` é uma função **pura** (nunca persiste, por desenho da tarefa anterior/ME-005/ME-006) e sempre resolve pra "última anamnese com dado", nunca recalcula pra uma anamnese específica do passado. Persistir um resultado histórico por anamnese exigiria uma coluna/tabela nova (ex.: `anamneses.tmb_calculado`/`tdee_medio_calculado`) — fora do escopo desta tarefa, cujos ARQUIVOS listam só telas Flutter, nenhuma migration. Registrado como possível trabalho futuro, não implementado por conta própria sem pedido explícito (Regra 26).

## Item 4 — Dashboard (auditoria, sem código novo)

`ConsumoMetaCard` (`dynamic_widget_factory.dart`, o widget de macros/calorias da tela inicial) **já** cruza exclusivamente `MetaBemEstarRepository.buscarMetaEfetivaAtual()` (a meta que o usuário/profissional definiu) com `ColetaDiariaRepository.buscarConsumoHoje()` (o que foi registrado no dia) — lido o arquivo inteiro, confirmado que não há nenhuma chamada a `calcular_motor_metabolico`/`calcular_motor_metabolico_v1`/`gerar_sugestao_meta` em nenhum ponto do widget ou de quem o alimenta (`main_navigation_page.dart`). Este item já estava correto desde o RELATÓRIO 20260820 (N12), antes até do Motor V1 existir — auditado, nenhuma mudança necessária.

## Verificação

- **Ao vivo contra o banco real** (atleta1000@teste.com, sessão autenticada de verdade via magic link): `buscarSugestaoBalanca` (filtro `.or()`) confirmado com dado real de balança; `buscarHistoricoAnamneses` inserida/lida/limpa uma anamnese de teste; `calcular_motor_metabolico_v1` reconfirmado com peso/altura reais (TMB=1655.5, TDEE médio PAL=1986.6, matemática batendo manualmente). Todos os dados de teste removidos ao final, confirmado 0 resíduo.
- `flutter analyze` — limpo nos arquivos tocados; os 30 avisos do projeto inteiro são pré-existentes.
- `flutter test` — **486/486**, zero regressão (+18 testes novos: 5 em `anamnese_repository_test.dart`, 2 em `meta_bem_estar_repository_test.dart`, 2 em `anamnese_self_service_page_test.dart`, `resultado_motor_metabolico_page_test.dart` reescrita — 8 testes — e `historico_anamneses_page_test.dart` novo, 4 testes).

## ACEITE (conferido item a item)

- ✅ Tipagem do DB "atualizada" no Dart — já estava (tarefa SSOT anterior); `supabase gen types dart` não existe nesta ferramenta, auditado e explicado.
- ✅ UX fluida na anamnese — sugestão da balança some/aparece sem travar o fluxo, altura/peso continuam obrigatórios.
- ✅ Usuário confirma altura/peso, vê o cálculo (Seção A), define sua própria meta (Seção B) — nunca um valor calculado é salvo como meta automaticamente.
- ✅ Dashboard reflete exclusivamente a meta digitada — já era assim, confirmado.

## Entregável

- Código Flutter: 7 arquivos modificados + 3 novos (`historico_anamneses_page.dart`, `meta_bloqueio_modal.dart`, + os modelos/i18n).
- Branch `feat/app-anamnese-v1-ux`, a partir de `main`, **não mesclada** (Regra 18 — aguardando autorização explícita do fundador).
