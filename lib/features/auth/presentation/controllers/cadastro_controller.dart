import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/security/crypto_storage_service.dart';
import '../../../../core/supabase/supabase_client.dart';
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

  /// Etapa 1/2 do cadastro bancário: dispara a criação da conta via
  /// `client.auth.signUp`. Com confirmação de e-mail habilitada no projeto
  /// Supabase (padrão), isto não abre uma sessão — apenas envia o e-mail
  /// com o token de 6 dígitos e devolve um `user` ainda não confirmado.
  /// Nenhum dado de perfil é gravado em `perfis_usuarios` aqui: essa tabela
  /// só aceita a escrita depois que [verificarTokenOTP] confirmar o e-mail e
  /// abrir uma sessão real que satisfaça `auth.uid() = id`.
  ///
  /// [metadadosPapel] é a ÚNICA exceção: vai direto no `data:` do `signUp`,
  /// virando `user_metadata` em `auth.users` imediatamente — mesmo antes da
  /// confirmação de e-mail (GoTrue aceita `data` em contas ainda não
  /// confirmadas). Ver [CadastroPerfilPendente.toUserMetadata] para o
  /// formato exato; é a combinação de papéis (perfil_uso + eh_profissional +
  /// especialidade/registro) que o Cadastro Dinâmico precisa estruturada em
  /// `user_metadata`, não um espelho de todo o formulário — nome/telefone
  /// seguem SÓ o caminho criptografado de `_persistirPerfil`, nunca em
  /// texto plano em `user_metadata` (que não tem o mesmo tratamento de
  /// cifragem client-side do resto do app).
  Future<CadastroSubmitResult> cadastrarComEmailESenha({
    required String email,
    required String senha,
    Map<String, dynamic>? metadadosPapel,
  }) async {
    try {
      await supabaseManager.client.auth.signUp(
        email: email,
        password: senha,
        data: metadadosPapel,
      );
      return const CadastroSubmitResult(success: true);
    } on AuthException catch (e) {
      return CadastroSubmitResult(success: false, errorMessage: e.message);
    }
  }

  /// Reenvia o e-mail de confirmação com um novo token de 6 dígitos —
  /// chamado pelo botão "Reenviar Código" da [VerificacaoOtpPage] depois do
  /// cooldown de 60s.
  Future<CadastroSubmitResult> reenviarTokenOTP({required String email}) async {
    try {
      await supabaseManager.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      return const CadastroSubmitResult(success: true);
    } on AuthException catch (e) {
      return CadastroSubmitResult(success: false, errorMessage: e.message);
    }
  }

  /// Etapa 2/2: valida o token de 6 dígitos recebido por e-mail contra o
  /// Supabase Auth. Só depois de `verifyOTP` confirmar o e-mail é que:
  ///
  /// 1. A sessão ativa é capturada e seu refresh token é criptografado e
  ///    salvo "de forma definitiva" no [CryptoStorageService]
  ///    (Keystore/Keychain) — exigindo biometria local em todo acesso
  ///    seguinte, nunca liberado em texto plano.
  /// 2. [perfil] (nickname/nome/telefone/endereço, coletados na tela de
  ///    cadastro mas retidos até aqui) é finalmente persistido em
  ///    `perfis_usuarios`, com nome/telefone AES-256-GCM criptografados
  ///    client-side — a mesma regra de blindagem de dados sensíveis do
  ///    restante do app.
  Future<CadastroSubmitResult> verificarTokenOTP({
    required String email,
    required String token,
    required CadastroPerfilPendente perfil,
  }) async {
    try {
      final authResponse = await supabaseManager.client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );

      final user = authResponse.user;
      if (user == null) {
        return CadastroSubmitResult(
          success: false,
          errorMessage: i18n.tr('auth.register_auth_failed'),
        );
      }

      final refreshToken = authResponse.session?.refreshToken;
      if (refreshToken != null && await cryptoStorage.isBiometricAvailable()) {
        await cryptoStorage.persistSessionToken(refreshToken);
      }

      await _persistirPerfil(userId: user.id, email: email, perfil: perfil);

      return const CadastroSubmitResult(success: true);
    } on AuthException catch (e) {
      return CadastroSubmitResult(success: false, errorMessage: e.message);
    } on PostgrestException catch (e) {
      return CadastroSubmitResult(success: false, errorMessage: e.message);
    }
  }

  static const Duration _oauthTimeout = Duration(minutes: 3);

  /// Login Unificado — dispara `signInWithOAuth` para [provider]
  /// (Google/Apple) e aguarda a sessão chegar via `onAuthStateChange`.
  ///
  /// `signInWithOAuth` só abre o navegador/webview e devolve se o
  /// navegador *abriu*, não se o login teve sucesso — a sessão real chega
  /// depois, de forma assíncrona, quando o provedor redireciona de volta
  /// para [AppConfig.oauthRedirectUrl] e o SO entrega esse deep link ao
  /// app. Por isso este método escuta `onAuthStateChange` por
  /// [AuthChangeEvent.signedIn] *antes* de lançar o navegador, com um
  /// timeout — nunca fica esperando para sempre se o usuário simplesmente
  /// fechar a aba do provedor sem concluir.
  ///
  /// Regra de Cibersegurança Bancária: assim que a sessão social chega, seu
  /// refresh token é criptografado e salvo no [CryptoStorageService]
  /// (Keystore/Keychain) exatamente como no login por senha — o que faz o
  /// botão "Entrar com Biometria" já existente em [LoginPage] cobrir contas
  /// Google/Apple automaticamente, sem nenhum código extra: acessos
  /// futuros a essa sessão exigem a mesma biometria local.
  Future<CadastroSubmitResult> autenticarComProvedorSocial({
    required OAuthProvider provider,
  }) async {
    try {
      final aguardarSessao = supabaseManager.client.auth.onAuthStateChange
          .firstWhere((event) => event.event == AuthChangeEvent.signedIn)
          .timeout(_oauthTimeout);

      final navegadorAbriu = await supabaseManager.client.auth.signInWithOAuth(
        provider,
        redirectTo: AppConfig.oauthRedirectUrl,
      );
      if (!navegadorAbriu) {
        return CadastroSubmitResult(
          success: false,
          errorMessage: i18n.tr('auth.oauth_launch_failed'),
        );
      }

      final event = await aguardarSessao;
      final refreshToken = event.session?.refreshToken;
      if (refreshToken == null) {
        return CadastroSubmitResult(
          success: false,
          errorMessage: i18n.tr('auth.oauth_failed'),
        );
      }

      if (await cryptoStorage.isBiometricAvailable()) {
        await cryptoStorage.persistSessionToken(refreshToken);
      }

      return const CadastroSubmitResult(success: true);
    } on TimeoutException {
      return CadastroSubmitResult(
        success: false,
        errorMessage: i18n.tr('auth.oauth_timeout'),
      );
    } on AuthException catch (e) {
      return CadastroSubmitResult(success: false, errorMessage: e.message);
    }
  }

  /// Conclui o cadastro depois de [autenticarComProvedorSocial]: o e-mail
  /// já veio confirmado pelo Google/Apple (não passa por OTP), então só
  /// falta o que o provedor social não tem — apelido e Liga Geográfica
  /// (CEP/Postal Code). [nomeCompleto] é lido com segurança de
  /// `user.userMetadata`, nunca assumido presente, já que seu formato é
  /// controlado pelo provedor externo, não pelo Supabase.
  ///
  /// Extrai o UUID a persistir estritamente de `currentUser!.id` — o
  /// identificador interno que o Supabase Auth gera para a sessão, nunca o
  /// e-mail ou qualquer id bruto do Google/Apple. É esse UUID, e só ele,
  /// que as tabelas clínicas (`metricas_saude_diarias` etc.) enxergam via
  /// RLS `auth.uid()`; a conta social original nunca é uma chave visível
  /// para dados de saúde.
  Future<CadastroSubmitResult> finalizarCadastroSocial({
    required String nickname,
    required String pais,
    required String cep,
    required String logradouro,
    required String bairro,
    required String cidade,
    required String uf,
    required String geoRankingId,
  }) async {
    final user = supabaseManager.currentUser;
    if (user == null) {
      return CadastroSubmitResult(
        success: false,
        errorMessage: i18n.tr('auth.register_auth_failed'),
      );
    }

    try {
      final metadata = user.userMetadata;
      final nomeSocial = (metadata?['full_name'] as String?) ??
          (metadata?['name'] as String?) ??
          '';

      await _persistirPerfil(
        userId: user.id,
        email: user.email ?? '',
        perfil: CadastroPerfilPendente(
          nickname: nickname,
          nomeCompleto: nomeSocial,
          pais: pais,
          cep: cep,
          logradouro: logradouro,
          bairro: bairro,
          cidade: cidade,
          uf: uf,
          geoRankingId: geoRankingId,
        ),
      );

      return const CadastroSubmitResult(success: true);
    } on PostgrestException catch (e) {
      return CadastroSubmitResult(success: false, errorMessage: e.message);
    }
  }

  /// Etapa 1 (LGPD art. 11 — dado sensível): `nome`/`telefone`/`email` saem
  /// daqui em TEXTO PLANO, protegidos em trânsito por TLS. A cifra EM REPOUSO
  /// é responsabilidade do banco agora (D2): um trigger `before insert/update`
  /// em `perfis_usuarios` cifra esses 3 campos com pgcrypto + chave no Vault
  /// (ver `*_d2_pii_criptografia_repouso.sql`) — o cliente não guarda mais
  /// nenhuma chave de PII. `perfis_usuarios.email` é só uma cópia de
  /// conveniência de `auth.users.email` (que o Supabase Auth já isola).
  Future<void> _persistirPerfil({
    required String userId,
    required String email,
    required CadastroPerfilPendente perfil,
  }) async {
    await supabaseManager.client.from('perfis_usuarios').upsert({
      'id': userId,
      'nickname': perfil.nickname,
      'nome': perfil.nomeCompleto,
      'telefone': perfil.telefone,
      'email': email,
      'pais': perfil.pais,
      'cep': perfil.cep,
      'logradouro': perfil.logradouro,
      'bairro': perfil.bairro,
      'cidade': perfil.cidade,
      'estado': perfil.uf,
      'geo_ranking_id': perfil.geoRankingId,
      if (perfil.idade != null) 'idade': perfil.idade,
      if (perfil.pesoKg != null) 'peso_kg': perfil.pesoKg,
      'eh_profissional': perfil.ehProfissional,
      if (perfil.tipoProfissional != null)
        'tipo_profissional': perfil.tipoProfissional,
      if (perfil.registroProfissional != null &&
          perfil.registroProfissional!.isNotEmpty)
        'registro_profissional': perfil.registroProfissional,
    }, onConflict: 'id');

    if (perfil.perfilUso != null) {
      await _persistirPerfilUsoInicial(userId, perfil.perfilUso!);
    }
  }

  /// Grava `perfil_uso` em `anonymous_users.profile_data` — o mesmo JSONB
  /// que [UiProfileSwitcher] lê para decidir o shell (Atleta competitivo x
  /// Guardião/Sênior) e que `AppRouter` usa para saber se o perfil já foi
  /// escolhido. Sem isto, um cadastro novo cairia num limbo de "perfil não
  /// configurado" mesmo já tendo respondido ao Radio Button da tela de
  /// cadastro — que é exatamente o comportamento que evita duplicar a
  /// escolha de perfil com [ProfileSelectionPage]: quando esta grava
  /// `perfil_uso` aqui, o redirect do roteador nunca chega a mandar o
  /// usuário para lá (só existe como fallback para quem cadastrou sem
  /// escolher, hoje só o caminho social reduzido). Diferente de
  /// `UiProfileSwitcher.switchProfile` (que faz merge preservando outras
  /// chaves), aqui não existe `profile_data` anterior — é a primeira
  /// escrita da conta, então `profile_data` nasce só com esta chave.
  Future<void> _persistirPerfilUsoInicial(String userId, String tag) async {
    await supabaseManager.client.from('anonymous_users').upsert(
      {
        'id': userId,
        'profile_data': {'perfil_uso': tag},
      },
      onConflict: 'id',
    );
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}

