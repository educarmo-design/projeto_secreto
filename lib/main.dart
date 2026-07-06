import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/i18n/i18n_manager.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await supabaseManager.initialize(
    supabaseUrl: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://your-project.supabase.co',
    ),
    supabaseAnonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'your-anon-key',
    ),
  );

  // Initialize i18n (default to Portuguese)
  await i18n.initialize('pt');

  runApp(const AtletaGamificacaoApp());
}

class AtletaGamificacaoApp extends StatefulWidget {
  const AtletaGamificacaoApp({Key? key}) : super(key: key);

  @override
  State<AtletaGamificacaoApp> createState() => _AtletaGamificacaoAppState();
}

class _AtletaGamificacaoAppState extends State<AtletaGamificacaoApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: i18n.tr('app_title'),
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      themeMode: ThemeMode.light, // or ThemeMode.system for device preference
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
        Locale('es', 'ES'),
      ],
      locale: _getCurrentLocale(),
      routerConfig: AppRouter.router,
    );
  }

  /// Get current locale based on i18n manager
  Locale _getCurrentLocale() {
    final language = i18n.currentLanguage;
    switch (language) {
      case 'pt':
        return const Locale('pt', 'BR');
      case 'en':
        return const Locale('en', 'US');
      case 'es':
        return const Locale('es', 'ES');
      default:
        return const Locale('pt', 'BR');
    }
  }
}
