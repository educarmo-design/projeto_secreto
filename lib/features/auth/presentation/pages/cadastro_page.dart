import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/security/password_policy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/cep_model.dart';
import '../controllers/cadastro_controller.dart';
import '../widgets/social_auth_buttons.dart';
import 'verificacao_otp_page.dart';

/// Cadastro (sign-up) form: nickname + address, split between a Brazilian
/// flow (CEP autocomplete via ViaCEP) and an international flow (fully
/// manual país/estado/cidade) driven by [CadastroController]'s
/// [PaisSelecionado].
///
/// Segurança bancária: nem o botão "Cadastrar" nem os botões sociais
/// (Google/Apple) gravam em `perfis_usuarios` diretamente.
///
/// - E-mail/senha: dispara [CadastroController.cadastrarComEmailESenha]
///   (envia o token OTP de 6 dígitos) e empurra [VerificacaoOtpPage] — o
///   resto do formulário viaja com ela como [CadastroPerfilPendente] e só é
///   persistido depois que o e-mail é confirmado no servidor.
/// - Google/Apple: o e-mail já vem confirmado pelo provedor, então
///   [CadastroController.autenticarComProvedorSocial] substitui a etapa de
///   OTP — mas a tela ainda troca para um formulário reduzido (apelido +
///   país/CEP) antes de liberar [CadastroController.finalizarCadastroSocial],
///   já que "Ligas Geográficas" dependem de uma localização que o provedor
///   social não fornece.
///
/// Em ambos os caminhos, [onSubmit] só é chamado no fim de tudo — nunca
/// antes de e-mail confirmado + localização capturada.
class CadastroPage extends StatefulWidget {
  const CadastroPage({super.key, this.onSubmit});

  final ValueChanged<Map<String, dynamic>>? onSubmit;

  @override
  State<CadastroPage> createState() => _CadastroPageState();
}

