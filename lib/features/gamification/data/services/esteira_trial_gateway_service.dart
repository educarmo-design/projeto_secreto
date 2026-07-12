import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';

/// Ação solicitada a `calculate-recovery-mode` — espelha 1:1 os métodos
/// públicos que [EsteiraTrialController] expõe hoje, para que o contrato do
/// servidor não precise mudar quando a lógica real (hoje um stub) for
/// implementada numa sessão futura.
enum EsteiraTrialAcao {
  consultar,
  ativarRecuperacao,
  desativarRecuperacao,
  registrarMetaMovimento,
  registrarMissaoExame,
}

extension on EsteiraTrialAcao {
  String get valorServidor {
    switch (this) {
      case EsteiraTrialAcao.consultar:
        return 'consultar';
      case EsteiraTrialAcao.ativarRecuperacao:
        return 'ativar_recuperacao';
      case EsteiraTrialAcao.desativarRecuperacao:
        return 'desativar_recuperacao';
      case EsteiraTrialAcao.registrarMetaMovimento:
        return 'registrar_meta_movimento';
      case EsteiraTrialAcao.registrarMissaoExame:
        return 'registrar_missao_exame';
    }
  }
}

/// Estado da Esteira dos 14 Dias Free devolvido pelo servidor. Espelho de
/// `EsteiraTrialState` (sem o campo `carregando`, que é puramente de UI) —
/// ver [EsteiraTrialController].
@immutable
class EsteiraTrialGatewayState {
  final int diaAtual;
  final bool modoRecuperacaoAtivo;
  final bool metaMovimentoCumprida;
  final Set<int> missoesExamesConcluidas;

  const EsteiraTrialGatewayState({
    required this.diaAtual,
    required this.modoRecuperacaoAtivo,
    required this.metaMovimentoCumprida,
    required this.missoesExamesConcluidas,
  });

  factory EsteiraTrialGatewayState.fromJson(Map<String, dynamic> json) {
    return EsteiraTrialGatewayState(
      diaAtual: (json['diaAtual'] as num).toInt(),
      modoRecuperacaoAtivo: json['modoRecuperacaoAtivo'] as bool,
      metaMovimentoCumprida: json['metaMovimentoCumprida'] as bool,
      missoesExamesConcluidas: (json['missoesExamesConcluidas'] as List)
          .map((e) => (e as num).toInt())
          .toSet(),
    );
  }
}

@immutable
class EsteiraTrialGatewayResult {
  final bool success;
  final EsteiraTrialGatewayState? state;
  final String? errorMessage;

  const EsteiraTrialGatewayResult({
    required this.success,
    this.state,
    this.errorMessage,
  });
}

/// Gateway server-side da Esteira dos 14 Dias Free (Etapa 0.5 — F21).
///
/// Regra de arquitetura inegociável (PRD Mestre §0.5): toda regra de jogo
/// sensível (streaks, pontos, congelamento) é calculada no servidor, nunca
/// no cliente. Antes desta etapa, [EsteiraTrialController] calculava o dia
/// do trial e a janela de congelamento localmente a partir de datas
/// guardadas no `flutter_secure_storage` do próprio aparelho — manipulável
/// por qualquer um com acesso de depuração ao dispositivo. Este serviço
/// substitui esse cálculo por uma chamada à Edge Function
/// `calculate-recovery-mode`, mesmo padrão de [GeminiGatewayService]: o
/// cliente nunca decide o resultado, só envia a intenção (`acao`) e exibe o
/// que o servidor devolve.
class EsteiraTrialGatewayService {
  EsteiraTrialGatewayService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<EsteiraTrialGatewayResult> executar({
    required EsteiraTrialAcao acao,
    required DateTime dataCadastro,
    required Map<String, String> authHeaders,
    int? dia,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.calculateRecoveryModeEndpoint),
            headers: {
              ...authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'acao': acao.valorServidor,
              'dataCadastro': dataCadastro.toIso8601String(),
              if (dia != null) 'dia': dia,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return EsteiraTrialGatewayResult(
          success: false,
          errorMessage: _mensagemDeErro(response),
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return EsteiraTrialGatewayResult(
        success: true,
        state: EsteiraTrialGatewayState.fromJson(decoded),
      );
    } on TimeoutException {
      return const EsteiraTrialGatewayResult(
        success: false,
        errorMessage: 'Tempo esgotado ao falar com o servidor.',
      );
    } on http.ClientException {
      return const EsteiraTrialGatewayResult(
        success: false,
        errorMessage: 'Erro de conexão.',
      );
    } on FormatException {
      return const EsteiraTrialGatewayResult(
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
    return 'Não foi possível calcular o Modo Recuperação agora '
        '(HTTP ${response.statusCode}).';
  }
}
