import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/cep_model.dart';

enum CadastroCepStatus { idle, loading, success, error }

/// Which address flow the cadastro form is running. ViaCEP is a Brazilian
/// government-backed free API — it has no concept of, and must never be
/// called for, an address outside Brazil.
enum PaisSelecionado { br, internacional }

@immutable
class CadastroCepState {
  final CadastroCepStatus status;
  final CepModel? cepModel;
  final String? errorMessage;
  final PaisSelecionado pais;

  const CadastroCepState({
    this.status = CadastroCepStatus.idle,
    this.cepModel,
    this.errorMessage,
    this.pais = PaisSelecionado.br,
  });

  bool get isLoading => status == CadastroCepStatus.loading;
  bool get isSuccess => status == CadastroCepStatus.success;
  bool get isError => status == CadastroCepStatus.error;
  bool get isBrasil => pais == PaisSelecionado.br;
}

/// Drives the CEP-driven address autocomplete for the cadastro form, plus
/// the BR/international split that decides whether ViaCEP may be called.
///
/// Zero-cost by design: uses `http` directly against ViaCEP (a free public
/// API) instead of a paid geocoding provider, and `ValueNotifier` instead of
/// pulling in a state-management package for a single-screen concern.
class CadastroController extends ValueNotifier<CadastroCepState> {
  CadastroController({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        super(const CadastroCepState());

  final http.Client _httpClient;

  /// Guards [detectPaisFromLocale] so a later locale-dependency rebuild
  /// (e.g. system language change) can't silently overwrite a país the
  /// user already picked by hand via [setPais].
  bool _paisAutoDetectado = false;

  static final RegExp _nonDigits = RegExp(r'[^0-9]');
  static const int _cepLength = 8;
  static const Duration _requestTimeout = Duration(seconds: 10);

  /// Auto-detects the initial país from the device/app locale — pass
  /// `Localizations.localeOf(context).countryCode` from the widget's
  /// `didChangeDependencies`. Only takes effect once; call [setPais]
  /// afterwards for any explicit user override (e.g. a Brasil/Outros
  /// selector), which always wins from that point on.
  void detectPaisFromLocale(String? countryCode) {
    if (_paisAutoDetectado) return;
    _paisAutoDetectado = true;
    if (countryCode != null && countryCode.toUpperCase() != 'BR') {
      setPais(PaisSelecionado.internacional);
    }
  }

  /// Explicit país selection (e.g. from a Brasil/Outros toggle). Resets any
  /// CEP-lookup state, since a result fetched for one país is meaningless
  /// once the flow switches to the other.
  void setPais(PaisSelecionado pais) {
    _paisAutoDetectado = true;
    if (value.pais == pais) return;
    value = CadastroCepState(pais: pais);
  }

  /// Call on every change to the CEP/postal-code field. For Brazil, fires
  /// the ViaCEP lookup once exactly 8 digits are present. For every other
  /// país this is a no-op: international postal codes are never sent to
  /// ViaCEP, and the address fields stay fully manual on the UI side.
  Future<void> onCepChanged(String rawInput) async {
    if (!value.isBrasil) return;

    final digits = rawInput.replaceAll(_nonDigits, '');
    if (digits.length != _cepLength) {
      if (value.status != CadastroCepStatus.idle) {
        value = CadastroCepState(pais: value.pais);
      }
      return;
    }
    await lookupCep(digits);
  }

  /// ViaCEP is a Brazil-only free API. This refuses outright for any other
  /// país rather than relying on callers to remember the check — so even a
  /// direct/future call site can't accidentally leak an international
  /// postal code to a Brazilian government API.
  Future<void> lookupCep(String cep) async {
    if (!value.isBrasil) {
      assert(
        false,
        'lookupCep() foi chamado com paisSelecionado != br. ViaCEP é uma '
        'API exclusiva do Brasil e nunca deve ser chamada para outros países.',
      );
      return;
    }

    value = CadastroCepState(
      pais: value.pais,
      status: CadastroCepStatus.loading,
    );

    try {
      final response = await _httpClient
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        _setError();
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (CepModel.isErrorResponse(decoded)) {
        _setError();
        return;
      }

      value = CadastroCepState(
        pais: value.pais,
        status: CadastroCepStatus.success,
        cepModel: CepModel.fromJson(decoded),
      );
    } on TimeoutException {
      _setError();
    } on http.ClientException {
      _setError();
    } on FormatException {
      _setError();
    }
  }

  void _setError() {
    value = CadastroCepState(
      pais: value.pais,
      status: CadastroCepStatus.error,
      errorMessage: i18n.tr('auth.cep_invalid'),
    );
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
