import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
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
/// 3. Provides AES-GCM field encryption for sensitive `perfis_usuarios`
///    columns (nome, telefone) using a random 256-bit key that is generated
///    once and never leaves the device's secure storage.
///
/// Caveat (documented, not hidden): the AES key here is device-bound. It
/// protects PII at rest against DB-level exposure (backups, support access,
/// a compromised read-replica) but a fresh install/device cannot decrypt
/// rows written by a previous device — by design, the key never leaves the
/// Keystore/Keychain to be synced anywhere.
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
  static const String _fieldEncryptionKeyKey = 'field_encryption_key_v1';

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

  // ---------------------------------------------------------------------
  // Criptografia de campos sensíveis (nome/telefone em perfis_usuarios)
  // ---------------------------------------------------------------------

  /// Encrypts [plaintext] with AES-256-GCM. The IV is random per call and
  /// prefixed to the ciphertext so a single stored key can decrypt every
  /// row; the whole payload is base64-encoded to fit a `text` column.
  Future<String> encryptSensitiveField(String plaintext) async {
    if (plaintext.isEmpty) return '';
    final key = await _getOrCreateFieldEncryptionKey();
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    final payload = Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    return base64Encode(payload);
  }

  /// Reverses [encryptSensitiveField]. Returns an empty string for empty or
  /// malformed input rather than throwing — a corrupt/legacy plaintext value
  /// must never crash the profile screen.
  Future<String> decryptSensitiveField(String ciphertextBase64) async {
    if (ciphertextBase64.isEmpty) return '';
    try {
      final key = await _getOrCreateFieldEncryptionKey();
      final payload = base64Decode(ciphertextBase64);
      if (payload.length <= 12) return '';
      final iv = enc.IV(Uint8List.sublistView(payload, 0, 12));
      final cipherBytes = Uint8List.sublistView(payload, 12);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      return encrypter.decrypt(enc.Encrypted(cipherBytes), iv: iv);
    } on Exception catch (e) {
      debugPrint('Erro ao decriptar campo sensível: $e');
      return '';
    }
  }

  Future<enc.Key> _getOrCreateFieldEncryptionKey() async {
    final existing = await _secureStorage.read(key: _fieldEncryptionKeyKey);
    if (existing != null) {
      return enc.Key(base64Decode(existing));
    }
    final generated = enc.Key.fromSecureRandom(32);
    await _secureStorage.write(
      key: _fieldEncryptionKeyKey,
      value: base64Encode(generated.bytes),
    );
    return generated;
  }
}

/// Singleton instance, mirroring the [supabaseManager] convention used
/// elsewhere in this codebase.
final cryptoStorage = CryptoStorageService();
