import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistência local dos insights textuais gerados pela IA — mesmo padrão
/// já usado por `GamificationRepository` (`FlutterSecureStorage` como cache
/// local, não um round-trip ao Supabase a cada render) para que o Card
/// Recomendações da IA do Dashboard leia instantaneamente e funcione
/// offline.
///
/// Anonimização (PRD Mestre §3): o conteúdo salvo aqui é sempre o texto
/// genérico do insight (ex.: "Seu sono médio caiu 12% esta semana...") —
/// nunca um identificador do usuário, nunca dados brutos de biomarcador.
class RecommendationsRepository {
  RecommendationsRepository({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const String _insightKey = 'intelligence_recomendacao_ia_texto';
  static const String _geradoEmKey = 'intelligence_recomendacao_ia_gerado_em';

  /// Salva o insight mais recente — chamado por
  /// [IntelligenceController] logo após uma resposta bem-sucedida do
  /// Gemini via [GeminiGatewayService.gerarRelatorioPreventivo].
  Future<void> salvarInsight(String textoInsight) async {
    await _secureStorage.write(key: _insightKey, value: textoInsight);
    await _secureStorage.write(
      key: _geradoEmKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  /// `null` se a IA ainda não gerou nenhum insight — o Card Recomendações
  /// da IA mostra seu estado vazio nesse caso, nunca um erro.
  Future<String?> obterUltimoInsight() => _secureStorage.read(key: _insightKey);

  /// Quando o insight salvo foi gerado — útil para decidir se vale a pena
  /// buscar um novo antes de mostrar o cacheado.
  Future<DateTime?> obterDataGeracao() async {
    final raw = await _secureStorage.read(key: _geradoEmKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Limpa o insight salvo — chamado no logout, para que a próxima conta a
  /// usar o aparelho nunca veja a recomendação de outra pessoa.
  Future<void> limpar() async {
    await _secureStorage.delete(key: _insightKey);
    await _secureStorage.delete(key: _geradoEmKey);
  }
}
