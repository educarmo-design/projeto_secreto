import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';
import '../models/alimento_encontrado_model.dart';

class FoodSearchResult {
  final bool success;
  final List<AlimentoEncontradoModel> alimentos;
  final String? errorMessage;

  const FoodSearchResult({
    required this.success,
    this.alimentos = const [],
    this.errorMessage,
  });
}

/// Gateway de `search-food` (Adendo v5.1 §A.3/§C.3 — "Cérebro da Busca") —
/// mesmo padrão de [ManageProfessionalLinkGatewayService]: HTTP puro, sem
/// tocar Supabase diretamente, com timeout e mapeamento de erro de rede
/// próprios para que o controller nunca precise lidar com exceções.
class FoodSearchService {
  FoodSearchService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _requestTimeout = Duration(seconds: 15);

  Future<FoodSearchResult> buscar({
    required String query,
    required Map<String, String> authHeaders,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.searchFoodEndpoint),
            headers: {
              ...authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'query': query}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return FoodSearchResult(success: false, errorMessage: _mensagemDeErro(response));
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final resultados = (decoded['results'] as List? ?? const [])
          .map((item) => AlimentoEncontradoModel.fromJson(item as Map<String, dynamic>))
          .toList();
      return FoodSearchResult(success: true, alimentos: resultados);
    } on TimeoutException {
      return const FoodSearchResult(
        success: false,
        errorMessage: 'Tempo esgotado ao falar com o servidor.',
      );
    } on http.ClientException {
      return const FoodSearchResult(success: false, errorMessage: 'Erro de conexão.');
    } on FormatException {
      return const FoodSearchResult(
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
    return 'Não foi possível buscar alimentos agora (HTTP ${response.statusCode}).';
  }
}
