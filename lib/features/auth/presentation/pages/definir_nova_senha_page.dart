import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/router/auth_recovery_controller.dart';
import '../../../../core/security/password_policy.dart';
import '../../../../core/theme/app_theme.dart';

/// Última etapa do fluxo "Esqueci minha senha": só alcançável pelo redirect
/// do [AppRouter] enquanto [authRecoveryController.emRecuperacao] é `true`
/// — a sessão que o deep link do e-mail de recuperação já deixou pronta
/// para chamar `auth.updateUser`. Nenhum botão do app navega pra cá
/// diretamente (ver [RouteNames.definirNovaSenha]).
///
/// Cru de propósito (Adendo v5.1 §B): senha nova + confirmação, mesma
/// `PasswordPolicy` do cadastro/login, sem nenhum acabamento visual extra.
class DefinirNovaSenhaPage extends StatefulWidget {
  const DefinirNovaSenhaPage({super.key});

  @override
  State<DefinirNovaSenhaPage> createState() => _DefinirNovaSenhaPageState();
}

class _DefinirNovaSenhaPageState extends State<DefinirNovaSenhaPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _senhaController = TextEditingController();
  final TextEditingController _confirmarSenhaController =
      TextEditingController();

  bool _obscureSenha = true;
  bool _obscureConfirmar = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _senhaController.dispose();
    _confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _senhaController.text),
      );
      if (!mounted) return;
      // Não navega explicitamente: encerrar o estado de recuperação já
      // dispara o refreshListenable do AppRouter, que reavalia o redirect
      // sozinho e manda o usuário pra onde a sessão normal já mandaria
      // (profile-selection ou home) — mesmo padrão de
      // UiProfileSwitcher.switchProfile.
      authRecoveryController.concluir();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = i18n.tr('auth.definir_nova_senha_error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: getDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(title: Text(i18n.tr('auth.definir_nova_senha_title'))),
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
                    Text(
                      i18n.tr('auth.definir_nova_senha_subtitle'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _senhaController,
                      obscureText: _obscureSenha,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: i18n.tr('auth.password_label'),
                        helperText: i18n.tr('auth.password_hint'),
                        helperMaxLines: 2,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureSenha
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscureSenha = !_obscureSenha),
                        ),
                      ),
                      validator: PasswordPolicy.validate,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmarSenhaController,
                      obscureText: _obscureConfirmar,
                      decoration: InputDecoration(
                        labelText: i18n.tr('auth.confirm_password_label'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmar
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                            () => _obscureConfirmar = !_obscureConfirmar,
                          ),
                        ),
                      ),
                      validator: (value) => value != _senhaController.text
                          ? i18n.tr('auth.confirm_password_mismatch')
                          : null,
                      onFieldSubmitted: (_) => _confirmar(),
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
                      onPressed: _isSubmitting ? null : _confirmar,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(i18n.tr('auth.definir_nova_senha_button')),
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
