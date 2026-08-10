import 'package:health/health.dart';

/// A single normalized health reading, regardless of where it came from —
/// one [HealthDataType] read from a wearable, or the one-or-many values a
/// photo of a physical device yielded via AI extraction. Every property
/// below is a direct, typed mirror of a fixed column on the
/// `metricas_saude_diarias` table (Onda 1.5) — there is no generic
/// key/value map and no JSONB blob in this model or in [toJson]'s output.
class HealthPayloadModel {
  final int? passos;
  final double? distanciaMetros;
  final int? fcRepouso;
  final int? frequenciaCardiaca;
  final double? hrvMedio;
  final double? caloriasAtivas;
  final int? minutosSono;
  final int? sonoLeveMinutos;
  final int? sonoProfundoMinutos;
  final int? sonoRemMinutos;
  final int? sonoAcordadoMinutos;
  final double? pesoKg;
  final double? massaMagraKg;
  final double? percentualGordura;
  final int? pressaoSistolica;
  final int? pressaoDiastolica;
  final double? glicoseJejum;
  final double? saturacaoOxigenio;
  final double? temperaturaCorporal;

  final DateTime dateFrom;
  final DateTime dateTo;

  /// Where this reading came from: `'wearable'` or `'camera'`.
  final String source;

  /// Set only for camera-origin payloads — which physical device the
  /// photo was of (glicosímetro / pressão arterial / balança). Client-side
  /// context only; `metricas_saude_diarias` has no column for it.
  final String? tipoAparelho;

  const HealthPayloadModel({
    this.passos,
    this.distanciaMetros,
    this.fcRepouso,
    this.frequenciaCardiaca,
    this.hrvMedio,
    this.caloriasAtivas,
    this.minutosSono,
    this.sonoLeveMinutos,
    this.sonoProfundoMinutos,
    this.sonoRemMinutos,
    this.sonoAcordadoMinutos,
    this.pesoKg,
    this.massaMagraKg,
    this.percentualGordura,
    this.pressaoSistolica,
    this.pressaoDiastolica,
    this.glicoseJejum,
    this.saturacaoOxigenio,
    this.temperaturaCorporal,
    required this.dateFrom,
    required this.dateTo,
    required this.source,
    this.tipoAparelho,
  });

