import 'package:flutter/material.dart';

/// Tema do Perfil 2 (Guardião Clínico / Sênior) — PRD Mestre §1/§2/§4.
///
/// Requisitos de acessibilidade: fundo claro, alto contraste (texto preto
/// sobre branco, sem gradientes ou cores competitivas gold/laranja do tema
/// Atleta), sem elementos visuais agressivos (sem badges, sem confete, sem
/// streak/chama) e escala de fontes ampliada (~1.3x) para leitura facilitada.
ThemeData getSeniorTheme() {
  const primary = Color(0xFF0B5FA5); // azul sóbrio — nunca dourado/laranja
  const onSurface = Color(0xFF14181F);
  const background = Color(0xFFFFFFFF);
  const surface = Color(0xFFF4F6F9);

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: primary,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: onSurface,
      error: Color(0xFFB3261E),
      onError: Colors.white,
    ),
  );

  return base.copyWith(
    // Escala de fontes ampliada: mantém a hierarquia (título > corpo)
    // enquanto aumenta a legibilidade geral em ~30%.
    //
    // BUG CORRIGIDO (23/jul/2026): `base.textTheme.apply(fontSizeFactor:
    // seniorFontScaleFactor)` derrubava o dashboard inteiro do perfil
    // Sênior/Guardião com a assertion "fontSize != null ||
    // (fontSizeFactor == 1.0 && fontSizeDelta == 0.0)" do Flutter. Causa
    // raiz confirmada isolando o TextTheme antes do `.apply()`: no Flutter
    // 3.44.5, `ThemeData(useMaterial3: true).textTheme` devolve os 15
    // estilos padrão com `fontSize == null` (o tamanho só é preenchido mais
    // tarde, ao mesclar com `Typography` dentro da árvore de widgets) — ou
    // seja, TODO `TextTheme` recém-criado por `ThemeData()` cai nessa
    // assertion se alguém chamar `.apply(fontSizeFactor: != 1.0)` nele
    // antes dessa mesclagem acontecer, não é peculiaridade deste tema.
    // `_escalarTextTheme` evita o `.apply(fontSizeFactor:)` e escala cada
    // estilo manualmente, caindo para os tamanhos oficiais da escala
    // tipográfica do Material 3 quando `fontSize` vier nulo.
    textTheme: _escalarTextTheme(
      base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface),
      seniorFontScaleFactor,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: onSurface,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: Colors.white,
      elevation: 1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E6EC)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        side: const BorderSide(color: primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
      backgroundColor: background,
      selectedItemColor: primary,
      unselectedItemColor: const Color(0xFF6B7280),
      type: BottomNavigationBarType.fixed,
    ),
  );
}

/// Fator de ampliação de fonte do tema Sênior, também usado fora do
/// [ThemeData] (ex.: `MediaQuery.textScalerOf` overrides) para manter a
/// mesma proporção em widgets que não herdam `TextTheme` diretamente.
const double seniorFontScaleFactor = 1.3;

/// Tamanhos padrão da escala tipográfica do Material 3 (`Typography
/// .material2021`), usados como fallback quando o [TextTheme] de entrada
/// ainda não teve `fontSize` preenchido (ver comentário em [getSeniorTheme]).
const Map<String, double> _tamanhosPadraoMaterial3 = {
  'displayLarge': 57,
  'displayMedium': 45,
  'displaySmall': 36,
  'headlineLarge': 32,
  'headlineMedium': 28,
  'headlineSmall': 24,
  'titleLarge': 22,
  'titleMedium': 16,
  'titleSmall': 14,
  'bodyLarge': 16,
  'bodyMedium': 14,
  'bodySmall': 12,
  'labelLarge': 14,
  'labelMedium': 12,
  'labelSmall': 11,
};

/// Multiplica o `fontSize` de cada estilo de [textTheme] por [fator], sem
/// usar `TextTheme.apply(fontSizeFactor:)` — que quebra com uma assertion
/// do Flutter quando algum estilo de entrada tem `fontSize == null`.
TextTheme _escalarTextTheme(TextTheme textTheme, double fator) {
  TextStyle? escalar(TextStyle? estilo, String nomePadrao) {
    if (estilo == null) return null;
    final tamanhoBase = estilo.fontSize ?? _tamanhosPadraoMaterial3[nomePadrao]!;
    return estilo.copyWith(fontSize: tamanhoBase * fator);
  }

  return textTheme.copyWith(
    displayLarge: escalar(textTheme.displayLarge, 'displayLarge'),
    displayMedium: escalar(textTheme.displayMedium, 'displayMedium'),
    displaySmall: escalar(textTheme.displaySmall, 'displaySmall'),
    headlineLarge: escalar(textTheme.headlineLarge, 'headlineLarge'),
    headlineMedium: escalar(textTheme.headlineMedium, 'headlineMedium'),
    headlineSmall: escalar(textTheme.headlineSmall, 'headlineSmall'),
    titleLarge: escalar(textTheme.titleLarge, 'titleLarge'),
    titleMedium: escalar(textTheme.titleMedium, 'titleMedium'),
    titleSmall: escalar(textTheme.titleSmall, 'titleSmall'),
    bodyLarge: escalar(textTheme.bodyLarge, 'bodyLarge'),
    bodyMedium: escalar(textTheme.bodyMedium, 'bodyMedium'),
    bodySmall: escalar(textTheme.bodySmall, 'bodySmall'),
    labelLarge: escalar(textTheme.labelLarge, 'labelLarge'),
    labelMedium: escalar(textTheme.labelMedium, 'labelMedium'),
    labelSmall: escalar(textTheme.labelSmall, 'labelSmall'),
  );
}
