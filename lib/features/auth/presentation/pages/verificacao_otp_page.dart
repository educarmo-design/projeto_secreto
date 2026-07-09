import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/cadastro_controller.dart';

/// Tela de verificação do token OTP de 6 dígitos enviado por e-mail ao
/// final de [CadastroController.cadastrarComEmailESenha] — PRD Mestre,
/// segurança bancária: nenhum usuário alcança o Dashboard sem essa
/// confirmação, porque é só aqui, em [CadastroController.verificarTokenOTP],
/// que a sessão é aberta e `perfis_usuarios` recebe a escrita.
///
/// [controller] é injetado (não criado aqui) para que a mesma instância
/// usada por [CadastroPage] — e seu `http.Client` — sobreviva à navegação
/// até esta tela.
class VerificacaoOtpPage extends StatefulWidget {
  const VerificacaoOtpPage({
    super.key,
    required this.email,
    required this.perfilPendente,
    required this.controller,
    this.onVerificado,
  });

  final String email;
  final CadastroPerfilPendente perfilPendente;
  final CadastroController controller;

  /// Chamado após [CadastroController.verificarTokenOTP] confirmar o
  /// e-mail e persistir o perfil com sucesso — tipicamente navega para o
  /// Dashboard.
  final VoidCallback? onVerificado;

  @override
  State<VerificacaoOtpPage> createState() => _VerificacaoOtpPageState();
}

class _VerificacaoOtpPageState extends State<VerificacaoOtpPage> {
  static const int _quantidadeDigitos = 6;
  static const int _cooldownReenvioSegundos = 60;

  final List<TextEditingController> _digitControllers = List.generate(
    _quantidadeDigitos,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    _quantidadeDigitos,
    (_) => FocusNode(),
  );

  Timer? _cooldownTimer;
  int _segundosRestantes = _cooldownReenvioSegundos;

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _iniciarCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final controller in _digitControllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _iniciarCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _segundosRestantes = _cooldownReenvioSegundos);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_segundosRestantes <= 1) {
        timer.cancel();
        setState(() => _segundosRestantes = 0);
        return;
      }
      setState(() => _segundosRestantes -= 1);
    });
  }

  String get _tokenDigitado =>
      _digitControllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      // Um único TextField pode receber colar de múltiplos caracteres (ex.:
      // o teclado sugerindo o código inteiro do SMS/e-mail) — usa só o
      // último dígito neste quadrado e não tenta espalhar o resto.
      final digit = value.characters.last;
      _digitControllers[index].text = digit;
      _digitControllers[index].selection = const TextSelection.collapsed(
        offset: 1,
      );
      if (index < _quantidadeDigitos - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    } else if (index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (_errorMessage != null) setState(() => _errorMessage = null);

    if (_tokenDigitado.length == _quantidadeDigitos) {
      _verificar();
    }
  }

  Future<void> _verificar() async {
    final token = _tokenDigitado;
    if (token.length != _quantidadeDigitos || _isVerifying) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final result = await widget.controller.verificarTokenOTP(
      email: widget.email,
      token: token,
      perfil: widget.perfilPendente,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isVerifying = false;
        _errorMessage = _mapearErro(result.errorMessage);
      });
      _limparCamposEFocarPrimeiro();
      return;
    }

    setState(() => _isVerifying = false);
    widget.onVerificado?.call();
  }

  Future<void> _reenviar() async {
    if (_segundosRestantes > 0 || _isResending) return;

    setState(() => _isResending = true);
    final result = await widget.controller.reenviarTokenOTP(
      email: widget.email,
    );
    if (!mounted) return;
    setState(() => _isResending = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? i18n.tr('common.error'))),
      );
      return;
    }

    _limparCamposEFocarPrimeiro();
    _iniciarCooldown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(i18n.tr('auth.otp_resend_success'))),
    );
  }

  void _limparCamposEFocarPrimeiro() {
    for (final controller in _digitControllers) {
      controller.clear();
    }
    _focusNodes.first.requestFocus();
  }

  /// Traduz a mensagem de erro do GoTrue num rótulo i18n estável — o texto
  /// bruto do servidor não é chave de tradução e não deve ser mostrado como
  /// se fosse um texto já localizado.
  String _mapearErro(String? mensagemServidor) {
    final mensagem = (mensagemServidor ?? '').toLowerCase();
    if (mensagem.contains('expired') || mensagem.contains('expirad')) {
      return i18n.tr('auth.otp_expired');
    }
    return i18n.tr('auth.otp_invalid');
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: getDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(title: Text(i18n.tr('auth.otp_title'))),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 56,
                    color: AppColors.primaryGold,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    i18n.tr(
                      'auth.otp_subtitle',
                      params: {'email': widget.email},
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < _quantidadeDigitos; i++)
                        _OtpDigitBox(
                          controller: _digitControllers[i],
                          focusNode: _focusNodes[i],
                          onChanged: (value) => _onDigitChanged(i, value),
                          hasError: _errorMessage != null,
                        ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (_isVerifying)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton(
                      onPressed: _tokenDigitado.length == _quantidadeDigitos
                          ? _verificar
                          : null,
                      child: Text(i18n.tr('auth.otp_verify_button')),
                    ),
                  const SizedBox(height: 24),
                  _isResending
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _segundosRestantes == 0 ? _reenviar : null,
                          child: Text(
                            _segundosRestantes == 0
                                ? i18n.tr('auth.otp_resend_button')
                                : i18n.tr(
                                    'auth.otp_resend_countdown',
                                    params: {
                                      'seconds': _segundosRestantes.toString(),
                                    },
                                  ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Um dos 6 quadrados individuais do PIN — dígito único, avança/retrocede o
/// foco automaticamente via [VerificacaoOtpPage._onDigitChanged].
class _OtpDigitBox extends StatelessWidget {
  const _OtpDigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.hasError,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: Theme.of(context).textTheme.headlineSmall,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: hasError ? AppColors.error : AppColors.mutedText,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: hasError ? AppColors.error : AppColors.primaryGold,
              width: 2,
            ),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
