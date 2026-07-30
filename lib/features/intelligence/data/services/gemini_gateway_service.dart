import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../dashboard/data/models/health_payload_model.dart';
import '../../../dashboard/data/services/health_sync_service.dart' show EventoAnomaliaSaude;

/// ⚠️ QUEBRADO E MORTO (achado em 30/jul/2026, ver RELATÓRIO/memória
/// `auditoria-codigo-morto-e-sem-especificacao`) — não é só código sem
/// chamador, as duas chamadas de rede aqui dentro FALHARIAM se alguém as
/// disparasse:
///   1. [processarImagemVisorPrato] faz POST em
///      [AppConfig.metricPhotoExtractionEndpoint] (`extract-metric-photo`),
///      mas parseia o formato de resposta ANTIGO
///      (`descricao_alimento`/`calorias` no nível raiz do JSON) — a Edge
///      Function real hoje roteia por `X-Tipo-Aparelho` e devolve
///      `itens`/`totais` (ver `supabase/functions/extract-metric-photo/
///      index.ts`). Este método nem manda o header `X-Tipo-Aparelho`.
///   2. [gerarRelatorioPreventivo] faz POST em
///      [AppConfig.preventiveInsightEndpoint]
///      (`generate-preventive-insight`) — Edge Function que **não existe**
///      em `supabase/functions/` (confirmado: só existem
///      `calculate-recovery-mode`, `extract-metric-photo`,
///      `garmin-gateway`, `manage-professional-link`, `search-food`).
///      Qualquer chamada real receberia 404.
/// Único chamador é [IntelligenceController] (também sem nenhum chamador de
/// produção — nunca instanciado por nenhuma tela real). Decisão registrada:
/// não apagar ainda (IntelligenceController/GeminiGatewayService formam uma
/// unidade — apagar um sem o outro deixaria o outro quebrado ou oco), só
/// documentar. Fica como pendência explícita para uma tarefa futura
/// decidir: apagar os dois juntos, ou reconstruir
/// `generate-preventive-insight` de verdade e religar.
///
/// Custo Zero / Zero Trust (PRD Mestre §3/§5): this service never talks to
/// Google's Generative AI API directly and never holds a Gemini API key —
/// an AI Studio key baked into a mobile binary via `--dart-define`/`.env`
/// is trivially extractable by decompiling the APK/IPA, which would both
/// violate Zero Trust and defeat "Custo Zero" the moment someone else's app
/// starts burning your free-tier quota with the leaked key.
///
/// Instead, both methods here POST to this app's own Supabase Edge
/// Functions (see [AppConfig.metricPhotoExtractionEndpoint] /
/// [AppConfig.preventiveInsightEndpoint]) — the Edge Function holds the
/// real key as a Supabase secret and calls Gemini 2.5 Flash server-side.
/// This mirrors the exact pattern [CameraCaptureController] already uses
/// for device-photo extraction; this file is the typed, reusable gateway
/// for the Módulo de Inteligência's own call sites.
///
/// Zero Storage Pipeline: [imageBytes] passed into
/// [processarImagemVisorPrato] lives only in RAM for the duration of the
/// HTTP request — this class never writes it to disk, and holds no
/// reference to it beyond the method call.
class GeminiGatewayService {
  GeminiGatewayService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const Duration _requestTimeout = Duration(seconds: 30);

  /// System prompt the paired Edge Function (`extract-metric-photo`) is
  /// expected to run server-side for photo analysis — kept here, in
  /// English (per PRD Mestre guidance: Gemini is measurably more reliable
  /// at strict-JSON instruction-following in English), as the audited
  /// source of truth for that contract.
  static const String systemPromptVisorPrato = '''
You are a strict clinical/nutritional data extraction engine analyzing a single photograph. The photo shows either (a) a plate of food, or (b) the digital display of a home blood pressure monitor or glucometer.

Rules:
- Respond with RAW JSON ONLY. No markdown code fences, no explanation, no text before or after the JSON object.
- If the photo shows food: return {"descricao_alimento": string, "calorias": number, "proteinas_g": number, "carboidratos_g": number, "gorduras_g": number}. Estimate conservatively from visual portion size.
- If the photo shows a blood pressure monitor display: return {"pressao_sistolica": number, "pressao_diastolica": number}.
- If the photo shows a glucometer display: return {"glicose_jejum": number}.
- If the image is unreadable, ambiguous, or none of the above, return {}.
- Never include a field you are not reasonably confident about — omit it instead of guessing.
''';

