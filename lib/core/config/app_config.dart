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
}
