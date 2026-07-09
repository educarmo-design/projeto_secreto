import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/services/health_sync_service.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/controllers/sync_ui_controller.dart';

import '../../../../support/fake_secure_storage.dart';

class _MockHealthSyncService extends Mock implements HealthSyncService {}

class _MockConnectivity extends Mock implements Connectivity {}

/// Matches [SyncUiController]'s private `_chaveFilaPendente` constant —
/// duplicated here deliberately, the same way the test would if it were
/// asserting against any other persisted-storage contract of the class
/// under test.
const _chaveFilaPendente = 'pending_metricas_saude_payloads';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerFallbackValue(<Map<String, dynamic>>[]);
    await i18n.initialize('pt');
  });

  late _MockHealthSyncService healthSyncService;
  late _MockConnectivity connectivity;
  late StreamController<List<ConnectivityResult>> connectivityStream;
  late FakeSecureStorage secureStorage;

  SyncUiController criarController() {
    return SyncUiController(
      healthSyncService: healthSyncService,
      secureStorage: secureStorage,
      connectivity: connectivity,
    );
  }

  setUp(() {
    healthSyncService = _MockHealthSyncService();
    connectivity = _MockConnectivity();
    connectivityStream = StreamController<List<ConnectivityResult>>.broadcast();
    secureStorage = FakeSecureStorage();

    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => connectivityStream.stream);
    when(() => healthSyncService.obterUltimaSincronizacao())
        .thenAnswer((_) async => null);
  });

  tearDown(() => connectivityStream.close());

  test('estado inicial reflete o último sync e a fila persistida', () async {
    final ultimoSync = DateTime(2026, 7, 7, 22);
    when(() => healthSyncService.obterUltimaSincronizacao())
        .thenAnswer((_) async => ultimoSync);
    await secureStorage.write(
      key: _chaveFilaPendente,
      value: jsonEncode([
        {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-07-06', 'passos': 100},
      ]),
    );

    final controller = criarController();
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.ultimaSincronizacaoEm, ultimoSync);
    expect(controller.value.pendentesNaFila, 1);
    expect(controller.value.temPendentes, isTrue);
  });

  group('forcarSincronizacaoAtleta', () {
    test('sucesso passa por carregando e termina em sucesso', () async {
      final agora = DateTime(2026, 7, 8, 8, 30);
      when(() => healthSyncService.sincronizarDeltaDiario()).thenAnswer(
        (_) async => DeltaSyncResult(
          outcome: DeltaSyncOutcome.sucesso,
          sincronizadoEm: agora,
        ),
      );

      final controller = criarController();
      await Future<void>.delayed(Duration.zero);

      final estados = <SyncUiStatus>[];
      controller.addListener(() => estados.add(controller.value.status));

      await controller.forcarSincronizacaoAtleta();

      expect(estados.first, SyncUiStatus.carregando);
      expect(estados.last, SyncUiStatus.sucesso);
      expect(controller.value.ultimaSincronizacaoEm, agora);
      expect(controller.value.isSuccess, isTrue);
    });

    test('chamada é ignorada se já houver uma sincronização em andamento', () async {
      final completer = Completer<DeltaSyncResult>();
      when(() => healthSyncService.sincronizarDeltaDiario())
          .thenAnswer((_) => completer.future);

      final controller = criarController();
      await Future<void>.delayed(Duration.zero);

      final primeira = controller.forcarSincronizacaoAtleta();
      final segunda = controller.forcarSincronizacaoAtleta();

      completer.complete(
        const DeltaSyncResult(outcome: DeltaSyncOutcome.semAlteracoes),
      );
      await Future.wait([primeira, segunda]);

      verify(() => healthSyncService.sincronizarDeltaDiario()).called(1);
    });

    test('offline enfileira o payload em cache seguro e expõe o total pendente', () async {
      final linhas = [
        {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-07-08', 'passos': 500},
        {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-07-07', 'passos': 300},
      ];
      when(() => healthSyncService.sincronizarDeltaDiario()).thenAnswer(
        (_) async => DeltaSyncResult(outcome: DeltaSyncOutcome.offline, linhas: linhas),
      );

      final controller = criarController();
      await Future<void>.delayed(Duration.zero);

      await controller.forcarSincronizacaoAtleta();

      expect(controller.value.status, SyncUiStatus.offline);
      expect(controller.value.pendentesNaFila, 2);

      final persistido = await secureStorage.read(key: _chaveFilaPendente);
      final decodido = jsonDecode(persistido!) as List<dynamic>;
      expect(decodido, hasLength(2));
    });

    test('enfileirar por dois dias distintos não duplica ao reenfileirar o mesmo dia', () async {
      when(() => healthSyncService.sincronizarDeltaDiario()).thenAnswer(
        (_) async => DeltaSyncResult(
          outcome: DeltaSyncOutcome.offline,
          linhas: [
            {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-07-08', 'passos': 500},
          ],
        ),
      );
      final controller = criarController();
      await Future<void>.delayed(Duration.zero);
      await controller.forcarSincronizacaoAtleta();

      when(() => healthSyncService.sincronizarDeltaDiario()).thenAnswer(
        (_) async => DeltaSyncResult(
          outcome: DeltaSyncOutcome.offline,
          linhas: [
            {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-07-08', 'passos': 900},
          ],
        ),
      );
      await controller.forcarSincronizacaoAtleta();

      expect(controller.value.pendentesNaFila, 1);
      final persistido = await secureStorage.read(key: _chaveFilaPendente);
      final decodido = jsonDecode(persistido!) as List<dynamic>;
      expect((decodido.single as Map)['passos'], 900);
    });

    test('falha expõe a mensagem de erro sem tocar na fila offline', () async {
      when(() => healthSyncService.sincronizarDeltaDiario()).thenAnswer(
        (_) async => const DeltaSyncResult(
          outcome: DeltaSyncOutcome.erro,
          errorMessage: 'Erro ao sincronizar dados',
        ),
      );

      final controller = criarController();
      await Future<void>.delayed(Duration.zero);

      await controller.forcarSincronizacaoAtleta();

      expect(controller.value.status, SyncUiStatus.falha);
      expect(controller.value.isError, isTrue);
      expect(controller.value.errorMessage, 'Erro ao sincronizar dados');
      expect(controller.value.pendentesNaFila, 0);
    });
  });

  test(
    'conectividade recuperada despacha a fila offline automaticamente e limpa o cache',
    () async {
      await secureStorage.write(
        key: _chaveFilaPendente,
        value: jsonEncode([
          {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-07-06', 'passos': 100},
        ]),
      );
      when(() => healthSyncService.despacharLinhasPendentes(any()))
          .thenAnswer((_) async => true);
      final proximoSync = DateTime(2026, 7, 8, 9);
      when(() => healthSyncService.obterUltimaSincronizacao())
          .thenAnswer((_) async => proximoSync);

      final controller = criarController();
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.pendentesNaFila, 1);

      connectivityStream.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final captura = verify(
        () => healthSyncService.despacharLinhasPendentes(captureAny()),
      ).captured;
      expect((captura.single as List).single, isA<Map<String, dynamic>>());

      expect(controller.value.status, SyncUiStatus.sucesso);
      expect(controller.value.pendentesNaFila, 0);
      expect(controller.value.ultimaSincronizacaoEm, proximoSync);
      expect(await secureStorage.read(key: _chaveFilaPendente), isNull);
    },
  );

  test('ficar offline (sem itens na fila) não tenta despachar nada', () async {
    when(() => healthSyncService.despacharLinhasPendentes(any()))
        .thenAnswer((_) async => true);

    final controller = criarController();
    await Future<void>.delayed(Duration.zero);

    connectivityStream.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => healthSyncService.despacharLinhasPendentes(any()));
    expect(controller.value.pendentesNaFila, 0);
  });

  group('ultimaSincronizacaoLabel (i18n)', () {
    test('hoje', () {
      final agora = DateTime.now();
      final quando = DateTime(agora.year, agora.month, agora.day, 8, 30);
      final state = SyncUiState(ultimaSincronizacaoEm: quando);

      expect(state.ultimaSincronizacaoLabel(), 'Última atualização: Hoje às 08:30');
    });

    test('ontem', () {
      final hoje = DateTime.now();
      final ontem = DateTime(hoje.year, hoje.month, hoje.day)
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 8, minutes: 30));
      final state = SyncUiState(ultimaSincronizacaoEm: ontem);

      expect(state.ultimaSincronizacaoLabel(), 'Última atualização: Ontem às 08:30');
    });

    test('data anterior a ontem inclui dia e mês', () {
      final referencia = DateTime.now().subtract(const Duration(days: 5));
      final quando = DateTime(
        referencia.year,
        referencia.month,
        referencia.day,
        8,
        30,
      );
      final dia = quando.day.toString().padLeft(2, '0');
      final mes = quando.month.toString().padLeft(2, '0');
      final state = SyncUiState(ultimaSincronizacaoEm: quando);

      expect(
        state.ultimaSincronizacaoLabel(),
        'Última atualização: $dia/$mes às 08:30',
      );
    });

    test('nunca sincronizado', () {
      const state = SyncUiState();

      expect(state.ultimaSincronizacaoLabel(), 'Ainda não sincronizado');
    });
  });
}