  /// System prompt the paired Edge Function (`generate-preventive-insight`)
  /// is expected to run server-side for the Dia 7 preventive report.
  static const String systemPromptRelatorioPreventivo = '''
You are a preventive-health assistant generating a single short insight for a fitness/wellness app user, based on a compact statistical summary of their recent biomarkers and any detected anomalies.

Rules:
- Respond with RAW JSON ONLY: {"insight": string}. No markdown, no extra fields, no text outside the JSON object.
- The insight must be 1-2 sentences, encouraging and actionable, written for a layperson — never alarming, never a diagnosis.
- Base it only on the summary provided; never invent data not present in it.
- If the summary shows no meaningful pattern, return a general encouragement instead of a fabricated insight.
''';

  /// Envia a foto (RAM apenas) de um prato ou do visor de um aparelho de
  /// pressão/glicose para extração estrita em JSON via Gemini 2.5 Flash.
  /// [authHeaders] deve trazer o `apikey`/`Authorization` da sessão Supabase
  /// atual — a mesma convenção de [CameraCaptureController.capturarEEnviar].
  Future<GeminiImageAnalysisResult> processarImagemVisorPrato(
    List<int> imageBytes, {
    required Map<String, String> authHeaders,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.metricPhotoExtractionEndpoint),
            headers: {
              ...authHeaders,
              'Content-Type': 'application/octet-stream',
            },
            body: imageBytes,
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return GeminiImageAnalysisResult(
          success: false,
          errorMessage: i18n.tr('intelligence.error_gateway_failure'),
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final resultado = GeminiVisorExtractionResult.fromJson(decoded);
      if (resultado.isEmpty) {
        return GeminiImageAnalysisResult(
          success: false,
          errorMessage: i18n.tr('intelligence.error_invalid_response'),
        );
      }

      return GeminiImageAnalysisResult(success: true, data: resultado);
    } on TimeoutException {
      return GeminiImageAnalysisResult(
        success: false,
        errorMessage: i18n.tr('intelligence.error_timeout'),
      );
    } on http.ClientException {
      return GeminiImageAnalysisResult(
        success: false,
        errorMessage: i18n.tr('intelligence.error_network'),
      );
    } on FormatException {
      return GeminiImageAnalysisResult(
        success: false,
        errorMessage: i18n.tr('intelligence.error_invalid_response'),
      );
    }
  }

  /// Gera o insight preventivo diário a partir de um resumo textual
  /// enxuto — nunca o histórico bruto linha a linha — mantendo o consumo
  /// de tokens (e portanto o custo) baixo. Ver [_construirResumoLeve].
  Future<GeminiPreventiveReportResult> gerarRelatorioPreventivo({
    required List<HealthPayloadModel> historico,
    required List<EventoAnomaliaSaude> anomalias,
    required Map<String, String> authHeaders,
  }) async {
    final resumo = _construirResumoLeve(historico, anomalias);

    try {
      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.preventiveInsightEndpoint),
            headers: {
              ...authHeaders,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'resumo': resumo}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return GeminiPreventiveReportResult(
          success: false,
          errorMessage: i18n.tr('intelligence.error_gateway_failure'),
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final insight = (decoded['insight'] as String?)?.trim();
      if (insight == null || insight.isEmpty) {
        return GeminiPreventiveReportResult(
          success: false,
          errorMessage: i18n.tr('intelligence.error_invalid_response'),
        );
      }

      return GeminiPreventiveReportResult(success: true, insightText: insight);
    } on TimeoutException {
      return GeminiPreventiveReportResult(
        success: false,
        errorMessage: i18n.tr('intelligence.error_timeout'),
      );
    } on http.ClientException {
      return GeminiPreventiveReportResult(
        success: false,
        errorMessage: i18n.tr('intelligence.error_network'),
      );
    } on FormatException {
      return GeminiPreventiveReportResult(
        success: false,
        errorMessage: i18n.tr('intelligence.error_invalid_response'),
      );
    }
  }

  /// Anonimização (PRD Mestre §3): só médias/últimos valores das colunas
  /// fixas e a contagem de anomalias por tipo entram no resumo — nunca um
  /// identificador do usuário, e nunca a série bruta dia a dia (o que
  /// também é o que mantém o prompt, e portanto o custo, pequeno).
  String _construirResumoLeve(
    List<HealthPayloadModel> historico,
    List<EventoAnomaliaSaude> anomalias,
  ) {
    if (historico.isEmpty) {
      return 'No recent biomarker data available.';
    }

    final buffer = StringBuffer('Last ${historico.length} days summary: ');
    final passosMedios = _mediaOuNull(historico.map((d) => d.passos?.toDouble()));
    final fcMedia = _mediaOuNull(historico.map((d) => d.fcRepouso?.toDouble()));
    final sonoMedioMin = _mediaOuNull(historico.map((d) => d.minutosSono?.toDouble()));
    double? pesoMaisRecente;
    for (final dia in historico.reversed) {
      if (dia.pesoKg != null) {
        pesoMaisRecente = dia.pesoKg;
        break;
      }
    }

    final partes = <String>[
      if (passosMedios != null) 'avg steps ${passosMedios.round()}',
      if (fcMedia != null) 'avg resting HR ${fcMedia.round()}bpm',
      if (sonoMedioMin != null) 'avg sleep ${(sonoMedioMin / 60).toStringAsFixed(1)}h',
      if (pesoMaisRecente != null) 'latest weight ${pesoMaisRecente.toStringAsFixed(1)}kg',
    ];
    buffer.write(partes.isEmpty ? 'no fixed-column signals present' : partes.join(', '));

    if (anomalias.isNotEmpty) {
      final porTipo = <String, int>{};
      for (final anomalia in anomalias) {
        porTipo[anomalia.tipoAnomalia] = (porTipo[anomalia.tipoAnomalia] ?? 0) + 1;
      }
      final anomaliasTexto =
          porTipo.entries.map((e) => '${e.key} x${e.value}').join(', ');
      buffer.write('. Detected anomalies: $anomaliasTexto');
    } else {
      buffer.write('. No anomalies detected.');
    }

    return buffer.toString();
  }