class _CadastroPageState extends State<CadastroPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final CadastroController _controller = CadastroController();

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _cepController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _neighborhoodController =
      TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();

  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _localeDetected = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// `true` depois que um provedor social confirmou a identidade — troca o
  /// formulário completo por só apelido + localização.
  bool _socialAuthConcluido = false;
  OAuthProvider? _socialProviderLoading;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCadastroStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_localeDetected) {
      _localeDetected = true;
      _controller.detectPaisFromLocale(
        Localizations.localeOf(context).countryCode,
      );
    }
  }

  void _onCadastroStateChanged() {
    final cepModel = _controller.value.cepModel;
    if (_controller.value.isBrasil &&
        _controller.value.isSuccess &&
        cepModel != null) {
      _streetController.text = cepModel.logradouro;
      _neighborhoodController.text = cepModel.bairro;
      _cityController.text = cepModel.localidade;
      _stateController.text = cepModel.uf;
    }
    setState(() {});
  }

  void _onPaisChanged(PaisSelecionado pais) {
    if (_controller.value.pais == pais) return;
    _controller.setPais(pais);
    _cepController.clear();
    _streetController.clear();
    _neighborhoodController.clear();
    _cityController.clear();
    _stateController.clear();
    if (pais == PaisSelecionado.br) {
      _countryController.clear();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onCadastroStateChanged);
    _controller.dispose();
    _nicknameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _countryController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  ({String pais, String cep, String logradouro, String bairro, String cidade,
      String uf, String geoRankingId}) _lerCamposDeEndereco() {
    final CadastroCepState state = _controller.value;
    final geoRankingId = state.isBrasil
        ? (state.cepModel?.geoRankingId ?? '')
        : GeoRankingId.build(
            pais: _countryController.text,
            estadoOuProvincia: _stateController.text,
            cidade: _cityController.text,
          );

    return (
      pais: state.isBrasil
          ? i18n.tr('auth.country_brazil')
          : _countryController.text.trim(),
      cep: _cepController.text.trim(),
      logradouro: _streetController.text.trim(),
      bairro: _neighborhoodController.text.trim(),
      cidade: _cityController.text.trim(),
      uf: _stateController.text.trim(),
      geoRankingId: geoRankingId,
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    final endereco = _lerCamposDeEndereco();
    final nickname = _nicknameController.text.trim();
    final nomeCompleto = _fullNameController.text.trim();
    final telefone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final senha = _passwordController.text;

    setState(() => _isSubmitting = true);
    final result = await _controller.cadastrarComEmailESenha(
      email: email,
      senha: senha,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? i18n.tr('common.error'))),
      );
      return;
    }

    final perfilPendente = CadastroPerfilPendente(
      nickname: nickname,
      nomeCompleto: nomeCompleto,
      telefone: telefone,
      pais: endereco.pais,
      cep: endereco.cep,
      logradouro: endereco.logradouro,
      bairro: endereco.bairro,
      cidade: endereco.cidade,
      uf: endereco.uf,
      geoRankingId: endereco.geoRankingId,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerificacaoOtpPage(
          email: email,
          perfilPendente: perfilPendente,
          controller: _controller,
          onVerificado: () {
            widget.onSubmit?.call(<String, dynamic>{
              'nickname': nickname,
              'email': email,
              'pais': endereco.pais,
              'cep': endereco.cep,
              'logradouro': endereco.logradouro,
              'bairro': endereco.bairro,
              'cidade': endereco.cidade,
              'uf': endereco.uf,
              'geo_ranking_id': endereco.geoRankingId,
            });
          },
        ),
      ),
    );
  }

  Future<void> _handleSocialAuth(OAuthProvider provider) async {
    if (_socialProviderLoading != null) return;

    setState(() => _socialProviderLoading = provider);
    final result = await _controller.autenticarComProvedorSocial(
      provider: provider,
    );
    if (!mounted) return;
    setState(() => _socialProviderLoading = null);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? i18n.tr('common.error'))),
      );
      return;
    }

    // Regra de Fluxo: identidade confirmada pelo provedor social, mas ainda
    // falta a Liga Geográfica (CEP/Postal Code) — troca para o formulário
    // reduzido em vez de liberar a Tela Principal agora.
    setState(() => _socialAuthConcluido = true);
  }

  Future<void> _submitSocial() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    final endereco = _lerCamposDeEndereco();
    final nickname = _nicknameController.text.trim();

    setState(() => _isSubmitting = true);
    final result = await _controller.finalizarCadastroSocial(
      nickname: nickname,
      pais: endereco.pais,
      cep: endereco.cep,
      logradouro: endereco.logradouro,
      bairro: endereco.bairro,
      cidade: endereco.cidade,
      uf: endereco.uf,
      geoRankingId: endereco.geoRankingId,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? i18n.tr('common.error'))),
      );
      return;
    }

    widget.onSubmit?.call(<String, dynamic>{
      'nickname': nickname,
      'pais': endereco.pais,
      'cep': endereco.cep,
      'logradouro': endereco.logradouro,
      'bairro': endereco.bairro,
      'cidade': endereco.cidade,
      'uf': endereco.uf,
      'geo_ranking_id': endereco.geoRankingId,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('auth.register_title'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: _socialAuthConcluido
                ? _buildSocialCompletionFields(context)
                : _buildFullFormFields(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFullFormFields(BuildContext context) {
    final CadastroCepState state = _controller.value;
    final bool isBrasil = state.isBrasil;
    final bool isAddressAutoFilled = isBrasil && state.isSuccess;

    return [
      Text(
        i18n.tr('auth.login_subtitle'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      _buildNicknameField(),
      const SizedBox(height: 16),
      TextFormField(
        controller: _fullNameController,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: i18n.tr('auth.full_name_label'),
          prefixIcon: const Icon(Icons.badge_outlined),
        ),
        validator: (value) => (value == null || value.trim().isEmpty)
            ? i18n.tr('auth.full_name_required')
            : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9()+\-\s]')),
        ],
        decoration: InputDecoration(
          labelText: i18n.tr('auth.phone_label'),
          prefixIcon: const Icon(Icons.phone_outlined),
        ),
        validator: (value) {
          final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
          return digits.length < 8 ? i18n.tr('auth.phone_required') : null;
        },
      ),
      const SizedBox(height: 16),
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
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        autofillHints: const [AutofillHints.newPassword],
        decoration: InputDecoration(
          labelText: i18n.tr('auth.password_label'),
          helperText: i18n.tr('auth.password_hint'),
          helperMaxLines: 2,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        validator: PasswordPolicy.validate,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _confirmPasswordController,
        obscureText: _obscureConfirmPassword,
        decoration: InputDecoration(
          labelText: i18n.tr('auth.confirm_password_label'),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscureConfirmPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword,
            ),
          ),
        ),
        validator: (value) => value != _passwordController.text
            ? i18n.tr('auth.confirm_password_mismatch')
            : null,
      ),
      const SizedBox(height: 16),
      ..._buildAddressFields(state, isBrasil, isAddressAutoFilled),
      const SizedBox(height: 32),
      FilledButton(
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(i18n.tr('auth.register_button')),
      ),
      const SizedBox(height: 24),
      SocialAuthButtons(
        dividerLabelKey: 'auth.register_social_divider',
        googleLabelKey: 'auth.register_with_google',
        appleLabelKey: 'auth.register_with_apple',
        loadingProvider: _socialProviderLoading,
        onProviderSelected: _handleSocialAuth,
      ),
    ];
  }

  List<Widget> _buildSocialCompletionFields(BuildContext context) {
    final CadastroCepState state = _controller.value;
    final bool isBrasil = state.isBrasil;
    final bool isAddressAutoFilled = isBrasil && state.isSuccess;

    return [
      Icon(Icons.location_on_outlined, size: 48, color: AppColors.primaryGold),
      const SizedBox(height: 16),
      Text(
        i18n.tr('auth.social_complete_title'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        i18n.tr('auth.social_complete_subtitle'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 24),
      _buildNicknameField(),
      const SizedBox(height: 16),
      ..._buildAddressFields(state, isBrasil, isAddressAutoFilled),
      const SizedBox(height: 32),
      FilledButton(
        onPressed: _isSubmitting ? null : _submitSocial,
        child: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(i18n.tr('common.next')),
      ),
    ];
  }

  Widget _buildNicknameField() {
    return TextFormField(
      controller: _nicknameController,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: i18n.tr('auth.nickname_label'),
        hintText: i18n.tr('auth.nickname_hint'),
        prefixIcon: const Icon(Icons.emoji_events_outlined),
      ),
      validator: (value) => (value == null || value.trim().isEmpty)
          ? i18n.tr('auth.nickname_required')
          : null,
    );
  }

  /// País/CEP/endereço — compartilhado pelo formulário completo (e-mail) e
  /// pelo formulário reduzido (pós-login social), já que ambos precisam da
  /// mesma Liga Geográfica anônima ao final.
  List<Widget> _buildAddressFields(
    CadastroCepState state,
    bool isBrasil,
    bool isAddressAutoFilled,
  ) {
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<PaisSelecionado>(
          segments: [
            ButtonSegment(
              value: PaisSelecionado.br,
              label: Text(i18n.tr('auth.country_brazil')),
              icon: const Icon(Icons.flag_outlined),
            ),
            ButtonSegment(
              value: PaisSelecionado.internacional,
              label: Text(i18n.tr('auth.country_other')),
              icon: const Icon(Icons.public),
            ),
          ],
          selected: {state.pais},
          onSelectionChanged: (selection) => _onPaisChanged(selection.first),
        ),
      ),
      if (!isBrasil) ...[
        const SizedBox(height: 16),
        TextFormField(
          controller: _countryController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: i18n.tr('auth.country_label'),
            prefixIcon: const Icon(Icons.public),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? i18n.tr('auth.country_required')
              : null,
        ),
      ],
      const SizedBox(height: 16),
      TextFormField(
        controller: _cepController,
        keyboardType: isBrasil ? TextInputType.number : TextInputType.text,
        inputFormatters: isBrasil
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ]
            : [
                FilteringTextInputFormatter.allow(
                  RegExp(r'[A-Za-z0-9\-\s]'),
                ),
                LengthLimitingTextInputFormatter(12),
              ],
        decoration: InputDecoration(
          labelText: i18n.tr(
            isBrasil ? 'auth.cep_label' : 'auth.postal_code_label',
          ),
          hintText: isBrasil ? i18n.tr('auth.cep_hint') : null,
          counterText: '',
          prefixIcon: const Icon(Icons.location_on_outlined),
          suffixIcon: isBrasil ? _buildCepSuffix(state) : null,
          errorText: (isBrasil && state.isError) ? state.errorMessage : null,
        ),
        onChanged: _controller.onCepChanged,
        validator: (value) {
          if (isBrasil) {
            final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
            return digits.length != 8 ? i18n.tr('auth.cep_required') : null;
          }
          return (value == null || value.trim().isEmpty)
              ? i18n.tr('auth.cep_required')
              : null;
        },
      ),
      if (isAddressAutoFilled) ...[
        const SizedBox(height: 8),
        Text(
          i18n.tr('auth.address_auto_filled'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.success),
        ),
      ],
      const SizedBox(height: 16),
      TextFormField(
        controller: _streetController,
        decoration: InputDecoration(labelText: i18n.tr('auth.street_label')),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _neighborhoodController,
        decoration:
            InputDecoration(labelText: i18n.tr('auth.neighborhood_label')),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _cityController,
        readOnly: isBrasil,
        decoration: InputDecoration(
          labelText: i18n.tr('auth.city_label'),
          filled: isAddressAutoFilled,
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _stateController,
        readOnly: isBrasil,
        decoration: InputDecoration(
          labelText: i18n.tr('auth.state_label'),
          filled: isAddressAutoFilled,
        ),
      ),
    ];
  }

  Widget? _buildCepSuffix(CadastroCepState state) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (state.isSuccess) {
      return const Icon(Icons.check_circle, color: AppColors.success);
    }
    return null;
  }
}
