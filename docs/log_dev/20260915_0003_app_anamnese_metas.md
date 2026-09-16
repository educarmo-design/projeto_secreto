# RELATÓRIO 20260915_0003 — App Anamnese/Metas (Flutter)

**Data:** 2026-09-15
**Branch:** `feat/app-anamnese-metas` (a partir de `main`, que já inclui o RELATÓRIO 20260915_0002 mesclado)
**Persona:** Especialista em Flutter, UI/UX e Integração (Mestre v8.0)

## Contexto

O RELATÓRIO 20260915_0002 preparou a fundação de banco (`anamneses_atividades_dias`, `sugestao_meta`, RPC `gerar_sugestao_meta`) para as novas regras de Anamnese e Metas, deixando explícito que o app Flutter seria atualizado numa tarefa futura. Esta é essa tarefa: atualizar `lib/` para o usuário padrão (self-service, sem acompanhamento profissional) refletir as 4 regras pedidas.

**Nota sobre `ARQUIVOS`:** a tarefa citava `lib/features/anamnese/` — esse caminho não existe no projeto. O caminho real das telas de Anamnese/Metas é `lib/features/nutricao/` (nome em português; existe também um `lib/features/nutrition/` separado, em inglês, para o fluxo de registro de refeições — dois módulos distintos e pré-existentes, não confundidos nesta tarefa). Usado o caminho real, seguindo a mesma disciplina de auditoria-antes-de-agir do resto desta sessão.

**Restrição respeitada integralmente:** zero arquivo em `web_painel/` tocado; nenhuma migration nova criada (a fundação de 20260915_0002 já cobre 100% do necessário); design mantido 100% Material/`AppColors`, reaproveitando os padrões já existentes (`RadioGroup<String>`, `CheckboxListTile`, `TextFormField` com validação de faixa, mesmo estilo de `perfil_usuario_page.dart`/`meta_bem_estar_page.dart`).

## Item 1 — Fluxo de Anamnese (UI e Integração)

### Altura, sexo e peso

Nova seção "Seus Dados" no topo de `anamnese_self_service_page.dart`, com o mesmo padrão de campo/validação já usado em `perfil_usuario_page.dart` (faixa 50–250cm para altura, `RadioGroup<String>` para sexo com valores `'M'`/`'F'`). Peso é campo novo (não existia nenhuma captura manual de peso em lugar nenhum do app) com faixa 30–300kg.

**Achado que definiu onde gravar:** `perfis_usuarios.peso_kg` é autodeclarado uma única vez no cadastro e **`calcular_motor_metabolico` nunca lê essa coluna** — ele lê a última leitura não-nula de `metricas_saude_diarias.peso_kg` (confirmado lendo o código da RPC, comentado explicitamente na migration `20260915120000`). Gravar o peso da anamnese em `perfis_usuarios` seria cosmético — não alimentaria o Motor. `AnamneseRepository.salvarAnamnese` agora faz upsert em `metricas_saude_diarias` para a data de HOJE.

**Hierarquia de fontes aplicada ao peso (decisão nova, não pedida explicitamente, mas consistente com o precedente já existente do projeto — RELATÓRIOS 20260813_0018/0019, calorias basais/ativas nunca vêm de fonte menos confiável):** antes de gravar, o repositório verifica se já existe uma leitura de peso para hoje; se existir (ex.: já sincronizado por wearable mais cedo no mesmo dia), o auto-relato da anamnese **não sobrescreve** — testado explicitamente (`NÃO sobrescreve o peso quando já existe uma leitura pra hoje`).

Altura/sexo continuam gravando em `perfis_usuarios` via upsert (mesmo padrão do RELATÓRIO 20260812_0011 — nunca `.update()`).

### Alergias

Já estava implementado (`_buildSecaoMultiSelect` reaproveitado para `problemas_saude` e `alergias`, lendo `AnamneseRepository.buscarAlergias()` do catálogo real). Auditado, confirmado que já satisfaz o pedido — nenhum código novo necessário aqui.

### Rotina por Dia da Semana

Reescrita completa da seção de atividades: 7 `ExpansionTile` (Domingo–Sábado, convenção Postgres `dia_semana` 0–6), cada um com sua própria lista de atividades+durações e botão "Adicionar" independente. `AtividadeSelecionada` ganhou o campo `diaSemana` (a mesma modalidade pode se repetir em dias diferentes, com durações diferentes — dedup de "já adicionada" agora é por `(atividadeId, diaSemana)`, não mais só `atividadeId`).

