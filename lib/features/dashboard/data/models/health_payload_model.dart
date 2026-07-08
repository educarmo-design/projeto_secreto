import 'package:health/health.dart';

/// Internationally-normalized keys shared by every leg of the health
/// telemetry pipeline — wearable sync (`HealthSyncService`), AI photo
/// extraction (`CameraCaptureController`), and the Supabase JSONB column
/// that stores both. One canonical key set means the dashboard, the AI
/// prompt, and the database never have to translate between three
/// different naming schemes.
enum HealthMetricKey {
  heartRate('heart_rate'),
  steps('steps'),
  distance('distance_meters'),
  activeEnergyBurned('active_energy_burned'),
  sleepMinutes('sleep_minutes'),
  hrv('hrv'),
  weight('weight_kg'),
  bodyFatPercentage('body_fat_percentage'),
  systolic('systolic'),
  diastolic('diastolic'),
  bloodGlucose('blood_glucose'),
  bloodOxygen('blood_oxygen'),
  bodyTemperature('body_temperature');

  const HealthMetricKey(this.jsonKey);

  /// The fixed, internationally-normalized JSONB key (e.g. `heart_rate`,
  /// `blood_glucose`, `systolic`, `diastolic`, `hrv`) — stable across app
  /// languages, the Supabase schema, and the AI extraction prompt.
  final String jsonKey;

  static HealthMetricKey? fromJsonKey(String jsonKey) {
    for (final key in values) {
      if (key.jsonKey == jsonKey) return key;
    }
    return null;
  }
}

/// Maps a `health` package [HealthDataType] to its normalized
/// [HealthMetricKey]. Some biological signals have a different
/// [HealthDataType] per platform (distance, sleep, HRV) — both sides
/// collapse to the same normalized key here, so callers never branch on
/// platform after this point.
const Map<HealthDataType, HealthMetricKey> healthDataTypeToMetricKey = {
  HealthDataType.HEART_RATE: HealthMetricKey.heartRate,
  HealthDataType.STEPS: HealthMetricKey.steps,
  HealthDataType.DISTANCE_WALKING_RUNNING: HealthMetricKey.distance,
  HealthDataType.DISTANCE_DELTA: HealthMetricKey.distance,
  HealthDataType.ACTIVE_ENERGY_BURNED: HealthMetricKey.activeEnergyBurned,
  HealthDataType.SLEEP_SESSION: HealthMetricKey.sleepMinutes,
  HealthDataType.SLEEP_ASLEEP: HealthMetricKey.sleepMinutes,
  HealthDataType.HEART_RATE_VARIABILITY_SDNN: HealthMetricKey.hrv,
  HealthDataType.HEART_RATE_VARIABILITY_RMSSD: HealthMetricKey.hrv,
  HealthDataType.WEIGHT: HealthMetricKey.weight,
  HealthDataType.BODY_FAT_PERCENTAGE: HealthMetricKey.bodyFatPercentage,
  HealthDataType.BLOOD_PRESSURE_SYSTOLIC: HealthMetricKey.systolic,
  HealthDataType.BLOOD_PRESSURE_DIASTOLIC: HealthMetricKey.diastolic,
  HealthDataType.BLOOD_GLUCOSE: HealthMetricKey.bloodGlucose,
  HealthDataType.BLOOD_OXYGEN: HealthMetricKey.bloodOxygen,
  HealthDataType.BODY_TEMPERATURE: HealthMetricKey.bodyTemperature,
};

/// A single normalized health reading, regardless of where it came from —
/// one [HealthDataType] read from a wearable, or the one-or-many values a
/// photo of a physical device yielded via AI extraction. [toJson] is what
/// is actually written to Supabase's JSONB column, and the shape the AI
/// extraction prompt is instructed to reply in.
class HealthPayloadModel {
  final Map<HealthMetricKey, double> values;
  final DateTime dateFrom;
  final DateTime dateTo;

  /// Where this reading came from: `'wearable'` or `'camera'`.
  final String source;

  /// Set only for camera-origin payloads — which physical device the
  /// photo was of (glicosímetro / pressão arterial / balança).
  final String? tipoAparelho;

  const HealthPayloadModel({
    required this.values,
    required this.dateFrom,
    required this.dateTo,
    required this.source,
    this.tipoAparelho,
  });

  /// Builds a single-key payload from one health-store reading.
  factory HealthPayloadModel.fromHealthDataType({
    required HealthDataType type,
    required double value,
    required DateTime dateFrom,
    required DateTime dateTo,
    required String source,
  }) {
    final key = healthDataTypeToMetricKey[type];
    return HealthPayloadModel(
      values: key == null ? const {} : {key: value},
      dateFrom: dateFrom,
      dateTo: dateTo,
      source: source,
    );
  }

  /// Parses the AI extraction JSON (already expected in normalized keys,
  /// e.g. `{"systolic": 128, "diastolic": 82}`) into a payload stamped
  /// with the capture time — a device photo carries no timestamp of its
  /// own, so [dateFrom]/[dateTo] default to when the capture happened.
  /// Unrecognized keys and non-numeric values are silently dropped rather
  /// than thrown on, since the AI response is untrusted input.
  factory HealthPayloadModel.fromAiExtraction(
    Map<String, dynamic> json, {
    required String tipoAparelho,
    DateTime? capturedAt,
  }) {
    final values = <HealthMetricKey, double>{};
    for (final entry in json.entries) {
      final key = HealthMetricKey.fromJsonKey(entry.key);
      final raw = entry.value;
      if (key != null && raw is num) {
        values[key] = raw.toDouble();
      }
    }
    final timestamp = capturedAt ?? DateTime.now();
    return HealthPayloadModel(
      values: values,
      dateFrom: timestamp,
      dateTo: timestamp,
      source: 'camera',
      tipoAparelho: tipoAparelho,
    );
  }

  Map<String, dynamic> toJson() => {
        for (final entry in values.entries) entry.key.jsonKey: entry.value,
        'date_from': dateFrom.toIso8601String(),
        'date_to': dateTo.toIso8601String(),
        'source': source,
        if (tipoAparelho != null) 'tipo_aparelho': tipoAparelho,
      };

  bool get isEmpty => values.isEmpty;
}
