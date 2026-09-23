# RELATÓRIO 20260923_0001 — Anamnese Inteligente: UI de Revisão de Smartwatch, IA de Refeições e Widget de Validade (Flutter + Web)

**Branch:** `feat/anamnese-smart-ui` (a partir de `main`, que já contém o backend de `20260922_0001`).
**Data:** 2026-09-23.

## Contexto

O backend (RPCs `iniciar_rascunho_anamnese`/`processar_medias_smartwatch`, trigger de composição corporal, colunas de IA/validade — `20260922_0001`) já estava pronto. Esta tarefa constrói a interface, com paridade estrita entre Flutter (self-service) e React (Anamnese Profissional).

## Item 1 — Reorganização e Listas

- **Sexo Biológico movido para antes do Motivo da Avaliação**, em ambas as plataformas.
  - Flutter: o campo (`_buildSecaoSexoBiologico`) já existia dentro de "Dados Físicos" — extraído pra seu próprio método e movido pra antes de `_buildSecaoMotivoAvaliacao`. Continua lendo o valor de `perfis_usuarios` (nenhuma mudança de fonte de dado).
  - Web: `AnamneseProfissionalView.tsx` **não tinha** esse campo (só coletava, nunca exibia) — adicionado como exibição SÓ LEITURA, buscado de `perfis_pacientes_vinculados` (mesma view que `PatientDetails.tsx` já usa), antes do `<select>` de Motivo. Edição continua exclusivamente em `PatientDetails.tsx` (`profissional_atualizar_sexo_biologico`), não duplicada aqui.
- **Restrições Culturais/Religiosas** — nas duas plataformas, catálogo estático idêntico (Vegano, Vegetariano, Kosher, Halal, Jejum intermitente, Outros — os exemplos literais da tarefa + a opção explícita pedida), usando a MESMA mecânica visual/de preenchimento de Alergias:
  - Flutter: `ResumoSelecaoMultipla`/`abrirSeletorMultiplo` (os mesmos widgets de Alergias), com campo de texto livre quando "Outros" é marcado.
  - Web: chips clicáveis (mesmo padrão visual de Alergias), com campo de texto livre quando "Outros" é marcado.
  - Como `anamneses.restricoes_culturais_religiosas` é `text[]` livre (sem tabela-catálogo, diferente de Alergias), os códigos internos (`vegano`, `kosher`...) viram o texto traduzido correspondente só no momento de montar o payload — nunca gravados como código.

## Item 2 — Motor de Agregação de Smartwatch (Revisão)

**Decisão de UX registrada**: a tarefa pede um botão "nas seções de Atividade, Sono e Carga de Treino" — como `processar_medias_smartwatch` devolve as 3 numa chamada só, implementei **um único botão** ("Buscar dados do relógio") que abre uma tela/modal de revisão com uma seção dedicada para cada uma das 3 — evita 3 gatilhos desconectados batendo na mesma RPC, e é a mesma decisão nas duas plataformas (paridade).

- A janela de tempo usada é a devolvida por `iniciar_rascunho_anamnese` (carregada uma vez, no início da tela) — reaproveitando o Item 1 do backend, exatamente como desenhado lá.
- **UX de Revisão**: nada é aplicado automaticamente (RESTRIÇÃO explícita). Cada item (cada modalidade/dia de atividade; sono; carga de treino) tem um checkbox "Aceitar" (desmarcado = excluído do resultado), um campo editável (minutos/intensidade para atividades; horas para sono/carga), e só o que estiver marcado quando o usuário clica "Aplicar/Confirmar" volta pra tela de origem — ainda como rascunho em memória, sujeito ao fluxo normal de salvar.
- **Semáforo de Confiabilidade — decisão técnica importante**: o backend só devolve `percentual_confiabilidade` para as **métricas diárias** (`metricas_diarias.*` — neste fluxo, só Sono é exibido). Para Atividades por dia da semana e Carga de Treino, `processar_medias_smartwatch` devolve `ocorrencias_totais`/`semanas_do_periodo` (suporte estatístico), **não uma porcentagem de confiabilidade**. Em vez de inventar uma fórmula não pedida pelo backend, essas 2 seções mostram o suporte estatístico real (ex.: "2 ocorrências em 2 semanas do período") e um aviso explícito de que a % não existe pra elas. Onde a % existe de verdade (Sono), o semáforo usa exatamente os limiares da tarefa: Verde > 70%, Amarelo 30-70%, Vermelho < 30%.
- Flutter: nova tela `RevisaoSmartwatchPage` + modelos (`MediasSmartwatchResultado`, `AtividadeSmartwatch`, `CargaAtletaSmartwatch`, `MetricaConfiabilidade`, `JanelaAnamnese`). `TipoAtividadeItem` ganha `nomeCodigo` (necessário pra casar a modalidade — texto — que a RPC devolve com o `id` — smallint — que `AtividadeSelecionada` exige).
- Web: componente `RevisaoSmartwatchModal` (overlay), mesmas 3 seções, mesmos limiares de cor.

## Item 3 — Inteligência Alimentar com IA

