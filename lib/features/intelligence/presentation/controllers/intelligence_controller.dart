import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../dashboard/data/models/health_payload_model.dart';
import '../../../dashboard/data/services/health_sync_service.dart' show EventoAnomaliaSaude;
import '../../data/repositories/recommendations_repository.dart';
import '../../data/services/gemini_gateway_service.dart';

/// Estrutura consumida pelo widget do cadeado dourado
/// (`TeaserConversaoPage`): as duas trajetórias de 7 pontos (hoje + 6
/// meses, normalizadas 0..1) que `_LongevityProjectionPainter` desenha, e o
/// insight textual que fica por trás do blur.
///
/// [trajetoriaAtual]/[trajetoriaOtimizada] são uma heurística
/// determinística simples (não um modelo preditivo clínico): uma pontuação
/// composta 0..1 do dia mais recente, projetada adiante com a tendência
/// observada no histórico (trajetória otimizada = mesma tendência, só que
/// invertida para melhora e amplificada — representando adesão às
/// recomendações do app). Calculado inteiramente no cliente a partir de
/// dados já carregados — só o texto do insight vem do Gemini, o que é
/// também o que mantém o consumo de tokens baixo.
@immutable
class ProjecaoLongevidadeResult {
  final DateTime geradoEm;
  final String insightPreventivo;
  final List<double> trajetoriaAtual;
  final List<double> trajetoriaOtimizada;
  final int totalAnomalias;

  const ProjecaoLongevidadeResult({
    required this.geradoEm,
    required this.insightPreventivo,
    required this.trajetoriaAtual,
    required this.trajetoriaOtimizada,
    required this.totalAnomalias,
  });
}

/// Orquestra as chamadas ao [GeminiGatewayService] e estrutura seus
/// resultados para consumo pela UI — nem esta classe nem o gateway que ela
/// chama jamais tocam uma API key de IA; toda a chamada real ao Gemini
/// acontece na Edge Function do lado do servidor (ver
/// [GeminiGatewayService]).
class IntelligenceController extends ChangeNotifier {
  IntelligenceController({
    SupabaseClient? client,
    GeminiGatewayService? gatewayService,
    RecommendationsRepository? recommendationsRepository,
  })  : _client = client ?? Supabase.instance.client,
        _gateway = gatewayService ?? GeminiGatewayService(),
        _recommendationsRepository =
            recommendationsRepository ?? RecommendationsRepository();

  final SupabaseClient _client;
  final GeminiGatewayService _gateway;
  final RecommendationsRepository _recommendationsRepository;

  static const int _diasHistoricoConsiderados = 30;
  static const int _pontosTrajetoria = 7;

  bool _isLoading = false;
  ProjecaoLongevidadeResult? _projecao;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  ProjecaoLongevidadeResult? get projecao => _projecao;
  String? get errorMessage => _errorMessage;

  /// Roda no Dia 7 do trial — o chamador (a tela que hospeda
  /// `TeaserConversaoPage`, gated por
  /// `EsteiraTrialState.gatilhoDia7Ativo`) decide *quando* chamar isto;
  /// este método sempre calcula quando invocado.
  ///
  /// Busca os biomarcadores (`metricas_saude_diarias`) e anomalias
  /// (`eventos_anomalias_saude`) dos últimos [_diasHistoricoConsiderados]
  /// dias, pede ao Gemini o insight preventivo (via resumo leve, nunca o
  /// histórico bruto), salva esse insight em [RecommendationsRepository]
  /// para leitura instantânea/offline pelo Card Recomendações da IA, e
  /// estrutura o resultado borrado que o cadeado dourado consome.
  Future<void> calcularProjecaoLongevidadeDia7() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _errorMessage = i18n.tr('intelligence.error_no_user');
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final historico = await _buscarHistorico(userId);
      final anomalias = await _buscarAnomalias(userId);

      final relatorio = await _gateway.gerarRelatorioPreventivo(
        historico: historico,
        anomalias: anomalias,
        authHeaders: _authHeaders(),
      );

      if (!relatorio.success || relatorio.insightText == null) {
        _errorMessage =
            relatorio.errorMessage ?? i18n.tr('intelligence.error_gateway_failure');
        return;
      }

      final pontuacaoAtual = _pontuacaoComposta(historico);
      final tendencia = _tendenciaSemanal(historico);

