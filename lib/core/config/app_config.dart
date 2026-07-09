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

  /// Deep link scheme the Google/Apple OAuth browser redirect returns to.
  /// `signInWithOAuth` hands this to the identity provider; the actual
  /// session only lands back in-app once the OS routes that deep link to
  /// `supabase_flutter`'s internal listener, which is what feeds
  /// `auth.onAuthStateChange`. Registering the scheme natively (Android
  /// intent-filter / iOS URL type) is required once the `android`/`ios`
  /// platform folders exist — there are none yet in this project — and is
  /// out of Dart's reach; override via `--dart-define=OAUTH_REDIRECT_URL=...`
  /// for a project-specific scheme.
  static String get oauthRedirectUrl {
    const override = String.fromEnvironment('OAUTH_REDIRECT_URL');
    return override.isNotEmpty
        ? override
        : 'io.supabase.atletagamificacao://login-callback';
  }
}
