import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/dashboard/data/services/background_sync_manager.dart';

/// Exercises [BackgroundSyncManager] through the real `workmanager` plugin
/// channel — intercepting its foreground `MethodChannel` instead of
/// injecting a fake, since `Workmanager()` is a hard-coded plugin singleton
/// with no seam for dependency injection. This is what actually proves the
/// "impacto zero na bateria" contract: the exact native arguments
/// (`networkType`, `requiresCharging`, `requiresBatteryNotLow`, `frequency`)
/// that will reach Android/iOS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'be.tramckrijte.workmanager/foreground_channel_work_manager',
  );
  final chamadas = <MethodCall>[];

  setUp(() {
    chamadas.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      chamadas.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'agendarSincronizacaoDiaria registra sync_diario_wearables uma vez por dia, '
    'restrito a Wi-Fi e carregamento',
    () async {
      await BackgroundSyncManager.instance.agendarSincronizacaoDiaria(horaAlvo: 3);

      expect(chamadas, hasLength(1));
      final chamada = chamadas.single;
      expect(chamada.method, 'registerPeriodicTask');

      final args = Map<String, dynamic>.from(chamada.arguments as Map);
      expect(args['uniqueName'], 'sync_diario_wearables_unique');
      expect(args['taskName'], BackgroundSyncManager.tarefaSyncDiario);
      expect(BackgroundSyncManager.tarefaSyncDiario, 'sync_diario_wearables');
      expect(args['frequency'], const Duration(hours: 24).inSeconds);
      expect(args['networkType'], 'unmetered');
      expect(args['requiresCharging'], isTrue);
      expect(args['requiresBatteryNotLow'], isTrue);
      expect(args['existingWorkPolicy'], 'keep');
      expect(args['backoffPolicyType'], 'linear');

      final delay = args['initialDelaySeconds'] as int;
      expect(delay, greaterThanOrEqualTo(0));
      expect(delay, lessThanOrEqualTo(const Duration(days: 1).inSeconds));
    },
  );

  test('cancelarSincronizacaoDiaria cancela pelo nome único da tarefa', () async {
    await BackgroundSyncManager.instance.cancelarSincronizacaoDiaria();

    expect(chamadas, hasLength(1));
    final chamada = chamadas.single;
    expect(chamada.method, 'cancelTaskByUniqueName');
    expect(chamada.arguments, {'uniqueName': 'sync_diario_wearables_unique'});
  });
}