/// Outcome of [CadastroController.cadastrarComEmailESenha] /
/// [CadastroController.verificarTokenOTP] / [CadastroController.reenviarTokenOTP].
@immutable
class CadastroSubmitResult {
  final bool success;
  final String? errorMessage;

  const CadastroSubmitResult({required this.success, this.errorMessage});
}

/// Dados de perfil coletados na tela de cadastro mas cuja gravação em
/// `perfis_usuarios` fica retida até [CadastroController.verificarTokenOTP]
/// confirmar o e-mail — antes disso não existe sessão válida para
/// satisfazer a RLS `auth.uid() = id`, e gravar sob uma conta ainda não
/// confirmada abriria uma janela para perfis "fantasma" de e-mails que
/// nunca chegam a ser verificados.
///
/// [perfilUso]/[ehProfissional]/[tipoProfissional]/[registroProfissional]/
/// [idade]/[pesoKg] são os campos do Cadastro Dinâmico (Perfil Base +
/// Profissional de Saúde) — persistidos duas vezes, de propósito: aqui em
/// `perfis_usuarios` (o que o resto do app lê via RLS) via
/// [toUserMetadata] direto no `signUp` da Etapa 1 (o que fica em
/// `auth.users.user_metadata`, disponível mesmo antes da confirmação de
/// e-mail).
@immutable
class CadastroPerfilPendente {
  final String nickname;
  final String nomeCompleto;
  final String telefone;
  final String pais;
  final String cep;
  final String logradouro;
  final String bairro;
  final String cidade;
  final String uf;
  final String geoRankingId;

