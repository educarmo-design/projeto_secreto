/// Application configuration constants
class AppConfig {
  /// Supabase Configuration
  /// Set via environment variables or .env file
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key',
  );

  /// The `defaultValue`s above are compile-time placeholders only — Dart
  /// const declarations can't throw. This must be checked at runtime, before
  /// [supabaseUrl]/[supabaseAnonKey] are handed to Supabase.initialize, so the
  /// app fails fast on a missing `--dart-define` instead of silently running
  /// against a URL that doesn't exist (or, worse, against a placeholder that
  /// later happens to be typo-squatted).
  static bool get hasValidSupabaseCredentials =>
      supabaseUrl != 'https://your-project.supabase.co' &&
      supabaseAnonKey != 'your-anon-key' &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty;

  /// App behavior flags
  static const bool debugMode = bool.fromEnvironment(
    'DEBUG_MODE',
    defaultValue: false,
  );

  /// Feature toggles
  static const bool enableOfflineSync = true;
  static const bool enableLocalCaching = true;
  static const bool enableSecureStorage = true;

  /// Gamification config
  static const int defaultPointsPerChallenge = 10;
  static const int streakBonusMultiplier = 2;
  static const int streakBonusInterval = 7; // Every 7 days

  /// CEP validation
  static const List<String> supportedStates = [
    'SP', 'RJ', 'MG', 'BA', 'SC', 'PR', 'RS', 'GO', 'DF',
    'PE', 'CE', 'PA', 'AM', 'ES', 'PB', 'MA', 'MT', 'MS',
    'AC', 'AL', 'AP', 'TO', 'RN', 'RR', 'PI', 'SE'
  ];

  /// Storage keys (must be unique)
  static const String storageKeyUserProfile = 'user_profile';
  static const String storageKeyGamificationState = 'gamification_state';
  static const String storageKeyAuthToken = 'auth_token';
  static const String storageKeySyncTimestamp = 'last_sync_timestamp';

  /// Timeouts (in milliseconds)
  static const int defaultNetworkTimeout = 30000; // 30 seconds
  static const int minSyncInterval = 60000; // 1 minute
  static const int streakResetTimeout = 86400000; // 24 hours

  /// Validation rules
  static const int minDisplayNameLength = 3;
  static const int maxDisplayNameLength = 50;
  static const String cepRegex = r'^\d{5}-\d{3}$';

  /// Offline mode
  static const bool offlineModeEnabled = true;
  static const int maxLocalCacheSize = 10485760; // 10MB in bytes

  /// Endpoint that receives a device-photo's raw bytes and returns the
  /// metric extracted by Gemini 2.5 Flash as JSON. Defaults to a Supabase
  /// Edge Function under the already-configured project (zero new infra);
  /// override via `--dart-define=METRIC_PHOTO_EXTRACTION_ENDPOINT=...` for
  /// a standalone deployment.
  static String get metricPhotoExtractionEndpoint {
    const override = String.fromEnvironment('METRIC_PHOTO_EXTRACTION_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/extract-metric-photo';
  }

  /// Endpoint that receives an old exam PDF's raw bytes (Esteira dos 14
  /// Dias Free — Semana 1 missions) and stores/parses it server-side.
  /// Same zero-new-infra convention as [metricPhotoExtractionEndpoint]:
  /// defaults to a Supabase Edge Function; override via
  /// `--dart-define=EXAM_UPLOAD_ENDPOINT=...` for a standalone deployment.
  static String get examUploadEndpoint {
    const override = String.fromEnvironment('EXAM_UPLOAD_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/upload-exam-pdf';
  }

  /// Endpoint that receives a compact textual summary of recent biomarkers
  /// + detected anomalies and returns a single Gemini 2.5 Flash-generated
  /// preventive insight as JSON. Same zero-new-infra convention as
  /// [metricPhotoExtractionEndpoint]: defaults to a Supabase Edge Function
  /// (which holds the actual Google AI Studio key server-side — never
  /// shipped in the client binary); override via
  /// `--dart-define=PREVENTIVE_INSIGHT_ENDPOINT=...` for a standalone
  /// deployment.
  static String get preventiveInsightEndpoint {
    const override = String.fromEnvironment('PREVENTIVE_INSIGHT_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/generate-preventive-insight';
  }

  /// Endpoint that receives a GZIP-compressed batch of anonymized
  /// [B2BAnalyticsPayload]s (ONDA 3 — Painel Web das Seguradoras/Médicos).
  /// Same zero-new-infra convention as the other endpoints above: defaults
  /// to a Supabase Edge Function under the already-configured project;
  /// override via `--dart-define=B2B_ANALYTICS_ENDPOINT=...` for a
  /// standalone deployment. The Edge Function — not this client — is the
  /// only place with the elevated (service-role-scoped) access needed to
  /// fan a batch out to the actual insurer/doctor-facing panel; this app
  /// only ever uploads its own already-anonymized, already-RLS-scoped data.
  static String get b2bAnalyticsEndpoint {
    const override = String.fromEnvironment('B2B_ANALYTICS_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/ingest-b2b-analytics';
  }

  /// Endpoint of the `calculate-recovery-mode` Edge Function (Etapa 0.5 —
  /// F21). Replaces the local date-anchor arithmetic that used to live in
  /// [EsteiraTrialController] — server-side by the same "Regra de
  /// arquitetura inegociável" (PRD Mestre §0.5) already applied to
  /// streaks/points elsewhere: a client-computed trial day/freeze state is
  /// trivially manipulable by reverse engineering. Same zero-new-infra
  /// convention as the other endpoints above; override via
  /// `--dart-define=CALCULATE_RECOVERY_MODE_ENDPOINT=...` for a standalone
  /// deployment. As of Etapa 0.5 this Edge Function is a stub (HTTP 501) —
  /// see supabase/functions/calculate-recovery-mode/index.ts.
  static String get calculateRecoveryModeEndpoint {
    const override =
        String.fromEnvironment('CALCULATE_RECOVERY_MODE_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/calculate-recovery-mode';
  }

  /// Endpoint of the `manage-professional-link` Edge Function (Motor de
  /// Vínculos — Adendo v4, Parte F). O app do paciente usa só as ações
  /// `aceitar_vinculo`/`encerrar_vinculo` (ver
  /// [ManageProfessionalLinkGatewayService]); `criar_vinculo` é do painel web
  /// do profissional, fora deste app. Same zero-new-infra convention as the
  /// other endpoints above; override via
  /// `--dart-define=MANAGE_PROFESSIONAL_LINK_ENDPOINT=...` for a standalone
  /// deployment.
  static String get manageProfessionalLinkEndpoint {
    const override =
        String.fromEnvironment('MANAGE_PROFESSIONAL_LINK_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/manage-professional-link';
  }

  /// Endpoint of the `search-food` Edge Function (Adendo v5.1 §A.3/§C.3 —
  /// "Cérebro da Busca"): recebe `{"query": "texto"}` e devolve os alimentos
  /// mais próximos por similaridade de embedding, para a Busca Manual de
  /// Alimentos (registro manual quando o usuário não quer usar a câmera).
  /// Same zero-new-infra convention as the other endpoints above; override
  /// via `--dart-define=SEARCH_FOOD_ENDPOINT=...` for a standalone
  /// deployment.
  static String get searchFoodEndpoint {
    const override = String.fromEnvironment('SEARCH_FOOD_ENDPOINT');
    return override.isNotEmpty
        ? override
        : '$supabaseUrl/functions/v1/search-food';
  }

  /// Deep link scheme the Google/Apple OAuth browser redirect returns to,
  /// AND the password recovery e-mail redirect. `signInWithOAuth` +
  /// `resetPasswordForEmail` hand this to identity providers; the actual
  /// session/recovery event only lands back in-app once the OS routes that
  /// deep link to `supabase_flutter`'s internal listener, which feeds
  /// `auth.onAuthStateChange`. Registering the scheme natively (Android
  /// intent-filter / iOS URL type) is required in `android/`/`ios/` platform
  /// folders; override via `--dart-define=OAUTH_REDIRECT_URL=...` for a
  /// project-specific scheme.
  /// CORRIGIDO (31/jul/2026): scheme deve ser `io.supabase.atletaapp`, não
  /// `atletagamificacao` (ver BUG #2: password recovery deep link).
  static String get oauthRedirectUrl {
    const override = String.fromEnvironment('OAUTH_REDIRECT_URL');
    return override.isNotEmpty
        ? override
        : 'io.supabase.atletaapp://login-callback';
  }
}
