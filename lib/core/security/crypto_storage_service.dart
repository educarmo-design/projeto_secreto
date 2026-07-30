import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Hardware-backed "blindagem" (shielding) service for Zero Trust §5:
///
/// 1. Wraps [FlutterSecureStorage] configured for Android Keystore
///    (EncryptedSharedPreferences, hardware-backed on API 23+) and iOS
///    Keychain (device-only, no iCloud sync) — never plain SharedPreferences.
/// 2. Gates release of the biometric quick-login token behind [local_auth]:
///    the encrypted token is written freely, but it can only be *read* after
///    a successful FaceID/fingerprint challenge.
///
/// This service is now purely about LOCAL DEVICE secrets (the biometric
/// session token). Field-level PII encryption used to live here too
/// (`encryptSensitiveField`/`decryptSensitiveField`) but was removed in D2:
/// `perfis_usuarios.nome/telefone/email` are now encrypted AT REST by the
/// database (pgcrypto + Supabase Vault, see
/// `*_d2_pii_criptografia_repouso.sql`). The old device-bound AES key was
/// write-only in practice — it never left the Keystore, so nothing outside
/// the original device (not the server, not the B2B panel, not a reinstall)
/// could ever decrypt it. Server-side crypto fixes that while keeping the key
/// off the client entirely.
class CryptoStorageService {
  CryptoStorageService({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
                synchronizable: false,
              ),
            ),
        _localAuth = localAuth ?? LocalAuthentication();

  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;

  static const String _biometricTokenKey = 'biometric_gated_session_token';

  // ---------------------------------------------------------------------
  // Biometria + token de sessão
  // ---------------------------------------------------------------------

  /// Whether the device has usable biometric hardware (fingerprint/FaceID)
  /// with at least one biometric enrolled.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on Exception catch (e) {
      debugPrint('Erro ao checar disponibilidade biométrica: $e');
      return false;
    }
  }

  /// Whether a hardware-encrypted session token is currently stored — used
  /// by [LoginPage] to decide whether to show the "entrar com biometria"
  /// quick-access button at all.
  Future<bool> hasStoredSessionToken() =>
      _secureStorage.containsKey(key: _biometricTokenKey);

  /// Persists [token] (the Supabase session's refresh token) under hardware
  /// encryption. Called right after a successful password login so the next
  /// app open can offer biometric quick access.
  Future<void> persistSessionToken(String token) =>
      _secureStorage.write(key: _biometricTokenKey, value: token);

  /// Wipes the biometric-gated token — call on explicit logout so a
  /// biometric unlock can never resurrect a session the user signed out of.
  Future<void> clearSessionToken() =>
      _secureStorage.delete(key: _biometricTokenKey);

  /// Runs the device's biometric challenge and, only on success, returns the
  /// stored session token. Returns `null` on cancellation, failure, or if no
  /// token was stored — callers must fall back to the manual e-mail/senha
  /// form in every one of those cases, never auto-retry silently.
  Future<String?> readSessionTokenWithBiometrics({String? reason}) async {
    final authenticated = await _authenticate(reason: reason);
    if (!authenticated) return null;
    return _secureStorage.read(key: _biometricTokenKey);
  }

  Future<bool> _authenticate({String? reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason ?? 'Confirme sua identidade para continuar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on Exception catch (e) {
      debugPrint('Falha na autenticação biométrica: $e');
      return false;
    }
  }
}

/// Singleton instance, mirroring the [supabaseManager] convention used
/// elsewhere in this codebase.
final cryptoStorage = CryptoStorageService();