      _projecao = ProjecaoLongevidadeResult(
        geradoEm: DateTime.now(),
        insightPreventivo: relatorio.insightText!,
        trajetoriaAtual: _projetarTrajetoria(
          pontuacaoInicial: pontuacaoAtual,
          tendenciaMensal: tendencia,
        ),
        trajetoriaOtimizada: _projetarTrajetoria(
          pontuacaoInicial: pontuacaoAtual,
          tendenciaMensal: tendencia,
          otimizada: true,
        ),
        totalAnomalias: anomalias.length,
      );

      await _recommendationsRepository.salvarInsight(relatorio.insightText!);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Ponto de entrada para o Card Câmera Nutricional/Aparelhos Clínicos do
  /// Dashboard usarem a extração via Gemini sem falar com
  /// [GeminiGatewayService] diretamente.
  Future<GeminiImageAnalysisResult> analisarFotoVisor(
    List<int> imageBytes,
  ) async {
    return _gateway.processarImagemVisorPrato(
      imageBytes,
      authHeaders: _authHeaders(),
    );
  }

  Future<List<HealthPayloadModel>> _buscarHistorico(String userId) async {
    final desde = DateTime.now().subtract(
      const Duration(days: _diasHistoricoConsiderados),
    );
    final response = await _client
        .from('metricas_saude_diarias')
        .select()
        .eq('usuario_id_anonimo', userId)
        .gte('data_referencia', _dataOnlyIso(desde))
        .order('data_referencia');

    return (response as List)
        .cast<Map<String, dynamic>>()
        .map(HealthPayloadModel.fromJson)
        .toList();
  }

  Future<List<EventoAnomaliaSaude>> _buscarAnomalias(String userId) async {
    final desde = DateTime.now().subtract(
      const Duration(days: _diasHistoricoConsiderados),
    );
    final response = await _client
        .from('eventos_anomalias_saude')
        .select()
        .eq('usuario_id_anonimo', userId)
        .gte('detectado_em', desde.toIso8601String())
        .order('detectado_em', ascending: false);

    return (response as List)
        .cast<Map<String, dynamic>>()
        .map(EventoAnomaliaSaude.fromJson)
        .toList();
  }

  Map<String, String> _authHeaders() {
    final session = _client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  /// Pontuação composta 0..1 do dia mais recente com dados — cada sinal
  /// presente contribui igualmente; um sinal ausente (ex.: usuário não
  /// pesou-se hoje) simplesmente não entra na média, em vez de penalizar o
  /// dia por um dado que nunca foi coletado.
  double _pontuacaoComposta(List<HealthPayloadModel> historico) {
    if (historico.isEmpty) return 0.5;
    final dia = historico.last;

    final componentes = <double>[
      if (dia.passos != null) (dia.passos! / 10000).clamp(0.0, 1.0),
      if (dia.fcRepouso != null)
        (1 - ((dia.fcRepouso! - 60).abs() / 40)).clamp(0.0, 1.0),
      if (dia.minutosSono != null) (dia.minutosSono! / 480).clamp(0.0, 1.0),
    ];
    if (componentes.isEmpty) return 0.5;
    return componentes.reduce((a, b) => a + b) / componentes.length;
  }

  /// Tendência simples: diferença de pontuação composta entre a primeira e
  /// a última semana do histórico disponível, normalizada por semana.
  /// Positiva = melhorando; negativa = piorando; 0 sem histórico suficiente.
  double _tendenciaSemanal(List<HealthPayloadModel> historico) {
    if (historico.length < 14) return 0.0;

    final primeiraSemana = historico.take(7).toList();
    final ultimaSemana = historico.skip(historico.length - 7).toList();

    final pontuacaoInicial = _pontuacaoComposta(primeiraSemana);
    final pontuacaoFinal = _pontuacaoComposta(ultimaSemana);
    final semanasEntre = (historico.length / 7).clamp(1, double.infinity);

    return (pontuacaoFinal - pontuacaoInicial) / semanasEntre;
  }

  List<double> _projetarTrajetoria({
    required double pontuacaoInicial,
    required double tendenciaMensal,
    bool otimizada = false,
  }) {
    final inclinacao =
        otimizada ? tendenciaMensal.abs() * 1.5 + 0.03 : tendenciaMensal;
    return List<double>.generate(
      _pontosTrajetoria,
      (mes) => (pontuacaoInicial + inclinacao * mes).clamp(0.0, 1.0),
    );
  }

  static String _dataOnlyIso(DateTime data) =>
      data.toIso8601String().split('T').first;
}
