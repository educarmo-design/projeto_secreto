import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

import 'package:atleta_gamificacao/features/dashboard/data/services/background_sync_manager.dart';

/// Exercises [BackgroundSyncManager] through a fake [WorkmanagerPlatform] —
/// `workmanager: ^0.9.0+3` is a federated plugin (workmanager +
/// workmanager_platform_interface + workmanager_android/_apple); `Workmanager()`
/// now dispatches through `WorkmanagerPlatform.instance` instead of a raw,
/// hard-coded native `MethodChannel`, so intercepting a channel name (the
/// pre-0.9 approach) no longer sees any call — the default
/// `_PlaceholderImplementation` just throws `UnimplementedError` in a plain
/// `flutter test` VM, since no platform package registers itself there. This
/// is what actually proves the "impacto zero na bateria" contract: the exact
/// arguments (`networkType`, `requiresCharging`, `requiresBatteryNotLow`,
/// `frequency`) that will reach Android/iOS.
class _FakeWorkmanagerPlatform extends WorkmanagerPlatform {
  final List<
      ({
        String metodo,
        String? uniqueName,
        String? taskName,
        Duration? frequency,
        Duration? initialDelay,
        Constraints? constraints,
        ExistingPeriodicWorkPolicy? existingWorkPolicy,
        BackoffPolicy? backoffPolicy,
        Duration? backoffPolicyDelay,
      })> chamadas = [];

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
  }) async {
    chamadas.add((
      metodo: 'registerPeriodicTask',
      uniqueName: uniqueName,
      taskName: taskName,
      frequency: frequency,
      initialDelay: initialDelay,
      constraints: constraints,
      existingWorkPolicy: existingWorkPolicy,
      backoffPolicy: backoffPolicy,
      backoffPolicyDelay: backoffPolicyDelay,
    ));
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    chamadas.add((
      metodo: 'cancelByUniqueName',
      uniqueName: uniqueName,
      taskName: null,
      frequency: null,
      initialDelay: null,
      constraints: null,
      existingWorkPolicy: null,
      backoffPolicy: null,
      backoffPolicyDelay: null,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeWorkmanagerPlatform fake;

  setUp(() {
    fake = _FakeWorkmanagerPlatform();
    WorkmanagerPlatform.instance = fake;
  });

  test(
    'agendarSincronizacaoDiaria registra sync_diario_wearables uma vez por dia, '
    'restrito a Wi-Fi e carregamento',
    () async {
      await BackgroundSyncManager.instance.agendarSincronizacaoDiaria(horaAlvo: 3);

      expect(fake.chamadas, hasLength(1));
      final chamada = fake.chamadas.single;
      expect(chamada.metodo, 'registerPeriodicTask');
      expect(chamada.uniqueName, 'sync_diario_wearables_unique');
      expect(chamada.taskName, BackgroundSyncManager.tarefaSyncDiario);
      expect(BackgroundSyncManager.tarefaSyncDiario, 'sync_diario_wearables');
      expect(chamada.frequency, const Duration(hours: 24));

      final constraints = chamada.constraints!;
      expect(constraints.networkType, NetworkType.unmetered);
      expect(constraints.requiresCharging, isTrue);
      expect(constraints.requiresBatteryNotLow, isTrue);

      expect(chamada.existingWorkPolicy, ExistingPeriodicWorkPolicy.keep);
      expect(chamada.backoffPolicy, BackoffPolicy.linear);

      final delay = chamada.initialDelay!;
      expect(delay.inSeconds, greaterThanOrEqualTo(0));
      expect(delay.inSeconds, lessThanOrEqualTo(const Duration(days: 1).inSeconds));
    },
  );

  test('cancelarSincronizacaoDiaria cancela pelo nome único da tarefa', () async {
    await BackgroundSyncManager.instance.cancelarSincronizacaoDiaria();

    expect(fake.chamadas, hasLength(1));
    final chamada = fake.chamadas.single;
    expect(chamada.metodo, 'cancelByUniqueName');
    expect(chamada.uniqueName, 'sync_diario_wearables_unique');
  });
}
