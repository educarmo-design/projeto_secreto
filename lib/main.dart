import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/config/app_config.dart';
import 'core/i18n/i18n_manager.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/dashboard/data/services/background_sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Zero Trust: refuse to boot against placeholder credentials. Without this
  // check the app would silently launch pointed at a non-existent project
  // whenever `--dart-define=SUPABASE_URL=...` is forgotten (e.g. a bad CI
  // config), instead of failing loudly at startup.
  if (!AppConfig.hasValidSupabaseCredentials) {
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY not configured. '
      'Run with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }

  // Initialize Supabase
  await supabaseManager.initialize(
    supabaseUrl: AppConfig.supabaseUrl,
    supabaseAnonKey: AppConfig.supabaseAnonKey,
  );

  // Initialize i18n (default to Portuguese)
  await i18n.initialize('pt');

  // Regra de Bateria Eficiente: agenda o sync_diario_wearables para rodar
  // uma vez por dia, de madrugada, só com Wi-Fi + carregador conectados.
  await BackgroundSyncManager.instance.inicializar(debugMode: AppConfig.debugMode);
  await BackgroundSyncManager.instance.agendarSincronizacaoDiaria();

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