  /// Tag de `perfil_uso` já no formato que [UiProfileSwitcher] espera em
  /// `anonymous_users.profile_data` — `'Atleta'` ou `'Senior'`. `null`
  /// significa "não escolhido" (hoje só acontece no caminho social
  /// reduzido, que não passa pelo Radio Button do Perfil Base).
  final String? perfilUso;
  final bool ehProfissional;

  /// Valor exato do enum Postgres `tipo_profissional_saude` (`'Medico'`,
  /// `'Nutricionista'`, `'Fisioterapeuta'`, `'Personal_Trainer'`) — `null`
  /// quando [ehProfissional] é `false`.
  final String? tipoProfissional;
  final String? registroProfissional;
  final int? idade;
  final double? pesoKg;

  const CadastroPerfilPendente({
    required this.nickname,
    this.nomeCompleto = '',
    this.telefone = '',
    required this.pais,
    required this.cep,
    required this.logradouro,
    required this.bairro,
    required this.cidade,
    required this.uf,
    required this.geoRankingId,
    this.perfilUso,
    this.ehProfissional = false,
    this.tipoProfissional,
    this.registroProfissional,
    this.idade,
    this.pesoKg,
  });

  /// Estrutura enviada como `data:` para `client.auth.signUp` — vira
  /// `user_metadata`. Espelha 1:1 os campos que [CadastroController.
  /// _persistirPerfil] grava em `perfis_usuarios`/`anonymous_users`, exceto
  /// nome/telefone/endereço (esses só existem, cifrados, na tabela — nunca
  /// em texto plano em `user_metadata`).
  Map<String, dynamic> toUserMetadata() => {
        if (perfilUso != null) 'perfil_uso': perfilUso,
        'eh_profissional': ehProfissional,
        if (tipoProfissional != null) 'tipo_profissional': tipoProfissional,
        if (registroProfissional != null && registroProfissional!.isNotEmpty)
          'registro_profissional': registroProfissional,
        if (idade != null) 'idade': idade,
        if (pesoKg != null) 'peso_kg': pesoKg,
      };
}
