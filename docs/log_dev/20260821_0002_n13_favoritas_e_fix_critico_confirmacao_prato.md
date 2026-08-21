# 20260821_0002_n13_favoritas_e_fix_critico_confirmacao_prato — Favoritas (N13) + achado: "editar unidade" já estava pronto + FIX CRÍTICO na tela de confirmar refeição

Log de Máquina (Regra 10.3 — append-only). Modo autônomo (fundador
dormindo, autorização ampla). Últimos 2 dos 4 itens da fila de backlog
pedidos (card consumo×meta e N15 já cobertos no RELATÓRIO
20260821_0001).

## 1. "Editar unidade de medida" — achado: já estava pronto

Antes de construir, investiguei `confirmacao_prato_page.dart` a fundo
(Regra: "agentes investigam o código real antes de presumir"). O
Documento Mestre (07/Ago) registra "hoje só edita gramas" como gap do
N12 — **desatualizado**: a tela já tem edição por categoria bem mais
rica que isso, categoria a categoria
(`alimentos_referencia.categoria_consumo`):
- `liquido_frio`/`liquido_quente`: botões de tamanho rápido em ml
  (200/500/700ml ou 50/200ml) + "Customizar" (entrada livre).
- `unidade`/`fatia`: mostra o peso estimado da unidade, com edição.
- `peso_livre`/sem categoria: aviso + edição de peso direto.

Mesmo achado do N14 (RELATÓRIO 20260819_0021 já tinha achado que peso
típico também já estava pronto) — não implementei nada aqui, só
verifiquei e registro pra não haver dúvida de que foi checado, não
ignorado.

## 2. Favoritas (N13)

Spec (Documento Mestre Parte V1.H): "Favoritas por tipo (café/almoço/
jantar/lanche), múltiplas; marcar como favorita ao registrar (seleciona
o tipo); manutenção no perfil (excluir/trocar tipo). Favorita salva com
a medida customizada e volta pronta."

### Entregue
- Migration `20260821010000_n13_alimentos_favoritos.sql` (nova tabela
  `alimentos_favoritos`: `tipo_refeicao` com CHECK dos 4 valores,
  `nome`, `payload_jsonb`, RLS/GRANT completos) — **aplicada no banco
  remoto**.
- `FavoritaModel`/`TipoRefeicao` (enum tipado, nunca string solta) +
  `FavoritasRepository` (`salvar`/`listar`/`excluir`/`atualizarTipo`),
  reaproveitando `ColetaDiariaResult` em vez de duplicar a classe de
  resultado.
- `ConfirmacaoPratoPage`: botão ⭐ na AppBar abre `_DialogoSalvarFavorita`
  (nome + tipo obrigatórios) — salva
  `ConfirmacaoPratoController.payloadRevisado()` **no estado atual**
  (com qualquer edição de quantidade/peso já feita), "com a medida
  customizada" como a spec pede. Independente de confirmar a refeição
  em si.
- `FavoritasPage` (nova) — cobre as DUAS metades da spec na MESMA tela
  (Regra 14): filtro por tipo, tocar numa favorita confirma "Registrar
  agora?" e grava direto via `ColetaDiariaRepository.gravarRefeicao`
  (sem recalcular nada, "volta pronta"), menu por item com "Trocar
  tipo"/"Excluir" (manutenção).
