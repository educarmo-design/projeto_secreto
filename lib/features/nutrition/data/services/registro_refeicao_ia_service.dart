import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/prato_refeicao_extracao_model.dart';

/// RELATÓRIO 20260824_0003 — Registro de Refeição, Métodos 1 (descritivo)
/// e 2 (áudio). Mesma chamada HTTP/tratamento de erro que
/// `CameraCaptureController` já usa pra foto (Método 4) — extraído aqui
/// pra não triplicar essa lógica entre os 3 controllers (foto/texto/
/// áudio), já que texto/áudio não têm NADA de câmera/plugin de imagem
/// pra herdar de `CameraCaptureController`.
class RegistroRefeicaoIaException implements Exception {
  const RegistroRefeicaoIaException({
    required this.mensagemAmigavel,
    required this.detalheTecnico,
  });

  final String mensagemAmigavel;
  final String detalheTecnico;
}

class RegistroRefeicaoIaService {
  /// [uploadTimeout] é injetável só pra teste (simular timeout sem esperar
  /// os 90s reais) — em produção sempre usa o padrão abaixo.
  RegistroRefeicaoIaService({http.Client? httpClient, Duration? uploadTimeout})
      : _httpClient = httpClient ?? http.Client(),
        _uploadTimeout = uploadTimeout ?? _uploadTimeoutPadrao;

  final http.Client _httpClient;
  final Duration _uploadTimeout;

  // RELATÓRIO 20260901_0003 — mesmo orçamento de
  // `CameraCaptureController._uploadTimeout` (60s→90s): texto/áudio usam
  // só o nível LITE, o MESMO modelo (`gemini-flash-lite-latest`) medido ao
  // vivo nesta investigação com variação real de ~2s a 43s numa chamada
  // TRIVIAL — a mesma folga vale aqui, mesmo sem fallback de modelo (já é
  // o nível mais barato, `NIVEL_POR_TIPO` em extract-metric-photo/index.ts).
  static const Duration _uploadTimeoutPadrao = Duration(seconds: 90);

  /// Método 1 — texto livre digitado pelo usuário.
  Future<PratoRefeicaoExtracaoModel> interpretarTexto({
    required String descricao,
    required Uri endpoint,
    Map<String, String> headers = const {},
  }) {
    return _chamar(
      endpoint: endpoint,
      headers: {
        ...headers,
        'Content-Type': 'text/plain; charset=utf-8',
        'X-Tipo-Aparelho': 'pratoRefeicaoTexto',
      },
      body: utf8.encode(descricao),
    );
  }

  /// Método 2 — áudio curto falado pelo usuário. `bytesAudio` já é a
  /// gravação inteira em memória — Zero Storage do lado do app (o
  /// controller que grava é quem garante que o arquivo temporário do
  /// plugin `record` é apagado logo em seguida, mesmo padrão de
  /// `CameraCaptureController.capturarEEnviar`/`XFile`).
  Future<PratoRefeicaoExtracaoModel> interpretarAudio({
    required List<int> bytesAudio,
    required String mimeType,
    required Uri endpoint,
    Map<String, String> headers = const {},
  }) {
    return _chamar(
      endpoint: endpoint,
      headers: {
        ...headers,
        'Content-Type': 'application/octet-stream',
        'X-Tipo-Aparelho': 'pratoRefeicaoAudio',
        'X-Image-Mime': mimeType,
      },
      body: bytesAudio,
    );
  }

  Future<PratoRefeicaoExtracaoModel> _chamar({
    required Uri endpoint,
    required Map<String, String> headers,
    required List<int> body,
  }) async {
    final http.Response response;
    try {
      response = await _httpClient.post(endpoint, headers: headers, body: body).timeout(_uploadTimeout);
    } on TimeoutException catch (e) {
      // RELATÓRIO 20260901_0003 (mesmo achado de `CameraCaptureController`)
      // — o cliente desistiu de esperar, o que não é "servidor ocupado":
      // pode ser o Gemini genuinamente lento (medido ao vivo: LITE variou
      // de ~2s a 43s numa imagem trivial) ou a rede do aparelho.
      throw RegistroRefeicaoIaException(
        mensagemAmigavel: 'Tempo esgotado aguardando o servidor. Tente novamente.',
        detalheTecnico: 'TimeoutException aguardando $endpoint: $e',
      );
    } on http.ClientException catch (e) {
      // Falha de CONEXÃO (DNS, sem internet, conexão recusada) — o pedido
      // nem chegou a sair do aparelho, nunca é "servidor ocupado".
      throw RegistroRefeicaoIaException(
        mensagemAmigavel: 'Falha de conexão. Verifique sua internet e tente novamente.',
        detalheTecnico: e.toString(),
      );
    }

    if (response.statusCode != 200) {
      // RELATÓRIO 20260901_0003 — a mensagem do backend (quando existe)
      // tem prioridade em QUALQUER status, não só 4xx: `extract-metric-photo`
      // já manda `{"error": "Falha ao analisar a imagem."}` num 502 real,
      // por exemplo, e o código antigo jogava isso fora pra mostrar
      // "servidor ocupado" sempre que via >=500. "Servidor ocupado" agora
      // só aparece sem mensagem do backend E status genuinamente 503/504.
      final erroBackend = _extrairMensagemErroBackend(response.body);
      final ehServidorGenuinamenteOcupado =
          response.statusCode == 503 || response.statusCode == 504;
      throw RegistroRefeicaoIaException(
        mensagemAmigavel: erroBackend ??
            (ehServidorGenuinamenteOcupado
                ? 'Servidor ocupado. Tente novamente em instantes.'
                : response.statusCode >= 500
                    ? 'Erro no servidor. Tente novamente.'
                    : 'Não foi possível interpretar a refeição.'),
        detalheTecnico: 'HTTP ${response.statusCode} em $endpoint — corpo: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    // Lança FormatException numa resposta malformada — mesmo caminho de
    // erro que a foto já tem (Regra 0.15: contrato quebrado, não estimativa
    // incerta de IA), o controller trata igual.
    return PratoRefeicaoExtracaoModel.fromJson(decoded);
  }

  /// Mesma lógica de `CameraCaptureController._extrairMensagemErroBackend`
  /// (duplicada de propósito — função pura de poucas linhas, evita puxar
  /// import de dashboard/camera pra dentro de nutrition só por isso, mesma
  /// justificativa já registrada em outros pares de utilitário duplicado
  /// deste projeto).
  String? _extrairMensagemErroBackend(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['message'] is String) return decoded['message'] as String;
        if (decoded['error'] is String) return decoded['error'] as String;
      }
    } catch (_) {
      // Corpo não é JSON — sem mensagem específica pra extrair.
    }
    return null;
  }

  void dispose() => _httpClient.close();
}
