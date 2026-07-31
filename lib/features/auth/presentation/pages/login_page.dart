import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/security/crypto_storage_service.dart';
import '../../../../core/security/password_policy.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/cadastro_controller.dart';
import '../widgets/social_auth_buttons.dart';
import 'recuperar_senha_page.dart';

/// Bank-grade login screen (Zero Trust §5): dark/high-contrast UI, strict
/// password strength, and a hardware-gated biometric quick-access path that
/// restores the last session without ever showing the password field again.
///
/// Login Unificado (Google/Apple) shares
/// [CadastroController.autenticarComProvedorSocial] with [CadastroPage] —
/// same OAuth wiring, same "capture + encrypt + biometric-gate the session
/// token" rule. That shared persistence is exactly why the biometric
/// quick-access button above already covers social sessions transparently:
/// once a Google/Apple sign-in stores its refresh token via
/// [CryptoStorageService.persistSessionToken], the next app open restores it
/// through the very same [_attemptBiometricLogin] path as a password login.
///
/// Deliberately does not navigate on success — [AppRouter]'s
/// `refreshListenable` already re-evaluates redirects on every
/// `auth.onAuthStateChange` event, so a successful `signInWithPassword` /
/// `setSession` / social sign-in here is enough to make GoRouter route the
/// user away from `/login` on its own. [onLoginSuccess] is only an optional
/// test/telemetry hook, mirroring [CadastroPage]'s `onSubmit`.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  /// Only used here for [CadastroController.autenticarComProvedorSocial] —
  /// the CEP/OTP surface of this controller is irrelevant to a login
  /// screen, but the OAuth wiring is explicitly shared with [CadastroPage]
  /// so both screens behave identically for Google/Apple.
  final CadastroController _socialAuthController = CadastroController();

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _nonDigits = RegExp(r'[^0-9]');

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  bool _isBiometricAttempting = false;
  bool _hasStoredBiometricToken = false;
  OAuthProvider? _socialProviderLoading;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final hasToken = await cryptoStorage.hasStoredSessionToken();
    if (!mounted) return;
    setState(() => _hasStoredBiometricToken = hasToken);
    if (hasToken) {
      // "Dispara o sensor biométrico imediatamente" — fires once
      // automatically; a manual retry button stays available below in case
      // the user cancels the OS challenge.
      _attemptBiometricLogin();
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _socialAuthController.dispose();
    super.dispose();
  }

  Future<void> _attemptBiometricLogin() async {
    if (_isBiometricAttempting) return;
    setState(() {
      _isBiometricAttempting = true;
      _errorMessage = null;
    });

    final refreshToken = await cryptoStorage.readSessionTokenWithBiometrics(
      reason: i18n.tr('auth.biometric_prompt_reason'),
    );

    if (!mounted) return;

    if (refreshToken == null) {
      setState(() => _isBiometricAttempting = false);
      return;
    }

    try {
      await supabaseManager.client.auth.setSession(refreshToken);
      if (!mounted) return;
      widget.onLoginSuccess?.call();
    } on AuthException catch (e) {
      // Stored token is stale/revoked — wipe it so the button stops
      // reappearing for a session that can never succeed again.
      await cryptoStorage.clearSessionToken();
      if (!mounted) return;
      setState(() {
        _hasStoredBiometricToken = false;
        _errorMessage = e.message;
      });
    } finally {
      if (mounted) setState(() => _isBiometricAttempting = false);
    }
  }

  Future<void> _submitWithPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    final isEmail = _emailRegex.hasMatch(identifier);

    try {
      final response = await supabaseManager.client.auth.signInWithPassword(
        email: isEmail ? identifier : null,
        phone: isEmail ? null : identifier.replaceAll(_nonDigits, ''),
        password: password,
      );

      final refreshToken = response.session?.refreshToken;
      if (refreshToken != null && await cryptoStorage.isBiometricAvailable()) {
        await cryptoStorage.persistSessionToken(refreshToken);
      }

      if (!mounted) return;
      widget.onLoginSuccess?.call();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleSocialAuth(OAuthProvider provider) async {
    if (_socialProviderLoading != null) return;

    setState(() {
      _socialProviderLoading = provider;
      _errorMessage = null;
    });

    final result = await _socialAuthController.autenticarComProvedorSocial(
      provider: provider,
    );
    if (!mounted) return;
    setState(() => _socialProviderLoading = null);

    if (!result.success) {
      setState(() => _errorMessage = result.errorMessage);
      return;
    }

    widget.onLoginSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: getDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 56,
                      color: AppColors.primaryGold,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      i18n.tr('auth.login_title'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      i18n.tr('auth.login_subtitle'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _identifierController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.email,
                        AutofillHints.telephoneNumber,
                      ],
                      decoration: InputDecoration(
                        labelText: i18n.tr('auth.login_identifier_label'),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        return trimmed.isEmpty
                            ? i18n.tr('auth.login_identifier_required')
                            : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: i18n.tr('auth.password_label'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: PasswordPolicy.validate,
                      onFieldSubmitted: (_) => _submitWithPassword(),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submitWithPassword,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(i18n.tr('auth.login_button')),
                    ),
                    // DESABILITADO (31/jul/2026): BUG #3 — biometria exige
                    // fluxo de enrollment em `perfil`, ainda não construído.
                    // Remoção temporária até que o fluxo esteja pronto.
                    // if (_hasStoredBiometricToken) ...[
                    //   const SizedBox(height: 16),
                    //   OutlinedButton.icon(
                    //     onPressed: _isBiometricAttempting
                    //         ? null
                    //         : _attemptBiometricLogin,
                    //     icon: _isBiometricAttempting
                    //         ? const SizedBox(
                    //             width: 16,
                    //             height: 16,
                    //             child:
                    //                 CircularProgressIndicator(strokeWidth: 2),
                    //           )
                    //         : const Icon(Icons.fingerprint),
                    //     label: Text(i18n.tr('auth.biometric_login_button')),
                    //   ),
                    // ],
                    // RecuperarSenhaPage não é uma rota do GoRouter (o
                    // roteador só tem as 4 rotas reais — login/cadastro/
                    // profile-selection/home; ver app_router.dart) — abre
                    // por cima da tela atual via Navigator, mesmo padrão de
                    // CameraCaptureView/GerirVinculosPage.
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RecuperarSenhaPage(),
                          ),
                        ),
                        child: Text(i18n.tr('auth.forgot_password_link')),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SocialAuthButtons(
                      dividerLabelKey: 'auth.login_social_divider',
                      googleLabelKey: 'auth.login_with_google',
                      appleLabelKey: 'auth.login_with_apple',
                      loadingProvider: _socialProviderLoading,
                      onProviderSelected: _handleSocialAuth,
                    ),
                    const SizedBox(height: 16),
                    // Diferente do botão acima, /cadastro JÁ é uma rota real
                    // do GoRouter — navega por ele (context.pushNamed), não
                    // por um Navigator.push avulso, para não abrir uma
                    // segunda instância de CadastroPage fora do controle do
                    // roteador.
                    TextButton(
                      onPressed: () => context.pushNamed(RouteNames.cadastro),
                      child: Text(i18n.tr('auth.create_account_link')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
