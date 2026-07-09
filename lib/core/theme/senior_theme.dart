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
    // Escala de fontes ampliada: fontSizeFactor multiplica cada estilo do
    // TextTheme padrão do Material 3 — mantém a hierarquia (título > corpo)
    // enquanto aumenta a legibilidade geral em ~30%.
    textTheme: base.textTheme.apply(
      fontSizeFactor: seniorFontScaleFactor,
      bodyColor: onSurface,
      displayColor: onSurface,
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
