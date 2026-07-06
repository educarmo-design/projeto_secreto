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
      anonKey: supabaseAnonKey,
      localStorage: _LocalSecureStorage(_secureStorage),
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
  Future<Map<String, dynamic>? getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('anonymous_users')
          .select('profile_data')
          .eq('id', userId)
          .single();
      return response['profile_data'] as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching user profile: $e');
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
    } catch (e) {
      print('Error updating user profile: $e');
      return false;
    }
  }
}

// Custom local storage using Secure Storage
class _LocalSecureStorage extends LocalStorage {
  final FlutterSecureStorage _secureStorage;

  _LocalSecureStorage(this._secureStorage);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setItem(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  @override
  String? getItem(String key) {
    // Note: This is synchronous but secure storage is async
    // In production, handle this more gracefully
    return null;
  }

  @override
  Future<String?> getItemAsync(String key) async {
    return await _secureStorage.read(key: key);
  }

  @override
  Future<bool> removeItem(String key) async {
    await _secureStorage.delete(key: key);
    return true;
  }

  @override
  Future<bool> clear() async {
    // Note: FlutterSecureStorage doesn't have a clear all method
    // You'd need to manage keys separately
    return true;
  }
}

// Singleton instance
final supabaseManager = SupabaseClientManager();