  double? _mediaOuNull(Iterable<double?> valores) {
    final validos = valores.whereType<double>().toList();
    if (validos.isEmpty) return null;
    return validos.reduce((a, b) => a + b) / validos.length;
  }
}

/// Outcome of [GeminiGatewayService.processarImagemVisorPrato].
@immutable
class GeminiImageAnalysisResult {
  final bool success;
  final GeminiVisorExtractionResult? data;
  final String? errorMessage;

  const GeminiImageAnalysisResult({
    required this.success,
    this.data,
    this.errorMessage,
  });
}

/// Outcome of [GeminiGatewayService.gerarRelatorioPreventivo].
@immutable
class GeminiPreventiveReportResult {
  final bool success;
  final String? insightText;
  final String? errorMessage;

  const GeminiPreventiveReportResult({
    required this.success,
    this.insightText,
    this.errorMessage,
  });
}

/// Polimórfico por natureza: uma foto de prato preenche [macros]; uma foto
/// de aparelho de pressão/glicose preenche [leituraDispositivo] (via o
/// parser já existente [HealthPayloadModel.fromAiExtraction]). No máximo um
/// dos dois é não-nulo.
@immutable
class GeminiVisorExtractionResult {
  final MacroNutrientesExtraidos? macros;
  final HealthPayloadModel? leituraDispositivo;

  const GeminiVisorExtractionResult({this.macros, this.leituraDispositivo});

  bool get isEmpty => macros == null && leituraDispositivo == null;

  factory GeminiVisorExtractionResult.fromJson(Map<String, dynamic> json) {
    final temCamposDeMacro = json.containsKey('calorias') ||
        json.containsKey('proteinas_g') ||
        json.containsKey('carboidratos_g') ||
        json.containsKey('gorduras_g');

    if (temCamposDeMacro) {
      return GeminiVisorExtractionResult(
        macros: MacroNutrientesExtraidos.fromJson(json),
      );
    }

    final leitura = HealthPayloadModel.fromAiExtraction(
      json,
      tipoAparelho: 'gemini_gateway',
    );
    return GeminiVisorExtractionResult(
      leituraDispositivo: leitura.isEmpty ? null : leitura,
    );
  }
}

/// Macros extraídos de uma foto de prato — espelho exato das colunas de
/// macro de `diario_alimentar_diario` (ver [toDiarioAlimentarJson]).
@immutable
class MacroNutrientesExtraidos {
  final String? descricaoAlimento;
  final double? calorias;
  final double? proteinasG;
  final double? carboidratosG;
  final double? gordurasG;

  const MacroNutrientesExtraidos({
    this.descricaoAlimento,
    this.calorias,
    this.proteinasG,
    this.carboidratosG,
    this.gordurasG,
  });

  factory MacroNutrientesExtraidos.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) => (value as num?)?.toDouble();
    return MacroNutrientesExtraidos(
      descricaoAlimento: json['descricao_alimento'] as String?,
      calorias: asDouble(json['calorias']),
      proteinasG: asDouble(json['proteinas_g']),
      carboidratosG: asDouble(json['carboidratos_g']),
      gordurasG: asDouble(json['gorduras_g']),
    );
  }

  /// Espelho exato das colunas de macro de `diario_alimentar_diario` —
  /// `tipoRefeicao` não vem do Gemini (a foto não diz se é café da manhã
  /// ou jantar), então é sempre fornecido pelo chamador.
  Map<String, dynamic> toDiarioAlimentarJson({required String tipoRefeicao}) => {
        'tipo_refeicao': tipoRefeicao,
        if (descricaoAlimento != null) 'descricao': descricaoAlimento,
        if (calorias != null) 'calorias': calorias,
        if (proteinasG != null) 'proteinas_g': proteinasG,
        if (carboidratosG != null) 'carboidratos_g': carboidratosG,
        if (gordurasG != null) 'gorduras_g': gordurasG,
      };
}
