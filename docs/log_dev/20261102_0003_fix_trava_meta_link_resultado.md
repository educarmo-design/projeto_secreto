# 20261102_0003 — Trava residual de 30 dias na Meta + acesso ao Resultado da Anamnese

## Contexto

Teste em device físico, conclusão da anamnese. Dois problemas reportados pelo fundador:

1. Ao tentar gravar a meta calculada pelo Motor Metabólico no fim da anamnese, o sistema bloqueava alegando carência de 30 dias — mesmo tendo acabado de submeter uma avaliação nova. "A meta precisa obedecer ao mesmo ciclo da anamnese."
2. O usuário não conseguia acessar/visualizar o resultado completo da anamnese finalizada — faltava um direcionamento claro ao concluir, e um link explícito no histórico.

## 1. Trava de carência mensal segue o ciclo da anamnese

### Achado

`validar_e_salvar_meta` (RPC N08) bloqueava (`N08_CARENCIA_MENSAL`) sempre que existisse qualquer meta self-service gravada nos últimos 30 dias — independente de uma anamnese nova ter sido submetida nesse meio-tempo. Nenhuma trava client-side (Flutter) existia; o bloqueio é 100% da RPC.

Desde o RELATÓRIO `20261102_0002`, `objetivos_alimentares.anamnese_id` (FK direta) já identifica exatamente a qual anamnese cada meta pertence — a peça que faltava pra resolver isto sem inventar uma heurística nova.

### Correção (migration `20261102150000`)

A condição de `N08_CARENCIA_MENSAL` passou a comparar o `anamnese_id` da última meta própria com o `anamnese_id` resolvido AGORA (mesma função `calcular_motor_metabolico_v1` que já alimenta a FK): só bloqueia se os dois forem a MESMA anamnese (`is not distinct from`, null-safe — preserva o comportamento antigo quando não há nenhum dado de anamnese pra decidir). Uma anamnese nova sempre libera a gravação, mesmo dentro dos 30 dias.

A resolução do `anamnese_id` (que antes só acontecia DEPOIS do INSERT, só para o snapshot) subiu para ANTES da checagem de carência — sem chamar a função duas vezes.

### Verificação end-to-end real em produção

Coincidentemente, o usuário de teste (`atleta1000@teste.com`) tinha uma anamnese nova genuína submetida minutos antes desta tarefa (às 22:48, provavelmente o próprio teste em device físico que motivou o relato) — uma reprodução real do bug, não simulada:

- Última meta própria (`6d4caf7d-...`) estava atrelada à anamnese `923de9e1-...` (ativa até então).
- Uma anamnese nova (`3894ee64-...`, peso atualizado 80.40kg) tinha sido submetida depois.
- Chamei `validar_e_salvar_meta` simulando a sessão deste usuário: **sucesso imediato**, mesmo dentro dos 30 dias — a nova meta (`480aa8c2-...`) foi gravada com `anamnese_id = '3894ee64-...'` (a anamnese nova), exatamente o comportamento pedido.
- Chamei de novo imediatamente depois, SEM nenhuma anamnese nova no meio: **bloqueado corretamente** com `N08_CARENCIA_MENSAL` — confirma que a proteção original (não editar a mesma meta repetidamente) continua ativa.
- Snapshot do Gap Crítico (`anamneses.resultado_motor_v1`/`resultado_motor_gravado_em`) continuou sendo gravado normalmente na anamnese nova.

## 2. Redirecionamento e link de acesso ao resultado

### Mudanças no Flutter

- `AnamneseRepository.salvarAnamnese` agora devolve `Future<String>` (o `id` da anamnese recém-criada) em vez de `Future<void>` — o valor já existia internamente, só era descartado.
- `ConfirmarAnamnesePage` captura esse id e passa para `ResultadoMotorMetabolicoPage(anamneseId: ...)`.
- `ResultadoMotorMetabolicoPage`:
  - Novo botão primário, sempre visível na Seção A (Resultados Calculados): **"Ver Resultado da Prescrição"** — abre `AnamneseDetalhesPage` desta anamnese via `push` (o usuário pode voltar e ainda preencher a meta).
  - Ao salvar a meta com sucesso OU tocar "Definir Depois" (pular), a tela agora SUBSTITUI a si mesma (`pushReplacement`) por `AnamneseDetalhesPage` — antes (`_fecharFluxo`) fazia `pop(); pop();` e fechava o fluxo inteiro sem mostrar nada, a causa raiz do item 2 do bug reportado. Mesma profundidade de pilha de antes (troca só o topo).
  - `AnamneseDetalhesPage`, alcançada por qualquer um desses 3 caminhos, já mostra o formulário completo + o card "Plano de Metas" (badge de origem, macros) vinculado por FK (`anamnese_id`, RELATÓRIO `20261102_0002`) — inclusive a meta que acabou de ser salva, se foi o caso.
- `HistoricoAnamnesesPage`: cada card do histórico ganhou um botão explícito e sempre visível **"Ver Detalhes / Prescrição"** (com ícone), abaixo do conteúdo do card — o card inteiro continua tocável como atalho, mas não é mais a ÚNICA afordância (achado real: o fundador não percebia que o card era clicável).

### i18n

Novas chaves em `pt`/`en`/`es`: `nutricao.resultado_motor_ver_prescricao_button`, `nutricao.historico_anamnese_ver_detalhes_button`.

## Verificação

- `flutter analyze` (lib/test de nutrição): sem issues.
- `flutter test` completo: **568/568** (era 566/566, +2 testes novos: botão "Ver Resultado da Prescrição" e botão explícito no Histórico; mais ajustes nos testes existentes para o novo destino pós-conclusão e o retorno de `salvarAnamnese`).
- Migration aplicada em produção (`supabase db push --linked`).
- Verificação end-to-end real (RPC) descrita na seção 1 acima.

## Arquivos

- `supabase/migrations/20261102150000_validar_e_salvar_meta_carencia_segue_ciclo_anamnese.sql` (nova).
- `lib/features/nutricao/data/repositories/anamnese_repository.dart` (`salvarAnamnese` devolve o id).
- `lib/features/nutricao/presentation/pages/confirmar_anamnese_page.dart`.
- `lib/features/nutricao/presentation/pages/resultado_motor_metabolico_page.dart`.
- `lib/features/nutricao/presentation/pages/historico_anamneses_page.dart`.
- `assets/i18n/pt.json`, `en.json`, `es.json`.
- `test/features/nutricao/data/repositories/anamnese_repository_test.dart`.
- `test/features/nutricao/presentation/pages/confirmar_anamnese_page_test.dart`.
- `test/features/nutricao/presentation/pages/resultado_motor_metabolico_page_test.dart`.
- `test/features/nutricao/presentation/pages/historico_anamneses_page_test.dart`.

Branch `fix/trava-meta-link-resultado`, a partir de `main`.
