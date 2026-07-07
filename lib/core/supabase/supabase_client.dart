import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SupabaseClientManager {
  static final SupabaseClientManager _instance = SupabaseClientManager._internal();

  factory SupabaseClientManager() {
    return _instance;
  }

  SupabaseClientManager._internal();

  late SupabaseClient _client;
  late FlutterSecureStorage _secureStorage;

  /// Initialize Supabase with secure token storage
  Future<void> initialize({
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    _secureStorage = const FlutterSecureStorage();

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: _LocalSecureStorage(_secureStorage),
      ),
      debug: false,
    );

    _client = Supabase.instance.client;
  }

  /// Get Supabase client instance
  SupabaseClient get client => _client;

  /// Get current authenticated user
  User? get currentUser => _client.auth.currentUser;

  /// Check if user is authenticated
  bool get isAuthenticated => currentUser != null;

  /// Sign in anonymously
  Future<AuthResponse> signInAnonymously() async {
    return await _client.auth.signInAnonymously();
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Store sensitive data in Secure Storage
  Future<void> storeSecurely(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  /// Retrieve sensitive data from Secure Storage
  Future<String?> retrieveSecurely(String key) async {
    return await _secureStorage.read(key: key);
  }

  /// Delete sensitive data from Secure Storage
  Future<void> deleteSecurely(String key) async {
    await _secureStorage.delete(key: key);
  }

  /// Get user profile (anonymous JSONB)
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('anonymous_users')
          .select('profile_data')
          .eq('id', userId)
          .single();
      return response['profile_data'] as Map<String, dynamic>?;
    } on PostgrestException catch (e) {
      debugPrint('Error fetching user profile: ${e.message}');
      return null;
    }
  }

  /// Update user profile (anonymous JSONB)
  Future<bool> updateUserProfile(
    String userId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      await _client
          .from('anonymous_users')
          .update({'profile_data': profileData}).eq('id', userId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('Error updating user profile: ${e.message}');
      return false;
    }
  }
}

/// Encrypted local storage for the Supabase session, backed by
/// FlutterSecureStorage (Keychain on iOS, Keystore-backed EncryptedSharedPreferences
/// on Android). Replaces supabase_flutter's default Hive-based storage, which
/// persists the session to disk unencrypted.
///
/// Implements the actual `LocalStorage` contract exposed by supabase_flutter v2
/// (initialize / hasAccessToken / accessToken / persistSession / removeSession).
class _LocalSecureStorage extends LocalStorage {
  final FlutterSecureStorage _secureStorage;

  _LocalSecureStorage(this._secureStorage);

  static const String _sessionKey = 'supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    return _secureStorage.read(key: _sessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    return _secureStorage.containsKey(key: _sessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _secureStorage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _secureStorage.delete(key: _sessionKey);
  }
}

// Singleton instance
final supabaseManager = SupabaseClientManager();