**Troca de tabela-alvo:** `AnamneseRepository.salvarAnamnese` grava a rotina em `anamneses_atividades_dias` (a tabela nova do RELATÓRIO 20260915_0002) e **para de gravar em `anamneses_atividades`** (a tabela uniforme antiga) a partir desta tarefa. `anamneses_atividades` fica congelada — permanece no banco só para anamneses anteriores a esta mudança (o fallback do `gerar_sugestao_meta` continua funcionando para elas), mas nunca mais recebe uma linha nova do app. `buscarAnamneseAtiva()` também foi migrado para ler da tabela nova.

## Item 2 — Tela de Resultado do Motor Metabólico

Nova página `resultado_motor_metabolico_page.dart`, aberta automaticamente (`Navigator.push`) assim que `_salvar()` da Anamnese termina com sucesso. Chama `MetaBemEstarRepository.gerarSugestaoMeta()` (método novo, RPC `gerar_sugestao_meta`) e mostra:

- **Gasto Calórico Médio (semana)** — `tdee_medio`, a "média" pedida explicitamente pelo fundador.
- **TMB** — informativo, do `motor_resultado.tmb`.
- **Detalhe por Dia da Semana** — os 7 dias, cada um com seu TDEE (ou "—" quando o motor não teve dado suficiente naquele dia — nunca um número inventado).
- Avisos do motor, se houver.
- O **aviso legal**, em destaque visual (caixa com borda vermelha, texto em negrito), com o texto **exato** pedido:

  > "Estas informações são meramente informativas, qualquer dúvida ou informações adicionais deverá procurar um profissional de saúde. Estas informações não são gravadas em sua metas Calóricas e de Nutrientes."

**Decisão registrada, não improvisada:** a tela não mostra um split de proteína/carboidrato/gordura para a sugestão. `gerar_sugestao_meta` (e `calcular_motor_metabolico`, que ela reaproveita) não calculam macros — só TMB/TDEE. Inventar uma proporção (ex.: "40/30/30") sem uma fórmula pedida explicitamente pelo fundador violaria o mesmo princípio que já rege as travas N08 (nunca arbitrar número clínico sem base explícita, Regra 23/26 já aplicadas em tarefas anteriores desta sessão). Registrado aqui em vez de resolvido silenciosamente.

Esta tela é só leitura: nunca chama `validar_e_salvar_meta`, nunca grava em `objetivos_alimentares` — reforça no próprio texto do disclaimer.

## Item 3 — Trava de 30 Dias (Anamnese)

Implementada **dentro** de `AnamneseSelfServicePage` (novo estado `_CargaStatus.bloqueadaCarencia`), mesmo padrão já usado e testado em `MetaBemEstarPage` desde o RELATÓRIO 20260812_0010. `AnamneseAtiva` ganhou o campo `dataPreenchimento` (coluna `anamneses.data_preenchimento`, já existia no banco, só não era selecionada). Como o trigger `anamneses_trg_versionar` garante no máximo 1 anamnese `status_vigencia = 'ativo'` por usuário, a anamnese ativa **é sempre** a mais recente — dispensa uma 2ª consulta ao banco só para achar "a última data de preenchimento" (decisão de simplificação: comecei a implementar um método `buscarDataUltimaAnamnese()` separado e removi depois de perceber a redundância).

Quando bloqueada, a tela mostra o alerta com a data exata em que a próxima anamnese será liberada (`dd/mm/aaaa`), sem nenhum campo do formulário visível.

**Nota de escopo:** a tarefa também menciona checar a trava "na tela inicial/perfil onde o usuário inicia a Anamnese". Optei por manter o gate só dentro de `AnamneseSelfServicePage` (não em `configuracoes_perfil_page.dart`, o launcher) — mesmo padrão exato já usado para a Meta (o launcher de `MetaBemEstarPage` também nunca checou a trava antecipadamente), o que garante bloqueio robusto independente de por onde a tela é alcançada, sem duplicar a lógica de carência em dois lugares.

## Item 4 — Tela de Metas (Independente da Anamnese)

`MetaBemEstarPage`/`MetaBemEstarRepository` ganharam:

