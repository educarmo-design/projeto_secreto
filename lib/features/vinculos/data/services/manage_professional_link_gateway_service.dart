import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';

/// Ação pedida a `manage-professional-link` do lado do paciente. A função
/// também tem `criar_vinculo` (chamada pelo profissional, no painel web —
/// fora do escopo deste app), por isso só as duas ações do paciente entram
/// aqui.
enum AcaoVinculoPaciente { aceitar, recusar }

extension on AcaoVinculoPaciente {
  /// "Recusar" não é uma ação própria da Edge Function — é `encerrar_vinculo`
  /// aplicado a um vínculo ainda `pendente` (ver
  /// supabase/functions/manage-professional-link/index.ts, `encerrarVinculo`:
  /// qualquer uma das partes pode encerrar, qualquer status exceto já
  /// encerrado). O mesmo endpoint que revoga um vínculo ativo serve para
  /// recusar um convite — o app nunca escreve na tabela diretamente, só
  /// escolhe a ação.
  String get valorServidor {
    switch (this) {
      case AcaoVinculoPaciente.aceitar:
        return 'aceitar_vinculo';
      case AcaoVinculoPaciente.recusar:
        return 'encerrar_vinculo';
    }
  }
}

class ManageProfessionalLinkResult {
  final bool success;
  final String? errorMessage;

  const ManageProfessionalLinkResult({required this.success, this.errorMessage});
}

/// Gateway de `manage-professional-link` do lado do paciente — Etapa de UI
/// de Consentimento (Adendo v4, F.3). Mesmo padrão de
/// [EsteiraTrialGatewayService]: o cliente só envia a intenção
/// (`acao` + `vinculo_id`); quem decide se o pedido é válido — é o paciente
/// dono do vínculo, o status permite a transição — é o servidor, com a
/// service role que `vinculos_profissional_paciente` nunca concede ao
/// `authenticated` (20260713100000/20260713140000).
class ManageProfessionalLinkGatewayService {
  ManageProfessionalLinkGatewayService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<ManageProfessionalLinkResult> executar({
    required AcaoVinculoPaciente acao,
    required String vinculoId,
    required Map<String, String> authHeaders,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.manageProfessionalLinkEndpoint),
            headers: {
              ...authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'acao': acao.valorServidor,
              'vinculo_id': vinculoId,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return ManageProfessionalLinkResult(
          success: false,
          errorMessage: _mensagemDeErro(response),
        );
      }
      return const ManageProfessionalLinkResult(success: true);
    } on TimeoutException {
      return const ManageProfessionalLinkResult(
        success: false,
        errorMessage: 'Tempo esgotado ao falar com o servidor.',
      );
    } on http.ClientException {
      return const ManageProfessionalLinkResult(
        success: false,
        errorMessage: 'Erro de conexão.',
      );
    } on FormatException {
      return const ManageProfessionalLinkResult(
        success: false,
        errorMessage: 'Resposta inválida do servidor.',
      );
    }
  }

  String _mensagemDeErro(http.Response response) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final erro = decoded['error'] as String?;
      if (erro != null && erro.isNotEmpty) return erro;
    } catch (_) {
      // Corpo não é JSON — cai no fallback genérico abaixo.
    }
    return 'Não foi possível processar o vínculo agora (HTTP ${response.statusCode}).';
  }
}