  /// Builds a single-field payload from one health-store reading, routing
  /// [type] to the one fixed column it corresponds to. [HealthDataType]
  /// values with no clinical column mapping (e.g. `WORKOUT`) yield a payload
  /// with every field null — filtered out by [isEmpty] downstream.
  factory HealthPayloadModel.fromHealthDataType({
    required HealthDataType type,
    required double value,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String source,
  }) {
    switch (type) {
      case HealthDataType.HEART_RATE:
        // Leitura genérica/contínua — distinta de RESTING_HEART_RATE logo
        // abaixo. Antes desta tarefa não existia essa distinção e HEART_RATE
        // caía em fcRepouso; ver RELATÓRIO (N17/N18) para a decisão.
        return HealthPayloadModel(
          frequenciaCardiaca: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.RESTING_HEART_RATE:
        return HealthPayloadModel(
          fcRepouso: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.LEAN_BODY_MASS:
        return HealthPayloadModel(
          massaMagraKg: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.STEPS:
        return HealthPayloadModel(
          passos: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.DISTANCE_WALKING_RUNNING:
      case HealthDataType.DISTANCE_DELTA:
        return HealthPayloadModel(
          distanciaMetros: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.ACTIVE_ENERGY_BURNED:
        return HealthPayloadModel(
          caloriasAtivas: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      // RELATÓRIO 20260811 — sono por estágio granular (decisão de produto:
      // aproveitar a riqueza do Garmin). SLEEP_SESSION propositalmente NÃO
      // mapeia aqui: cobre a noite inteira (incluindo acordado), não é um
      // estágio — ver HealthSyncService.todosOsTipos.
      case HealthDataType.SLEEP_LIGHT:
        return HealthPayloadModel(
          sonoLeveMinutos: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.SLEEP_DEEP:
        return HealthPayloadModel(
          sonoProfundoMinutos: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.SLEEP_REM:
        return HealthPayloadModel(
          sonoRemMinutos: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.SLEEP_AWAKE:
        return HealthPayloadModel(
          sonoAcordadoMinutos: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      // Fallback de dispositivos que só reportam "dormindo" sem quebrar em
      // estágio (não é o caso do Garmin, mas cobre outras fontes conectadas
      // ao Health Connect) — soma para sono_leve_minutos em vez de
      // descartar o dado; não existe uma coluna "genérica" separada (ver
      // RELATÓRIO 20260811 para a decisão completa).
      case HealthDataType.SLEEP_ASLEEP:
        return HealthPayloadModel(
          sonoLeveMinutos: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.HEART_RATE_VARIABILITY_SDNN:
      case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
        return HealthPayloadModel(
          hrvMedio: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.WEIGHT:
        return HealthPayloadModel(
          pesoKg: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.BODY_FAT_PERCENTAGE:
        return HealthPayloadModel(
          percentualGordura: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.BLOOD_PRESSURE_SYSTOLIC:
        return HealthPayloadModel(
          pressaoSistolica: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.BLOOD_PRESSURE_DIASTOLIC:
        return HealthPayloadModel(
          pressaoDiastolica: value.round(),
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.BLOOD_GLUCOSE:
        return HealthPayloadModel(
          glicoseJejum: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.BLOOD_OXYGEN:
        return HealthPayloadModel(
          saturacaoOxigenio: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      case HealthDataType.BODY_TEMPERATURE:
        return HealthPayloadModel(
          temperaturaCorporal: value,
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
      default:
        return HealthPayloadModel(
          dateFrom: dateFrom,
          dateTo: dateTo,
          source: source,
        );
    }
  }

  /// Parses the AI extraction JSON (already expected in fixed-column keys,
  /// e.g. `{"pressao_sistolica": 128, "pressao_diastolica": 82}`) into a
  /// payload stamped with the capture time — a device photo carries no
  /// timestamp of its own, so [dateFrom]/[dateTo] default to when the
  /// capture happened. Unrecognized keys and non-numeric values are
  /// silently dropped rather than thrown on, since the AI response is
  /// untrusted input.
  factory HealthPayloadModel.fromAiExtraction(
    Map<String, dynamic> json, {
    required String tipoAparelho,
    DateTime? capturedAt,
  }) {
    num? numOrNull(String key) {
      final raw = json[key];
      return raw is num ? raw : null;
    }

    final timestamp = capturedAt ?? DateTime.now();
    return HealthPayloadModel(
      passos: numOrNull('passos')?.round(),
      distanciaMetros: numOrNull('distancia_metros')?.toDouble(),
      fcRepouso: numOrNull('fc_repouso')?.round(),
      frequenciaCardiaca: numOrNull('frequencia_cardiaca')?.round(),
      hrvMedio: numOrNull('hrv_medio')?.toDouble(),
      caloriasAtivas: numOrNull('calorias_ativas')?.toDouble(),
      minutosSono: numOrNull('minutos_sono')?.round(),
      sonoLeveMinutos: numOrNull('sono_leve_minutos')?.round(),
      sonoProfundoMinutos: numOrNull('sono_profundo_minutos')?.round(),
      sonoRemMinutos: numOrNull('sono_rem_minutos')?.round(),
      sonoAcordadoMinutos: numOrNull('sono_acordado_minutos')?.round(),
      pesoKg: numOrNull('peso_kg')?.toDouble(),
      massaMagraKg: numOrNull('massa_magra_kg')?.toDouble(),
      percentualGordura: numOrNull('percentual_gordura')?.toDouble(),
      pressaoSistolica: numOrNull('pressao_sistolica')?.round(),
      pressaoDiastolica: numOrNull('pressao_diastolica')?.round(),
      glicoseJejum: numOrNull('glicose_jejum')?.toDouble(),
      saturacaoOxigenio: numOrNull('saturacao_oxigenio')?.toDouble(),
      temperaturaCorporal: numOrNull('temperatura_corporal')?.toDouble(),
      dateFrom: timestamp,
      dateTo: timestamp,
      source: 'camera',
      tipoAparelho: tipoAparelho,
    );
  }

  /// Parses a row read back from `metricas_saude_diarias` — the exact,
  /// symmetric counterpart of [toJson].
  factory HealthPayloadModel.fromJson(Map<String, dynamic> json) {
    num? asNum(String key) => json[key] as num?;
    final dataReferencia = DateTime.parse(json['data_referencia'] as String);
    return HealthPayloadModel(
      passos: asNum('passos')?.toInt(),
      distanciaMetros: asNum('distancia_metros')?.toDouble(),
      fcRepouso: asNum('fc_repouso')?.toInt(),
      frequenciaCardiaca: asNum('frequencia_cardiaca')?.toInt(),
      hrvMedio: asNum('hrv_medio')?.toDouble(),
      caloriasAtivas: asNum('calorias_ativas')?.toDouble(),
      minutosSono: asNum('minutos_sono')?.toInt(),
      sonoLeveMinutos: asNum('sono_leve_minutos')?.toInt(),
      sonoProfundoMinutos: asNum('sono_profundo_minutos')?.toInt(),
      sonoRemMinutos: asNum('sono_rem_minutos')?.toInt(),
      sonoAcordadoMinutos: asNum('sono_acordado_minutos')?.toInt(),
      pesoKg: asNum('peso_kg')?.toDouble(),
      massaMagraKg: asNum('massa_magra_kg')?.toDouble(),
      percentualGordura: asNum('percentual_gordura')?.toDouble(),
      pressaoSistolica: asNum('pressao_sistolica')?.toInt(),
      pressaoDiastolica: asNum('pressao_diastolica')?.toInt(),
      glicoseJejum: asNum('glicose_jejum')?.toDouble(),
      saturacaoOxigenio: asNum('saturacao_oxigenio')?.toDouble(),
      temperaturaCorporal: asNum('temperatura_corporal')?.toDouble(),
      dateFrom: dataReferencia,
      dateTo: dataReferencia,
      source: json['origem'] as String? ?? 'wearable',
    );
  }

  /// Exact, symmetric mirror of `metricas_saude_diarias`'s fixed columns —
  /// every key here is a real column name, typed to match its Postgres
  /// counterpart (`int` -> `int`/`bigint`, `double` -> `numeric`).
  Map<String, dynamic> toJson() => {
        'data_referencia': _dateOnly(dateFrom),
        'origem': source,
        if (passos != null) 'passos': passos,
        if (distanciaMetros != null) 'distancia_metros': distanciaMetros,
        if (fcRepouso != null) 'fc_repouso': fcRepouso,
        if (frequenciaCardiaca != null)
          'frequencia_cardiaca': frequenciaCardiaca,
        if (hrvMedio != null) 'hrv_medio': hrvMedio,
        if (caloriasAtivas != null) 'calorias_ativas': caloriasAtivas,
        if (minutosSono != null) 'minutos_sono': minutosSono,
        if (sonoLeveMinutos != null) 'sono_leve_minutos': sonoLeveMinutos,
        if (sonoProfundoMinutos != null)
          'sono_profundo_minutos': sonoProfundoMinutos,
        if (sonoRemMinutos != null) 'sono_rem_minutos': sonoRemMinutos,
        if (sonoAcordadoMinutos != null)
          'sono_acordado_minutos': sonoAcordadoMinutos,
        if (pesoKg != null) 'peso_kg': pesoKg,
        if (massaMagraKg != null) 'massa_magra_kg': massaMagraKg,
        if (percentualGordura != null) 'percentual_gordura': percentualGordura,
        if (pressaoSistolica != null) 'pressao_sistolica': pressaoSistolica,
        if (pressaoDiastolica != null) 'pressao_diastolica': pressaoDiastolica,
        if (glicoseJejum != null) 'glicose_jejum': glicoseJejum,
        if (saturacaoOxigenio != null) 'saturacao_oxigenio': saturacaoOxigenio,
        if (temperaturaCorporal != null)
          'temperatura_corporal': temperaturaCorporal,
      };

  static String _dateOnly(DateTime date) =>
      date.toIso8601String().split('T').first;

  /// Non-null clinical fields as `(coluna, valor)` pairs — for UI display
  /// (e.g. the camera-capture result dialog) without hardcoding a fixed
  /// subset of fields.
  List<MapEntry<String, num>> get camposPreenchidos => [
        if (passos != null) MapEntry('passos', passos!),
        if (distanciaMetros != null)
          MapEntry('distancia_metros', distanciaMetros!),
        if (fcRepouso != null) MapEntry('fc_repouso', fcRepouso!),
        if (frequenciaCardiaca != null)
          MapEntry('frequencia_cardiaca', frequenciaCardiaca!),
        if (hrvMedio != null) MapEntry('hrv_medio', hrvMedio!),
        if (caloriasAtivas != null) MapEntry('calorias_ativas', caloriasAtivas!),
        if (minutosSono != null) MapEntry('minutos_sono', minutosSono!),
        if (sonoLeveMinutos != null)
          MapEntry('sono_leve_minutos', sonoLeveMinutos!),
        if (sonoProfundoMinutos != null)
          MapEntry('sono_profundo_minutos', sonoProfundoMinutos!),
        if (sonoRemMinutos != null) MapEntry('sono_rem_minutos', sonoRemMinutos!),
        if (sonoAcordadoMinutos != null)
          MapEntry('sono_acordado_minutos', sonoAcordadoMinutos!),
        if (pesoKg != null) MapEntry('peso_kg', pesoKg!),
        if (massaMagraKg != null) MapEntry('massa_magra_kg', massaMagraKg!),
        if (percentualGordura != null)
          MapEntry('percentual_gordura', percentualGordura!),
        if (pressaoSistolica != null)
          MapEntry('pressao_sistolica', pressaoSistolica!),
        if (pressaoDiastolica != null)
          MapEntry('pressao_diastolica', pressaoDiastolica!),
        if (glicoseJejum != null) MapEntry('glicose_jejum', glicoseJejum!),
        if (saturacaoOxigenio != null)
          MapEntry('saturacao_oxigenio', saturacaoOxigenio!),
        if (temperaturaCorporal != null)
          MapEntry('temperatura_corporal', temperaturaCorporal!),
      ];

  bool get isEmpty => camposPreenchidos.isEmpty;
}
