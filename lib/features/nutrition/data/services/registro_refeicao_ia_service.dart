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
  RegistroRefeicaoIaService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  // Mesmo orçamento de `CameraCaptureController._uploadTimeout` (RELATÓRIO
  // 20260824_0001/0002/20260825_0003) — texto/áudio usam só o nível LITE
  // (sem fallback de modelo: já é o mais barato, `NIVEL_POR_TIPO` em
  // extract-metric-photo/index.ts), então o pior caso real de retry aqui é
  // bem menor que o da foto (CORE); mesmo timeout mantido só por
  // simplicidade — 60s nunca é um problema pro caminho comum, que termina
  // em poucos segundos.
  static const Duration _uploadTimeout = Duration(seconds: 60);

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
    final response = await _httpClient.post(endpoint, headers: headers, body: body).timeout(_uploadTimeout);

    if (response.statusCode != 200) {
      // Mesmo critério de `CameraCaptureController`: >=500 é "servidor
      // ocupado", 4xx é o texto que o próprio backend já devolve.
      throw RegistroRefeicaoIaException(
        mensagemAmigavel: response.statusCode >= 500
            ? 'Servidor ocupado. Tente novamente.'
            : (_extrairMensagemErroBackend(response.body) ?? 'Não foi possível interpretar a refeição.'),
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
