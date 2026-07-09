import '../i18n/i18n_manager.dart';

/// Bank-grade password strength policy shared by [LoginPage] and
/// [CadastroPage] so both screens reject the same weak passwords instead of
/// each hand-rolling its own regex.
///
/// Requires: 8+ characters, at least one letter, one digit and one special
/// character. This is a client-side UX gate only — Supabase Auth's own
/// server-side minimum length is the actual enforcement boundary.
class PasswordPolicy {
  const PasswordPolicy._();

  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _hasSpecialChar = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\[\]\\/~`+=;]');

  static const int minLength = 8;

  /// Returns `null` when [value] satisfies the policy, otherwise an
  /// i18n-translated error message suitable for a [TextFormField] validator.
  static String? validate(String? value) {
    final password = value ?? '';
    if (password.length < minLength) {
      return i18n.tr('auth.password_too_short');
    }
    if (!_hasLetter.hasMatch(password)) {
      return i18n.tr('auth.password_missing_letter');
    }
    if (!_hasDigit.hasMatch(password)) {
      return i18n.tr('auth.password_missing_digit');
    }
    if (!_hasSpecialChar.hasMatch(password)) {
      return i18n.tr('auth.password_missing_special_char');
    }
    return null;
  }

  static bool isValid(String? value) => validate(value) == null;
}
