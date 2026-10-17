# "Retângulo branco vazio" na tela de Rótulo — não era crash, era contraste

**Tipo:** RCA (4ª rodada desta saga) + correção. Fundador enviou screenshot
do device físico: topo ("Porção") e rodapé (chips de ingredientes)
renderizam perfeitamente; o meio da tela — onde deveria estar o card de
macros — é um bloco branco 100% vazio, sem nenhum campo visível.

## A hipótese de "crash de RenderBox / NPE" foi descartada com leitura de código

A tarefa chegou com uma hipótese forte: algum `!` (force unwrap) perigoso em
`_buildResultadoRotulo`/`_buildCampoMacro` quebrando a árvore de widgets
quando a IA devolve macro nulo. Antes de escrever qualquer código, reli os
dois métodos inteiros:

- Os únicos 2 `!` que existem no arquivo (`extracao!.porcaoDescricao!` e
  `extracao!.ingredientesPrincipais`) estão **blindados** por um `if
  (extracao?.campo != null)`/`if (extracao?.lista.isNotEmpty ?? false)`
  imediatamente acima — nunca executam com `extracao` nulo. Não há como
  disparar um NPE por aqui.
- `_buildCampoMacro` **não tem nenhum `!`** — o `TextEditingController` já
  chega pré-populado (ou vazio) por `_preencherCamposRotulo`, que já trata
  cada macro nulo como string vazia (`extracao.caloriasKcal == null ? '' :
  ...`). Os campos de macro já eram, e continuam sendo, 100% null-safe.

Ou seja: **não existe crash nenhum nesta tela** — nem hoje, nem na versão
anterior. Um `RenderBox`/NPE de verdade também não se parece com "um
retângulo branco liso": em debug aparece a tela vermelha padrão do Flutter;
em release, o erro vai para o log nativo, não produz silenciosamente um
`Container` branco do tamanho exato de um `Card`.

## Causa raiz real, confirmada por leitura do tema do app

`Card(color: Colors.white, ...)` é a ÚNICA parte desta tela com fundo claro
explícito — todo o resto (porção, aviso de foto de tela, ingredientes) usa
texto branco/`white70` sobre o `Scaffold` preto da própria tela. O título do
card e os `TextFormField` dos 4 macros, porém, **não tinham nenhuma cor
própria** — herdavam o que o `Theme` ambiente definisse.

`UiProfileSwitcher.themeMode` (`lib/core/router/ui_profile_switcher.dart:63`)
força `ThemeMode.dark` para o perfil Atleta **sempre** (nunca
`ThemeMode.system`) — e em `getDarkTheme()` (`app_theme.dart`),
`textTheme.titleMedium`/o texto/label padrão de `TextFormField`
(`colorScheme.onSurface`) resolvem para `AppColors.lightText`
(`0xFFFFFFFF`, branco). Resultado: título e os 4 campos de macro renderizavam
**texto branco dentro de um Card branco** — tecnicamente presentes na árvore
de widgets, perfeitamente "retângulo branco vazio" a olho nu. Exatamente o
padrão relatado: topo/rodapé usam cor explícita (visíveis), o meio é o único
widget sem cor explícita sobre fundo claro (invisível).

Confirmado que esta tela não roda em nenhum `ThemeMode.light`/`system` real
(forçado sempre escuro para Atleta) — não é uma condição rara, acontece
**toda vez** que a IA extrai algo (mesmo com todos os 4 macros presentes, o
TÍTULO do card já ficava invisível; com macro ausente, o campo inteiro ficava
sem nenhum traço visível de rótulo, texto ou valor).

## Correção

`_buildResultadoRotulo` — o `Card` branco (e só ele) agora é envolvido por
`Theme(data: getLightTheme(), child: Card(...))`, mesmo idioma já usado em
outras telas deste app para forçar um tema específico num subtree
independente do ambiente (`main_navigation_page.dart`,
`gerenciador_layout_page.dart`: `Theme(data: getDarkTheme(), child: ...)`,
aqui invertido porque o fundo local é claro). Isso resolve o título e os 4
`TextFormField` (texto, label, cursor, borda de foco) para as cores do tema
CLARO — legível sobre o `Card` branco, independente do tema ambiente da
tela (preto/escuro para Atleta).

### Item 2 da tarefa — `errorBuilder` de imagem

**Não aplicável, confirmado pela 4ª vez nesta saga**: busca exaustiva por
`Image.file`/`Image.memory`/`Image.network`/`Image.asset`/`DecorationImage`/
`FadeInImage`/`CachedNetworkImage`/`RawImage`/`MemoryImage`/`FileImage` em
todo `lib/` continua devolvendo zero resultados. Não existe, nunca existiu,
nenhum widget de imagem nesta tela (pipeline Zero Storage, câmera 100% ao
vivo) — não há nada para colocar um `errorBuilder`. O "retângulo branco" era
sempre o Card de macros com texto invisível, não uma foto quebrada.

### Item 1 da tarefa — null-safety dos macros

Já era null-safe (ver seção acima) — nenhuma mudança de lógica foi
necessária, só a correção de cor/tema. Nenhum `!` foi removido porque nenhum
`!` perigoso existia.

## Verificação

- Novo teste `test/features/dashboard/presentation/widgets/camera_capture_view_macro_card_theme_test.dart`
  (3 testes): reproduz o mecanismo exato do bug com as `ThemeData` reais do
  app (`getDarkTheme()`/`getLightTheme()`) — confirma que, sem o `Theme`
  local, o título resolve para `AppColors.lightText` (branco, o bug); com o
  `Theme(data: getLightTheme())` aninhado (a correção), resolve para
  `AppColors.darkText`; terceiro teste monta o `Card` branco de verdade e
  confirma que o texto não fica branco-sobre-branco.
  `CameraCaptureView` em si continua sem teste próprio — limitação
  pré-existente documentada (`CameraController` não é mockável).
- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: **522/522** (era 519/519, +3 novos).

## Banco de dados

Nenhuma alteração — Restrição explícita da tarefa. Nenhuma Edge Function
alterada — **sem deploy pendente**.

Branch `fix/ui-crash-rotulo-branco`, a partir de `main`.
