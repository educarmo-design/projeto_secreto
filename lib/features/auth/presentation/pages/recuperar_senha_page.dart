import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';

/// "Esqueci minha senha" — pede o e-mail e dispara
/// `client.auth.resetPasswordForEmail`. Cru de propósito (Adendo v5.1 §B):
/// um campo, um botão, sem nenhum acabamento visual além do tema já
/// compartilhado com [LoginPage]/[CadastroPage].
///
/// Anti-enumeração de contas: a mensagem de sucesso é a MESMA independente
/// de o e-mail existir ou não na base — `resetPasswordForEmail` do Supabase
/// já não diferencia isso na resposta (não lança para "e-mail não
/// encontrado"), e esta tela reforça o mesmo princípio na cópia exibida.
///
/// Fora do escopo desta tela: a tela de "definir nova senha" que abriria a
/// partir do link recebido por e-mail (precisaria de tratamento de deep
/// link, ainda não configurado nas pastas nativas) — ver RELATÓRIO DE FIM
/// DE TAREFA.
class RecuperarSenhaPage extends StatefulWidget {
  const RecuperarSenhaPage({super.key});

  @override
  State<RecuperarSenhaPage> createState() => _RecuperarSenhaPageState();
}

class _RecuperarSenhaPageState extends State<RecuperarSenhaPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _isSubmitting = false;
  bool _emailEnviado = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: AppConfig.oauthRedirectUrl,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _emailEnviado = true;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(i18n.tr('auth.recuperar_senha_error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: getDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(title: Text(i18n.tr('auth.recuperar_senha_title'))),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _emailEnviado ? _buildSucesso(context) : _buildForm(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            i18n.tr('auth.recuperar_senha_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: i18n.tr('auth.email_label'),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              return _emailRegex.hasMatch(trimmed)
                  ? null
                  : i18n.tr('auth.email_invalid');
            },
            onFieldSubmitted: (_) => _enviar(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting ? null : _enviar,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(i18n.tr('auth.recuperar_senha_button')),
          ),
        ],
      ),
    );
  }

  Widget _buildSucesso(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 56, color: AppColors.primaryGold),
        const SizedBox(height: 16),
        Text(
          i18n.tr('auth.recuperar_senha_sucesso'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.tr('auth.recuperar_senha_voltar_button')),
        ),
      ],
    );
  }
}