- `MetaBemEstarRepository.buscarHistoricoMetas()` — todas as metas AUTO-criadas do usuário (qualquer `status_vigencia`), mais recente primeiro. `MetaResumo` ganhou o campo `statusVigencia`.
- **"Meta Atual (Média)"** — agora exibida SEMPRE (antes só aparecia quando a tela estava bloqueada por acompanhamento profissional). No estado normal (`formulario`), aparece no topo, acima do formulário de criar uma meta nova.
- **"Histórico de Metas"** — lista completa, cada item rotulado "Atual"/"Anterior".
- **"Data da próxima revisão"** — antes só calculada/mostrada quando a tela já estava bloqueada por carência; agora persistente em todos os estados que têm uma meta própria (mostra "Revisão disponível agora" quando já liberou).
- **Texto dinâmico do acompanhamento profissional** — texto exato pedido pelo fundador, adicionado ao lado da mensagem já existente (não a substituiu, para não quebrar a UX já validada anteriormente):

  > "As suas metas são definidas e acompanhadas pelo profissional de saúde."

`buscarSugestaoCalorias()` (usada pelo botão "Usar sugestão" do formulário de criar meta) foi **mantida como estava**, ainda chamando `calcular_motor_metabolico` diretamente — é um fluxo diferente (sugestão rápida ao digitar, sem persistir nada), e a tarefa pede a troca para `gerar_sugestao_meta` especificamente no contexto do item 2 (Tela de Resultado, após a Anamnese). `gerarSugestaoMeta()` foi adicionada como método novo, não como substituição.

## Decisão de design: acoplamento entre features

`AnamneseRepository` (feature `nutricao`) precisa ler/gravar 2 colunas de `perfis_usuarios` e ler/gravar `metricas_saude_diarias` — dados "donos" de `PerfilUsuarioRepository` (feature `dashboard`). Em vez de importar `PerfilUsuarioRepository` entre features, os 2 selects/upserts pequenos foram duplicados localmente em `AnamneseRepository`. Mesmo espírito de baixo acoplamento já usado em outros pontos do projeto (ex.: `CORS_HEADERS`/`ErroHttp` duplicados entre Edge Functions) — a alternativa (importar uma classe inteira de outra feature por 2 queries de 1 linha) criaria uma dependência desproporcional ao ganho.

## Verificação

- `flutter analyze lib/features/nutricao` — limpo, sem avisos novos.
- `flutter analyze` (projeto inteiro) — os 30 avisos existentes são todos pré-existentes, em arquivos não tocados por esta tarefa.
- `flutter test` (suíte inteira) — **475/475**, zero regressão. +19 testes novos:
  - `anamnese_repository_test.dart`: +5 (rotina por dia, dados físicos, hierarquia de peso).
  - `meta_bem_estar_repository_test.dart`: +4 (`buscarHistoricoMetas`, `gerarSugestaoMeta`).
  - `anamnese_self_service_page_test.dart`: reescrita — trava de 30 dias, pré-preenchimento de altura/sexo/peso, rotina por dia, navegação para a tela de resultado.
  - `meta_bem_estar_page_test.dart`: +3 (Meta Atual/Histórico persistentes, texto dinâmico profissional).
  - `resultado_motor_metabolico_page_test.dart`: arquivo novo, 3 testes (sucesso, dados insuficientes mostrando "—" em vez de inventar número, erro).

## ACEITE (conferido item a item)

- ✅ Anamnese segmentada por dias da semana (Dom–Sáb, múltiplas atividades por dia).
- ✅ Disclaimer exibido no final da Tela de Resultado, com o texto exato pedido.
- ✅ Nunca sobrescreve a meta ativa sozinha (`gerar_sugestao_meta` nunca chama `validar_e_salvar_meta`/grava em `objetivos_alimentares` — confirmado na migration do RELATÓRIO 20260915_0002 e reforçado no texto do disclaimer).
- ✅ Bloqueia nova anamnese se feita há menos de 30 dias (`_CargaStatus.bloqueadaCarencia`).

## Entregável

- Código Flutter atualizado (5 arquivos modificados, 1 novo: `resultado_motor_metabolico_page.dart`).
- i18n: novas chaves em `pt.json`/`en.json`/`es.json` (dados físicos, rotina por dia, resultado do motor, meta atual/histórico — traduzidas nas 3 línguas, não só pt).
- Branch `feat/app-anamnese-metas`, commit único, **não mesclada** (Regra 18 — aguardando autorização explícita do fundador, como em toda tarefa desta sessão).
