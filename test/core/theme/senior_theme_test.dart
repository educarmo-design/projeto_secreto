import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/theme/senior_theme.dart';

/// Regressão do crash real (23/jul/2026): `getSeniorTheme()` derrubava o
/// dashboard inteiro do perfil Sênior/Guardião porque `ThemeData
/// (useMaterial3: true).textTheme` chega com `fontSize == null` em todo
/// estilo, e o código antigo chamava `TextTheme.apply(fontSizeFactor:
/// seniorFontScaleFactor)` nesse estado — o que dispara a assertion
/// `fontSize != null || (fontSizeFactor == 1.0 && fontSizeDelta == 0.0)`
/// do Flutter. Este teste roda em `flutter test` puro (sem widget tree),
/// que é exatamente o estado que expunha o bug — se `getSeniorTheme()`
/// voltar a chamar `.apply(fontSizeFactor:)` diretamente, ele quebra de
/// novo aqui.
void main() {
  test('getSeniorTheme não lança ao construir o TextTheme ampliado', () {
    expect(getSeniorTheme, returnsNormally);
  });

  test('escala cada estilo do TextTheme em seniorFontScaleFactor (~1.3x)', () {
    final tema = getSeniorTheme();
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

    // Os estilos padrão do Material 3 chegam sem fontSize neste ambiente de
    // teste — por isso a comparação usa os tamanhos oficiais da escala
    // tipográfica (mesmo fallback usado internamente pelo tema) em vez de
    // reler `base.textTheme.bodyLarge!.fontSize`, que seria null.
    const tamanhoPadraoBodyLarge = 16.0;
    const tamanhoPadraoTitleLarge = 22.0;

    expect(base.textTheme.bodyLarge!.fontSize, isNull);
    expect(
      tema.textTheme.bodyLarge!.fontSize,
      closeTo(tamanhoPadraoBodyLarge * seniorFontScaleFactor, 0.01),
    );
    expect(
      tema.textTheme.titleLarge!.fontSize,
      closeTo(tamanhoPadraoTitleLarge * seniorFontScaleFactor, 0.01),
    );
  });

  test('mantém a cor de alto contraste exigida no TextTheme', () {
    final tema = getSeniorTheme();
    const onSurfaceEsperado = Color(0xFF14181F);

    expect(tema.textTheme.bodyLarge!.color, onSurfaceEsperado);
    expect(tema.textTheme.displayLarge!.color, onSurfaceEsperado);
  });
}
