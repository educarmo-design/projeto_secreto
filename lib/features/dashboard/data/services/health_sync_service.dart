import 'dart:io';

import 'package:health/health.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../models/health_payload_model.dart';

/// One normalized point read from Health Connect (Android) / HealthKit
/// (iOS). [sourceApp] is the app/device that actually wrote the point —
/// the OS health store merges data from every wearable and third-party app
/// connected to it, so this is what lets the UI tell "synced from Google
/// Fit" apart from "synced from this app".
class HealthMetricPoint {
  final HealthDataType type;
  final double value;
  final String unit;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String sourceApp;

  const HealthMetricPoint({
    required this.type,
    required this.value,
    required this.unit,
    required this.dateFrom,
    required this.dateTo,
    required this.sourceApp,
  });

  factory HealthMetricPoint.fromHealthDataPoint(HealthDataPoint point) {
    final rawValue = point.value;
    return HealthMetricPoint(
      type: point.type,
      value: rawValue is NumericHealthValue
          ? rawValue.numericValue.toDouble()
          : 0,
      unit: point.unit.name,
      dateFrom: point.dateFrom,
      dateTo: point.dateTo,
      sourceApp: point.sourceName,
    );
  }

  /// Converts to the normalized [HealthPayloadModel] shape shared with the
  /// camera/AI extraction path — e.g. for writing into Supabase's JSONB
  /// column alongside camera-origin readings.
  HealthPayloadModel toPayload() => HealthPayloadModel.fromHealthDataType(
    type: type,
    value: value,
    dateFrom: dateFrom,
    dateTo: dateTo,
    source: sourceApp.isEmpty ? 'wearable' : sourceApp,
  );
}

class HealthSyncResult {
  final bool granted;
  final List<HealthMetricPoint> points;
  final String? errorMessage;
  final bool needsHealthConnectInstall;

  const HealthSyncResult({
    required this.granted,
    this.points = const [],
    this.errorMessage,
    this.needsHealthConnectInstall = false,
  });

  factory HealthSyncResult.denied(String errorMessage) =>
      HealthSyncResult(granted: false, errorMessage: errorMessage);

  factory HealthSyncResult.needsInstall(String errorMessage) =>
      HealthSyncResult(
        granted: false,
        errorMessage: errorMessage,
        needsHealthConnectInstall: true,
      );

  /// Normalized payloads (one per point) ready for Supabase JSONB storage.
  /// Points whose [HealthDataType] has no [healthDataTypeToMetricKey]
  /// mapping yield an empty payload, filtered out here.
  List<HealthPayloadModel> toPayloads() => points
      .map((point) => point.toPayload())
      .where((payload) => !payload.isEmpty)
      .toList();
}

/// Bridges Health Connect (Android) / HealthKit (iOS) via the `health`
/// plugin. Zero-cost by design: no per-wearable vendor SDK and no paid
/// aggregation service — the device's OS health store already merges data
/// from every connected wearable and any third-party app that writes into
/// it, so a single read here covers all of them.
class HealthSyncService {
  HealthSyncService({Health? health}) : _health = health ?? Health() {
    _configured = _health.configure();
  }

  final Health _health;
  late final Future<void> _configured;

  /// The full superset of biological/clinical signals this app tracks.
  /// Some are platform-specific variants of the same signal (distance,
  /// sleep, HRV have a different [HealthDataType] on iOS vs. Android) —
  /// both variants are listed here and [_tiposSuportados] filters down to
  /// whichever this platform's health store actually exposes, so callers
  /// never have to branch on platform.
  static const List<HealthDataType> todosOsTipos = [
    HealthDataType.HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.WORKOUT,
  ];

  List<HealthDataType> get _tiposSuportados =>
      todosOsTipos.where(_health.isDataTypeAvailable).toList();

  /// Reads the complete telemetry history across every biological/clinical
  /// parameter this app tracks — heart rate, steps, distance, calories,
  /// sleep, HRV, weight, body fat, blood pressure, glucose, oxygen
  /// saturation and body temperature — for the last [dias] days (default
  /// 30). This is the one-time backfill so the dashboard isn't empty on
  /// day one after connecting a wearable.
  Future<HealthSyncResult> carregarHistoricoInicial({int dias = 30}) {
    return _lerComPermissao(_tiposSuportados, dias: dias);
  }

  /// Android-only: routes the user to install Health Connect from the
  /// store. No-op on iOS. Call when a [HealthSyncResult] comes back with
  /// [HealthSyncResult.needsHealthConnectInstall] set.
  Future<void> instalarHealthConnect() => _health.installHealthConnect();

  Future<HealthSyncResult> _lerComPermissao(
    List<HealthDataType> types, {
    required int dias,
  }) async {
    await _configured;

    try {
      if (Platform.isAndroid && !(await _health.isHealthConnectAvailable())) {
        return HealthSyncResult.needsInstall(
          i18n.tr('dashboard.health_connect_unavailable'),
        );
      }

      final permissions = List<HealthDataAccess>.filled(
        types.length,
        HealthDataAccess.READ_WRITE,
      );

      // hasPermissions() is best-effort: HealthKit never discloses read
      // grants (privacy), so it returns null on iOS for READ/READ_WRITE.
      // requestAuthorization() is safe to call unconditionally in that
      // case — it's a fast no-op if access was already granted.
      final alreadyGranted =
          await _health.hasPermissions(types, permissions: permissions) ??
          false;
      if (!alreadyGranted) {
        final granted = await _health.requestAuthorization(
          types,
          permissions: permissions,
        );
        if (!granted) {
          return HealthSyncResult.denied(
            i18n.tr('dashboard.health_permission_denied'),
          );
        }
      }

      final now = DateTime.now();
      final start = now.subtract(Duration(days: dias));
      final rawPoints = await _health.getHealthDataFromTypes(
        types: types,
        startTime: start,
        endTime: now,
      );

      return HealthSyncResult(
        granted: true,
        points: rawPoints.map(HealthMetricPoint.fromHealthDataPoint).toList(),
      );
    } catch (_) {
      return HealthSyncResult.denied(i18n.tr('dashboard.health_sync_error'));
    }
  }
}