- Reaproveita **exatamente** a IA de refeições já existente (RESTRIÇÃO explícita: "não invente integrações novas do zero") — o mesmo Edge Function/contrato do Método 1 (texto) do Registro de Refeição (RELATÓRIO 20260824_0003): `X-Tipo-Aparelho: pratoRefeicaoTexto` em `extract-metric-photo`.
- Flutter: reaproveita literalmente `RegistroRefeicaoIaController`/`RegistroRefeicaoIaService` (o mesmo código que já roda no Registro de Refeição) dentro do novo widget `RefeicoesHabituaisWidget`.
- Web: **nova chamada `fetch` direta** ao mesmo Edge Function (o Painel Web nunca tinha essa integração — não havia um "controller" existente pra reaproveitar do lado do cliente, só o backend). Verificado ao vivo que uma sessão de PROFISSIONAL consegue chamar esse endpoint (nunca testado nesse contexto antes) e recebe `itens`/`itens_nao_reconhecidos` normalmente.
- Cada refeição (o número de linhas segue "Refeições/dia", até 12) tem: Horário, "Fora de casa?" (toggle), texto livre, botão "Interpretar com IA" — soma `calorias`/`proteinas_g`/`carboidratos_g`/`gorduras_g` de todos os `itens` retornados (o mesmo `PratoRefeicaoExtracaoModel` que a foto/áudio já produzem) e mostra o resultado. Tudo isso vira um elemento de `refeicoes_diarias_habituais` no momento de montar o payload — `kcal`/macros só presentes quando a IA conseguiu interpretar.
- **"Alimentos evitados" e "Alimentos preferidos" já existiam** nas duas telas antes desta tarefa (`alimentosEvitadosController`/`preferenciasController` no Flutter; `alimentosEvitados`/`preferenciasAlimentares` no Web) — confirmado, nenhuma mudança necessária.

## Item 4 — Live Search em Atividades

**Já implementado nas duas plataformas antes desta tarefa** — confirmado por leitura de código, nenhuma mudança necessária:
- Flutter: `_ModalAdicionarAtividade._opcoesFiltradas` filtra a lista a cada `onChanged` do campo de busca.
- Web: `atividadesFiltradas` filtra o `<select>` a cada tecla (aparece quando o catálogo tem mais de 8 itens).

## Item 5 — Widget de Notificação e Bloqueio de Validade (Flutter)

- Lógica **pura** e testável, isolada em `lib/features/nutricao/domain/anamnese_validade_status.dart` (`AnamneseValidadeStatus.calcular`), compartilhada entre o widget do Dashboard e o bloqueio de `MetaBemEstarPage` — um único lugar decide os limiares:
  - `> 7 dias pra vencer` → `ok` (nenhum alerta).
  - `0-7 dias pra vencer` → `lembrete` (amarelo, dispensável).
  - `1-39 dias de atraso` → `atrasada` (laranja, dispensável) — **decisão registrada**: a tarefa cita "10, 20 e 30 dias" como exemplos de marcos; implementado para mostrar o alerta (com o número EXATO de dias) continuamente durante todo o atraso, não só nesses 3 dias específicos — um usuário que abre o app no dia 15 de atraso também precisa ver o aviso.
  - `>= 40 dias de atraso` → `bloqueada` (vermelho, **NÃO dispensável**).
- `AnamneseValidadeBanner`: novo widget montado como banner FIXO no topo da aba Dashboard (`main_navigation_page.dart`), **fora** do catálogo de widgets arrastáveis/customizáveis (`DashboardWidgetFactory`/`WidgetLayoutModel`) — decisão de escopo: integrá-lo ali exigiria uma migration nova pro layout persistido, além do que a tarefa pediu ("crie o Widget no Dashboard", não "integre ao sistema de customização"). Botão "Refazer anamnese" nele leva direto para `AnamneseSelfServicePage`.
- **Bloqueio Severo**: `MetaBemEstarPage` ganha um novo `_CargaStatus.bloqueadaValidadeAnamnese`, checado **antes** de Carência/Prioridade Profissional (uma anamnese severamente vencida é mais fundamental que qualquer meta já definida) — reaproveita o `_buildBloqueio` já existente na tela, mesma UX das outras 2 travas.
- Dispensa de alertas não-bloqueantes: **só durante a sessão atual** (estado em memória, sem `shared_preferences` — pacote não usado neste projeto ainda; adicioná-lo só pra persistir essa dispensa entre reaberturas do app foi considerado fora do escopo desta tarefa, documentado aqui em vez de simplesmente ignorado).

## Verificação

- `flutter analyze`: 30 avisos pré-existentes, zero novo.
- `flutter test`: **508/508** (496 anteriores + 12 novos — 10 testes puros de `AnamneseValidadeStatus` cobrindo cada limiar/fronteira, incluindo os "marcos" 10/20/30 citados na tarefa, e 2 testwidgets do bloqueio de 40 dias em `MetaBemEstarPage`), zero regressão.
- `npx tsc -b` / `npm run build` / `npm run lint` (Web): limpos (lint com os 2 warnings pré-existentes de sempre, em arquivo não tocado).
- **Verificado ao vivo**: a Edge Function de IA de refeições responde `200` para uma sessão de PROFISSIONAL (uso nunca testado nesse contexto antes desta tarefa); `iniciar_rascunho_anamnese`/`processar_medias_smartwatch` respondem corretamente chamadas pelo cliente anon com token de profissional (mesmo contrato já testado exaustivamente no backend, RELATÓRIO 20260922_0001 — aqui só confirmando que a integração client-side usa os parâmetros certos).

## Fora do escopo desta tarefa (documentado, não esquecido)

- `AdminComplianceAnamnese.tsx` não foi atualizada — não estava no `ARQUIVOS` desta tarefa.
- Dispensa de alertas de validade não persiste entre reaberturas do app (só na sessão atual).
- `AnamneseValidadeBanner` não foi integrado ao catálogo de widgets customizáveis/arrastáveis do Dashboard — fica fixo no topo.
- A "Tela Senior" (`_SeniorShell`, perfil de UI acessível) não recebeu o banner de validade — só o layout competitivo padrão (`_AthleteShell`) foi tocado; adicionar ao layout senior fica como gap conhecido pra uma tarefa futura.
- Web: modal de revisão do smartwatch não tem um teste automatizado dedicado (o Painel Web neste projeto não tem suíte de testes de componente configurada — mesma limitação já registrada em relatórios anteriores).
