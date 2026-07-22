import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/supabase/supabase_client.dart';
import 'health_sync_service.dart';

/// Entry point the OS re-launches the app's background isolate into
/// (Android: `WorkManager`; iOS: `BGTaskScheduler`, once the native `ios/`
/// project exists). Must stay a top-level function annotated
/// `vm:entry-point` — Workmanager looks it up by name after an app restart,
/// so it cannot be a class method or closure.
@pragma('vm:entry-point')
void backgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != BackgroundSyncManager.tarefaSyncDiario) {
      // Unknown task id — nothing this dispatcher knows how to run.
      return true;
    }

    try {
      if (!supabaseManager.isAuthenticated &&
          AppConfig.hasValidSupabaseCredentials) {
        await supabaseManager.initialize(
          supabaseUrl: AppConfig.supabaseUrl,
          supabaseAnonKey: AppConfig.supabaseAnonKey,
        );
      }

      final resultado = await HealthSyncService().sincronizarDeltaDiario();
      // Returning false tells WorkManager to retry with its backoff policy
      // (e.g. the device went offline mid-window) instead of silently
      // dropping the day's delta until tomorrow's run.
      return resultado.isSuccess;
    } catch (e) {
      debugPrint('sync_diario_wearables falhou: $e');
      return false;
    }
  });
}

/// Regra de Bateria Eficiente (Onda 1.5): schedules `sync_diario_wearables`
/// to run at most once a day, overnight, and only while the phone is
/// charging and on Wi-Fi — so the daily wearable sync never drains battery
/// or burns mobile data. This is the background-only path; the in-app
/// "sync now" button (`SyncUiController.forcarSincronizacaoAtleta`) runs the
/// same delta in foreground without touching WorkManager at all.
class BackgroundSyncManager {
  BackgroundSyncManager._();

  static final BackgroundSyncManager instance = BackgroundSyncManager._();

  /// Task id WorkManager reports back into [backgroundSyncCallbackDispatcher].
  static const String tarefaSyncDiario = 'sync_diario_wearables';

  /// Unique work name — registering again with the same name and
  /// [ExistingWorkPolicy.keep] is a safe no-op, so callers don't need to
  /// guard against calling [agendarSincronizacaoDiaria] more than once.
  static const String _nomeUnico = 'sync_diario_wearables_unique';

  static const Duration _frequencia = Duration(hours: 24);

  bool _inicializado = false;

  /// Registers [backgroundSyncCallbackDispatcher] with the native
  /// WorkManager/BGTaskScheduler bridge. Call once at app startup, before
  /// [agendarSincronizacaoDiaria].
  Future<void> inicializar({bool debugMode = false}) async {
    if (_inicializado) return;
    await Workmanager().initialize(
      backgroundSyncCallbackDispatcher,
      isInDebugMode: debugMode,
    );
    _inicializado = true;
  }

  /// Schedules the once-a-day, madrugada (overnight) sync. Constraints:
  /// `NetworkType.unmetered` (Wi-Fi only, never mobile data) and
  /// `requiresCharging: true` (phone plugged in). The OS still decides the
  /// exact moment within its maintenance window — [horaAlvo] only picks the
  /// earliest the task is allowed to fire, computed as an [initialDelay]
  /// from now; the periodic 24h [_frequencia] keeps it landing in roughly
  /// the same overnight window every day after that.
  Future<void> agendarSincronizacaoDiaria({int horaAlvo = 3}) async {
    await Workmanager().registerPeriodicTask(
      _nomeUnico,
      tarefaSyncDiario,
      frequency: _frequencia,
      initialDelay: _delayAteProximaMadrugada(horaAlvo),
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresCharging: true,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 30),
    );
  }

  Future<void> cancelarSincronizacaoDiaria() {
    return Workmanager().cancelByUniqueName(_nomeUnico);
  }

  Duration _delayAteProximaMadrugada(int horaAlvo) {
    final agora = DateTime.now();
    var alvo = DateTime(agora.year, agora.month, agora.day, horaAlvo);
    if (!alvo.isAfter(agora)) {
      alvo = alvo.add(const Duration(days: 1));
    }
    return alvo.difference(agora);
  }
}
