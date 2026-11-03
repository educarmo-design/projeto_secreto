# 20261103_0001 — 5 ajustes finos: máscara de hora, remoção de atalho, resultado completo nos detalhes, "Meta já definida"

## Contexto

Teste de campo do fundador na Anamnese, Detalhes e Meta de Bem-Estar. 5 ajustes finos de UX/formatação + remoção de uma restrição legada. Esta tarefa parte de branch que inclui as mudanças ainda não mescladas do RELATÓRIO `20261102_0003` (PR #19) — vários dos arquivos tocados aqui (`ResultadoMotorMetabolicoPage`, `AnamneseDetalhesPage`) são os mesmos daquela PR, então esta foi aberta em cima dela (`fix/trava-meta-link-resultado`), não direto em `main`, para evitar conflito.

RESTRIÇÃO explícita da tarefa: nenhuma migration/RPC nova — tudo 100% Flutter.

## 1. Máscara HH:mm nos 3 campos de horário

Novo utilitário compartilhado (`lib/features/nutricao/presentation/widgets/hora_input_formatter.dart`):
- `HoraInputFormatter` (`TextInputFormatter`) — insere o `:` sozinho depois dos 2 primeiros dígitos, nunca deixa passar de 4 dígitos (`HHmm`).
- `validarHorarioOpcional` — campo OPCIONAL (vazio nunca é erro); quando preenchido, exige o formato completo `HH:mm` e a faixa `00:00`–`23:59`.

Aplicado nos 3 campos pedidos:
- "Hora da refeição" (`RefeicoesHabituaisWidget`, dentro de cada linha de refeição habitual) — `TextField` → `TextFormField` (precisava virar `TextFormField` pra `Form.validate()` da tela de Anamnese conseguir pegá-lo).
- "Horário habitual de dormir"/"Horário habitual de acordar" (`AnamneseSelfServicePage`).

## 2. Removido "Usar este valor em Calorias" (Tela Resultado da Avaliação)

O botão (que só copiava o valor da Recomendação Energética pro campo de Calorias da Seção B, nunca salvava nada sozinho) foi removido por pedido explícito. O card de Recomendação Energética continua, só informativo — sem nenhum atalho de cópia.

## 3. AnamneseDetalhesPage ganha o Resultado completo do Motor Metabólico

**Achado da auditoria**: o Gap Crítico do RELATÓRIO `20260917_0001` já persiste o JSON EXATO de `calcular_motor_metabolico_v1` em `anamneses.resultado_motor_v1` no momento em que uma Meta é salva — o mesmo documentado como "GAP CONHECIDO" nos relatórios anteriores (TMB/GET nunca apareciam no Histórico) **já estava fechado no banco**, só faltava ler e exibir. Nenhuma migration nova foi necessária (RESTRIÇÃO cumprida).

- `AnamneseDetalheModel` ganha `resultadoMotorV1` (JSON cru de `anamneses.resultado_motor_v1`); `AnamneseRepository.buscarAnamnesePorId` passa a mapeá-lo (a query já usava `.select()`/`*`, só não extraía a coluna).
- Extraído `MotorMetabolicoResultadoView` (novo widget compartilhado, `lib/features/nutricao/presentation/widgets/motor_metabolico_resultado_view.dart`) a partir da Seção A de `ResultadoMotorMetabolicoPage` — MESMO código/textos (TMB, TDEE médio, Qualidade, Energia Recomendada/VET, disclaimer), eliminando duplicação; `ResultadoMotorMetabolicoPage` passou a usar este widget compartilhado.
- `mostrarMacrosRecomendados` (parâmetro novo, `true` só em `AnamneseDetalhesPage`) — equivalente ESTÁTICO (sem chips/seleção) do seletor de protocolos MACRO-001/002/003 da Seção B, satisfazendo "distribuição de Macronutrientes" numa tela 100% leitura.
- `AnamneseDetalhesPage` exibe isso ao FINAL da tela, com fallback gracioso ("Sem resultado do Motor Metabólico calculado para esta avaliação.") quando nenhuma meta nunca foi salva pra aquela anamnese.

## 4. "Meta já definida" sem a limitação mensal (Tela de Meta de Bem-Estar)

**Achado real**: `MetaBemEstarPage` tinha sua PRÓPRIA trava client-side de "carência 1x/30 dias" (`ultimaMetaPropria.dataCriacao + 30 dias`), 100% alheia ao vínculo por anamnese que a RPC `validar_e_salvar_meta` já usa desde o RELATÓRIO `20261102_0003` (PR #19). Resultado: um usuário podia submeter uma anamnese nova — o SERVIDOR liberaria a gravação na hora — e mesmo assim ficar bloqueado NESTA TELA por uma régua puramente temporal, desatualizada.

- Removida por completo: `_CargaStatus.bloqueadaCarencia`, `_carenciaDias`, `_dataProximaLiberacao`, `_buildProximaRevisao()` (e a mensagem "Próxima revisão disponível em {{data}}"/"1x por mês").
- A tela SEMPRE mostra o formulário (exceto meta profissional ativa ou anamnese severamente vencida — travas que não mudaram); quando há uma meta própria recente, mostra só "Meta já definida" (informativo, nunca bloqueia).
- O servidor é agora o ÚNICO decisor: se ele recusar (mesmo ciclo de anamnese), o modal de bloqueio avisa — título renomeado de "Meta já definida este mês" para "Meta já definida", e a mensagem "Você só pode alterar sua meta de bem-estar 1x por mês." foi removida (o AlertDialog aceita `content: null` agora).
- Chaves i18n mortas removidas (`meta_carencia_titulo`, `meta_carencia_mensagem`, `meta_proxima_revisao_label`, `meta_proxima_revisao_disponivel`, `meta_bloqueio_carencia_mensagem`); nova `meta_ja_definida_label`.

## Testes

- `hora_input_formatter_test.dart` (novo) — 8 testes unitários do formatter/validator.
- `refeicoes_habituais_widget_test.dart` (novo) — 6 testes de widget (máscara, limite de 4 dígitos, validação opcional/formato/intervalo).
- `anamnese_self_service_page_test.dart` — +1 teste (máscara aplicada nos 2 campos de sono).
- `resultado_motor_metabolico_page_test.dart` — botão "Usar este valor em Calorias" trocado por `findsNothing`.
- `anamnese_detalhes_page_test.dart` — +2 testes (fallback sem snapshot; snapshot completo renderizando TMB/TDEE/Qualidade/Energia/Macros).
- `meta_bem_estar_page_test.dart` — teste de bloqueio por carência reescrito pra "NÃO bloqueia"; teste de "próxima revisão" trocado por "Meta já definida"; +1 teste novo (modal do servidor sem a mensagem de limitação mensal).

## Verificação

- `flutter analyze` (lib/test de nutrição): sem issues.
- `flutter test` completo: **586/586** (era 568/568, +18).
- Nenhuma migration/RPC nova — 100% Flutter, conforme Restrição.

## Arquivos

- `lib/features/nutricao/presentation/widgets/hora_input_formatter.dart` (novo).
- `lib/features/nutricao/presentation/widgets/motor_metabolico_resultado_view.dart` (novo).
- `lib/features/nutricao/presentation/widgets/refeicoes_habituais_widget.dart`.
- `lib/features/nutricao/presentation/pages/anamnese_self_service_page.dart`.
- `lib/features/nutricao/presentation/pages/resultado_motor_metabolico_page.dart`.
- `lib/features/nutricao/presentation/pages/anamnese_detalhes_page.dart`.
- `lib/features/nutricao/presentation/pages/meta_bem_estar_page.dart`.
- `lib/features/nutricao/presentation/widgets/meta_bloqueio_modal.dart`.
- `lib/features/nutricao/data/models/anamnese_models.dart`.
- `lib/features/nutricao/data/repositories/anamnese_repository.dart`.
- `assets/i18n/pt.json`, `en.json`, `es.json`.
- Testes: `hora_input_formatter_test.dart` (novo), `refeicoes_habituais_widget_test.dart` (novo), `anamnese_self_service_page_test.dart`, `resultado_motor_metabolico_page_test.dart`, `anamnese_detalhes_page_test.dart`, `meta_bem_estar_page_test.dart`.

Branch `fix/anamnese-ux-mascara-metas`, a partir de `fix/trava-meta-link-resultado` (PR #19, ainda não mesclada).