- Entrada em `ConfiguracoesPerfilPage`, mesma convenção de
  `ManualFoodSearchPage` (que também mora ali, não num menu de "3
  opções" dedicado — não inventei um padrão de navegação novo).
- i18n `pt`/`en`/`es` completo (`favoritas.*` + `confirmacao_prato.
  favorita_*`/`tipo_refeicao_*`).

## 3. FIX CRÍTICO (achado no caminho, não pedido, mas real e urgente)

Ao rodar os testes desta tarefa, `confirmacao_prato_page_test.dart`
(que já tinha 11 falhas "pré-existentes" registradas em TODOS os
relatórios desta semana, sempre descritas como "não relacionadas, fora
do escopo") passou a falhar em **14** de 15 testes — incluindo testes
básicos de renderização que eu tinha certeza que passavam antes.

Investigação séria (não presumida): isolei uma `git worktree` limpa do
HEAD, sem nenhuma mudança minha, e rodei só esse arquivo de teste lá.
**Resultado: TODOS os 11 testes já falhavam, desde antes de qualquer
coisa que eu fiz hoje ou nas tarefas anteriores desta semana** — a
contagem "11 falhas conhecidas" que vinha sendo carregada de relatório
em relatório era um subconjunto mal-observado; o arquivo inteiro nunca
tinha rodado limpo.

**Causa raiz real**: `_ItemPratoTile` tinha um `Flexible` como filho
direto de um `Wrap` — combinação estruturalmente inválida no Flutter
(`Wrap` usa `WrapParentData`; `Flexible` exige `FlexParentData`, que só
existe dentro de `Row`/`Column`/`Flex`). Isso derruba a árvore de
widgets com "Incorrect use of ParentDataWidget" toda vez que o card
renderiza — **não é só um problema de teste**: é o card de cada item na
tela de confirmar refeição, a tela mais usada do módulo de nutrição.
Bug de produção real, pré-existente, não introduzido nesta tarefa nem
por mim.

**Corrigido**: removido o `Flexible` (o `Text` dos macros vira filho
direto do `Wrap`, que já dá a cada filho sua própria constraint de
largura — `overflow`/`maxLines` continuam funcionando sem ele). Fix
mínimo e cirúrgico, sem mudar nenhum outro comportamento.

Depois do fix, restou só 1 falha real (não um crash): o teste "mostra
nome, medida, macros e confiança do item" esperava um texto
"Identificado como: {{nome}}" que a implementação atual nunca produziu
— a UI já mostra o nome identificado como TÍTULO (bare) e o nome casado
como subtítulo quando diferem (achado: `confirmacao_prato.
identificado_como` é uma chave i18n órfã, não referenciada em lugar
nenhum do código — sobrou de um redesign anterior que o teste nunca
acompanhou). Corrigido o teste pra bater com a UI real (não mudei a UI —
ela já estava certa).

## Verificação

- `flutter analyze`: limpo (0 erros/warnings novos).
- `favoritas_repository_test.dart` (novo): 9 testes — `salvar` (grava
  campos certos, falha sem login), `listar` (converte, lista vazia sem
  login, lista vazia em erro de rede), `excluir`/`atualizarTipo` (chama
  certo, falha sem login).
- `favoritas_page_test.dart` (novo): 7 testes — carrega e mostra,
  empty state, erro de carga, filtro recarrega com o tipo certo, usar
  favorita confirma+grava+volta `true`, excluir pede confirmação,
  trocar tipo chama `atualizarTipo` com o tipo escolhido.
- `confirmacao_prato_page_test.dart`: 3 testes novos (favoritar com
  nome+tipo válidos salva; sem nome o botão fica desabilitado; cancelar
  nunca chama o repositório) — **e as 11 falhas pré-existentes deste
  arquivo, corrigidas** (fix do Flexible/Wrap + 1 teste desatualizado).
  **15 de 15 passando, arquivo inteiro verde pela primeira vez.**
- `flutter test` (suíte inteira): **389 testes passando, ZERO falhas**
  — primeira vez nesta semana inteira de trabalho que a suíte inteira
  fecha 100% verde (as 11 falhas de `confirmacao_prato_page_test.dart`
  vinham sendo carregadas, descritas como "não relacionadas", em TODOS
  os relatórios desde o início desta sessão longa).

## Não resolvido / próximo passo

Nada verificado em device físico (fundador dormindo). O fix crítico do
`Flexible`/`Wrap` é especialmente importante confirmar visualmente na
tela de confirmar refeição assim que possível — é a mudança de maior
risco/benefício desta tarefa, mesmo sendo pequena.

Com isso, os 4 itens do backlog que o fundador pediu (card consumo×meta,
N15 aparelho por foto, editar unidade de medida, favoritas N13) estão
todos cobertos — os dois primeiros e a investigação do terceiro no
RELATÓRIO 20260821_0001, favoritas neste relatório.
