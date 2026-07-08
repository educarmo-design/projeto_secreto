import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/cep_model.dart';
import '../controllers/cadastro_controller.dart';

/// Cadastro (sign-up) form: nickname + address, split between a Brazilian
/// flow (CEP autocomplete via ViaCEP) and an international flow (fully
/// manual país/estado/cidade) driven by [CadastroController]'s
/// [PaisSelecionado].
///
/// Submission itself is delegated to [CadastroController.enviarParaNuvem],
/// which persists the cadastro to `perfis_usuarios` in Supabase. [onSubmit]
/// is an optional hook called with the validated, LGPD-conscious payload
/// (nickname, street/neighborhood as free text, plus a `geo_ranking_id`
/// bucket built from país+estado+cidade instead of the raw CEP/postal code)
/// after a successful cloud write — e.g. for navigation.
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
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _cepController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _neighborhoodController =
      TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();

  bool _localeDetected = false;
  bool _isSubmitting = false;

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
    _countryController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isSubmitting) return;

    final CadastroCepState state = _controller.value;
    final String geoRankingId = state.isBrasil
        ? (state.cepModel?.geoRankingId ?? '')
        : GeoRankingId.build(
            pais: _countryController.text,
            estadoOuProvincia: _stateController.text,
            cidade: _cityController.text,
          );

    final nickname = _nicknameController.text.trim();
    final pais = state.isBrasil
        ? i18n.tr('auth.country_brazil')
        : _countryController.text.trim();
    final cep = _cepController.text.trim();
    final logradouro = _streetController.text.trim();
    final bairro = _neighborhoodController.text.trim();
    final cidade = _cityController.text.trim();
    final uf = _stateController.text.trim();

    setState(() => _isSubmitting = true);
    final result = await _controller.enviarParaNuvem(
      nickname: nickname,
      pais: pais,
      cep: cep,
      logradouro: logradouro,
      bairro: bairro,
      cidade: cidade,
      uf: uf,
      geoRankingId: geoRankingId,
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
      'pais': pais,
      'cep': cep,
      'logradouro': logradouro,
      'bairro': bairro,
      'cidade': cidade,
      'uf': uf,
      'geo_ranking_id': geoRankingId,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(i18n.tr('common.success'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CadastroCepState state = _controller.value;
    final bool isBrasil = state.isBrasil;
    final bool isAddressAutoFilled = isBrasil && state.isSuccess;

    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('auth.register_title'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                i18n.tr('auth.login_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextFormField(
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
              ),
              const SizedBox(height: 16),
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
                  onSelectionChanged: (selection) =>
                      _onPaisChanged(selection.first),
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
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? i18n.tr('auth.country_required')
                          : null,
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _cepController,
                keyboardType:
                    isBrasil ? TextInputType.number : TextInputType.text,
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
                  errorText:
                      (isBrasil && state.isError) ? state.errorMessage : null,
                ),
                onChanged: _controller.onCepChanged,
                validator: (value) {
                  if (isBrasil) {
                    final digits = (value ?? '').replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    );
                    return digits.length != 8
                        ? i18n.tr('auth.cep_required')
                        : null;
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
                decoration: InputDecoration(
                  labelText: i18n.tr('auth.street_label'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _neighborhoodController,
                decoration: InputDecoration(
                  labelText: i18n.tr('auth.neighborhood_label'),
                ),
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
            ],
          ),
        ),
      ),
    );
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
