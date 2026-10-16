import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/theme/app_theme.dart';

/// RELATÓRIO 20261016_0006 — regressão do "retângulo branco vazio" na
/// tela de Rótulo Nutricional. NÃO é um crash (nenhum `!` desprotegido
/// existe em `_buildResultadoRotulo`/`_buildCampoMacro` — confirmado por
/// leitura de código, documentado no relatório): é CONTRASTE. O perfil
/// Atleta força `ThemeMode.dark` sempre (`UiProfileSwitcher.themeMode`,
/// nunca `ThemeMode.system`) — qualquer `Card`/widget com fundo branco
/// explícito dentro dessa tela herda, por padrão, texto claro
/// (`textTheme`/`colorScheme.onSurface` do tema ESCURO), invisível sobre
/// fundo branco.
///
/// `CameraCaptureView` em si não é testável (`CameraController` do
/// pacote `camera` não é mockável — limitação pré-existente, documentada
/// na própria classe). Este teste isola só o mecanismo do bug/correção —
/// as mesmas 2 `ThemeData` reais do app (`getDarkTheme()`/`getLightTheme()`),
/// no mesmo padrão de `Theme(data: ..., child: ...)` aninhado que o
/// widget real agora usa — sem precisar da câmera.
void main() {
  testWidgets('BUG: sem o Theme local, o Card branco herda texto claro do tema escuro ambiente (perfil Atleta)',
      (tester) async {
    Color? corSemCorrecao;
    await tester.pumpWidget(
      Theme(
        data: getDarkTheme(),
        child: Builder(
          builder: (context) {
            corSemCorrecao = Theme.of(context).textTheme.titleMedium?.color;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // AppColors.lightText (branco) — exatamente o que fica invisível sobre
    // o `Card(color: Colors.white)` da tela de rótulo.
    expect(corSemCorrecao, AppColors.lightText);
  });

  testWidgets('CORREÇÃO: Theme(data: getLightTheme()) local resolve o título do card pra texto escuro, legível sobre branco',
      (tester) async {
    Color? corComCorrecao;
    await tester.pumpWidget(
      // Mesmo aninhamento de `_buildResultadoRotulo`: o tema escuro
      // ambiente da tela por fora, o `Theme(data: getLightTheme())` local
      // do Card por dentro — o de dentro é o que de fato governa a
      // resolução de `Theme.of(context)` no ponto onde o Text é construído.
      Theme(
        data: getDarkTheme(),
        child: Theme(
          data: getLightTheme(),
          child: Builder(
            builder: (context) {
              corComCorrecao = Theme.of(context).textTheme.titleMedium?.color;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(corComCorrecao, AppColors.darkText);
    expect(corComCorrecao, isNot(AppColors.lightText));
  });

  testWidgets('CORREÇÃO: o título do card de macros fica de fato visível (pumpAndSettle sem overflow/erro) sobre fundo branco',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: getDarkTheme(),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Theme(
              data: getLightTheme(),
              child: Card(
                color: Colors.white,
                child: Builder(
                  builder: (context) => Text(
                    'Informações Nutricionais',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final texto = tester.widget<Text>(find.text('Informações Nutricionais'));
    expect(texto.style?.color, isNot(Colors.white));
  });
}
