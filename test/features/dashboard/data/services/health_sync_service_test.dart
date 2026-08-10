import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/services/health_sync_service.dart';

import '../../../../support/fake_secure_storage.dart';

class _MockHealth extends Mock implements Health {}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Stands in for whatever [SupabaseQueryBuilder.insert]/`.upsert` returns
/// (`PostgrestFilterBuilder<dynamic>`, itself `implements Future`). `await`
/// on a Future-like object resolves through `.then` alone, so forwarding
/// just that method to a real, controllable [Future] is enough to drive
/// every success/offline/error path without a live Postgrest response.
class _FakeFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  _FakeFilterBuilder(this._future);
  final Future<T> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
}

const _usuarioId = 'user-123';
const _usuarioAutenticado = User(
  id: _usuarioId,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

HealthDataPoint _ponto({
  required HealthDataType type,
  required num value,
  required DateTime dateFrom,
  DateTime? dateTo,
  String sourceName = 'TestWearable',
}) {
  return HealthDataPoint(
    uuid: 'uuid-${type.name}-${dateFrom.microsecondsSinceEpoch}',
    value: NumericHealthValue(numericValue: value),
    type: type,
    unit: HealthDataUnit.NO_UNIT,
    dateFrom: dateFrom,
    dateTo: dateTo ?? dateFrom,
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'device-1',
    sourceId: 'source-1',
    sourceName: sourceName,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(<HealthDataType>[]);
    registerFallbackValue(HealthDataType.STEPS);
    registerFallbackValue(DateTime(2024));
    i18n.initialize('pt');
  });

  late _MockHealth health;
  late _MockSupabaseClient supabase;
  late _MockGoTrueClient auth;
  late _MockSupabaseQueryBuilder metricasBuilder;
  late _MockSupabaseQueryBuilder anomaliasBuilder;
  late FakeSecureStorage secureStorage;
  late HealthSyncService service;

  // Takes a factory rather than a ready-made Future: an already-constructed
  // `Future.error(...)` sitting unconsumed across the several intervening
  // `await`s before `_enviarLinhas` reaches it would trip Dart's unhandled-
  // error zone reporting. Building it lazily, at the moment `upsert` is
  // actually invoked, means `then()` attaches in the same synchronous
  // continuation as the `await` that consumes it.
  void stubUpsertMetricas(Future<dynamic> Function() resultado) {
    when(
      () => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')),
    ).thenAnswer((_) => _FakeFilterBuilder<dynamic>(resultado()));
  }

  setUp(() {
    health = _MockHealth();
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    metricasBuilder = _MockSupabaseQueryBuilder();
    anomaliasBuilder = _MockSupabaseQueryBuilder();
    secureStorage = FakeSecureStorage();

    when(() => health.configure()).thenAnswer((_) async {});
    // N18 (READ_HEALTH_DATA_HISTORY) — só carregarHistoricoInicial chama;
    // padrão "já autorizado" pra não precisar re-stubar em todo teste que
    // não é sobre essa permissão especificamente (ver grupo dedicado).
    when(() => health.isHealthDataHistoryAuthorized()).thenAnswer((_) async => true);
    when(() => health.requestHealthDataHistoryAuthorization()).thenAnswer((_) async => true);
    when(() => health.isDataTypeAvailable(any())).thenReturn(true);
    when(
      () => health.hasPermissions(any(), permissions: any(named: 'permissions')),
    ).thenAnswer((_) async => true);
    when(
      () => health.getHealthDataFromTypes(
        types: any(named: 'types'),
        startTime: any(named: 'startTime'),
        endTime: any(named: 'endTime'),
      ),
    ).thenAnswer((_) async => <HealthDataPoint>[]);
    // Passos/calorias ativas/sono (SLEEP_ASLEEP) saem por aqui agora — ver
    // HealthSyncService._tiposComAgregadoNativo (RELATÓRIO 20260810).
    when(
      () => health.getHealthIntervalDataFromTypes(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        types: any(named: 'types'),
        interval: any(named: 'interval'),
      ),
    ).thenAnswer((_) async => <HealthDataPoint>[]);

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('metricas_saude_diarias')).thenAnswer((_) => metricasBuilder);
    when(() => supabase.from('eventos_anomalias_saude')).thenAnswer((_) => anomaliasBuilder);
    when(() => anomaliasBuilder.insert(any()))
        .thenAnswer((_) => _FakeFilterBuilder<dynamic>(Future.value(const <Map<String, dynamic>>[])));
    stubUpsertMetricas(() => Future.value(const <Map<String, dynamic>>[]));

    service = HealthSyncService(
      health: health,
      supabaseClient: supabase,
      secureStorage: secureStorage,
    );
  });

  group('sincronizarDeltaDiario', () {
    test('sem usuÃ¡rio autenticado retorna erro sem tocar no health store', () async {
      when(() => auth.currentUser).thenReturn(null);

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.erro);
      verifyNever(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      );
    });

    test('permissÃ£o negada retorna permissaoNegada e nÃ£o escreve nada', () async {
      when(
        () => health.hasPermissions(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);
      when(
        () => health.requestAuthorization(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.permissaoNegada);
      verifyNever(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')));
      expect(await service.obterUltimaSincronizacao(), isNull);
    });

    test('sem pontos novos retorna semAlteracoes e ainda assim avanÃ§a o cursor', () async {
      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.semAlteracoes);
      expect(resultado.sincronizadoEm, isNotNull);
      expect(await service.obterUltimaSincronizacao(), resultado.sincronizadoEm);
      verifyNever(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')));
    });

    test('mescla passos (agregado), fc (mÃ©dia) e fc_repouso do mesmo dia em uma Ãºnica linha e sincroniza', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      // Passos: vem de UM ponto só do agregado nativo (Health Connect já
      // fundiu as fontes do lado do SO) — não é mais soma de vários
      // registros brutos (ver RELATÓRIO 20260810).
      when(
        () => health.getHealthIntervalDataFromTypes(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          types: any(named: 'types'),
          interval: any(named: 'interval'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.STEPS, value: 4200, dateFrom: hoje),
        ],
      );
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          // FC genérica: 3 leituras no dia — vira MÉDIA aritmética
          // ((70+80+90)/3 = 80), não a última (que seria 90). CORRIGIDO
          // NESTA TAREFA — ver RELATÓRIO.
          _ponto(type: HealthDataType.HEART_RATE, value: 70, dateFrom: hoje),
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 80,
            dateFrom: hoje.add(const Duration(hours: 1)),
          ),
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 90,
            dateFrom: hoje.add(const Duration(hours: 2)),
          ),
          // RESTING_HEART_RATE segue "última leitura" — não mudou nesta
          // tarefa (fundador confirmou fc_repouso correto no teste físico).
          _ponto(
            type: HealthDataType.RESTING_HEART_RATE,
            value: 58,
            dateFrom: hoje,
          ),
          _ponto(
            type: HealthDataType.LEAN_BODY_MASS,
            value: 62.5,
            dateFrom: hoje,
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      expect(resultado.linhas, hasLength(1));
      final linha = resultado.linhas.single;
      expect(linha['usuario_id_anonimo'], _usuarioId);
      expect(linha['passos'], 4200);
      expect(linha['frequencia_cardiaca'], 80);
      expect(linha['fc_repouso'], 58);
      expect(linha['massa_magra_kg'], 62.5);
      verify(
        () => metricasBuilder.upsert(
          resultado.linhas,
          onConflict: 'usuario_id_anonimo,data_referencia',
        ),
      ).called(1);
      expect(await service.obterUltimaSincronizacao(), resultado.sincronizadoEm);
    });

    group('Caixa Preta â€” detecÃ§Ã£o de anomalias', () {
      test(
        'FC > 150 fora de treino Ã© isolada e gravada em eventos_anomalias_saude com severidade atencao',
        () async {
          final agora = DateTime(2026, 7, 8, 9, 30);
          when(
            () => health.getHealthDataFromTypes(
              types: any(named: 'types'),
              startTime: any(named: 'startTime'),
              endTime: any(named: 'endTime'),
            ),
          ).thenAnswer(
            (_) async => [
              _ponto(type: HealthDataType.HEART_RATE, value: 155, dateFrom: agora),
            ],
          );

          await service.sincronizarDeltaDiario();

          final captura = verify(() => anomaliasBuilder.insert(captureAny())).captured;
          expect(captura, hasLength(1));
          final eventos = captura.single as List<Map<String, dynamic>>;
          expect(eventos, hasLength(1));
          expect(eventos.single['usuario_id_anonimo'], _usuarioId);
          expect(eventos.single['parametro'], 'frequencia_cardiaca');
          expect(eventos.single['valor_detectado'], 155);
          expect(eventos.single['em_treino'], false);
          expect(eventos.single['severidade'], 'atencao');
          expect(eventos.single['detectado_em'], agora.toIso8601String());
        },
      );

      test('FC acima do limite crÃ­tico (>160) fora de treino Ã© severidade critico', () async {
        final agora = DateTime(2026, 7, 8, 9, 30);
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            _ponto(type: HealthDataType.HEART_RATE, value: 165, dateFrom: agora),
          ],
        );

        await service.sincronizarDeltaDiario();

        final captura = verify(() => anomaliasBuilder.insert(captureAny())).captured;
        final eventos = captura.single as List<Map<String, dynamic>>;
        expect(eventos.single['severidade'], 'critico');
      });

      test('FC elevada durante um treino ativo nÃ£o Ã© tratada como anomalia', () async {
        final inicioTreino = DateTime(2026, 7, 8, 9);
        final fimTreino = DateTime(2026, 7, 8, 10);
        final duranteOTreino = DateTime(2026, 7, 8, 9, 30);

        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            HealthDataPoint(
              uuid: 'workout-1',
              value: NumericHealthValue(numericValue: 0),
              type: HealthDataType.WORKOUT,
              unit: HealthDataUnit.NO_UNIT,
              dateFrom: inicioTreino,
              dateTo: fimTreino,
              sourcePlatform: HealthPlatformType.googleHealthConnect,
              sourceDeviceId: 'device-1',
              sourceId: 'source-1',
              sourceName: 'TestWearable',
            ),
            _ponto(type: HealthDataType.HEART_RATE, value: 155, dateFrom: duranteOTreino),
          ],
        );

        await service.sincronizarDeltaDiario();

        verifyNever(() => anomaliasBuilder.insert(any()));
      });

      test('FC dentro da faixa normal fora de treino nÃ£o gera anomalia', () async {
        final agora = DateTime(2026, 7, 8, 9, 30);
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            _ponto(type: HealthDataType.HEART_RATE, value: 72, dateFrom: agora),
          ],
        );

        await service.sincronizarDeltaDiario();

        verifyNever(() => anomaliasBuilder.insert(any()));
      });
    });

    test('upsert offline (SocketException) devolve as linhas sem avanÃ§ar o cursor', () async {
      final agora = DateTime(2026, 7, 8, 9, 30);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        // WEIGHT (não STEPS): este teste só precisa de QUALQUER ponto não
        // vazio no caminho cru — STEPS agora sai pelo agregado (ver
        // RELATÓRIO 20260810), então usar STEPS aqui não testaria nada.
        (_) async => [_ponto(type: HealthDataType.WEIGHT, value: 70, dateFrom: agora)],
      );
      stubUpsertMetricas(() => Future<dynamic>.error(const SocketException('sem rede')));

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.offline);
      expect(resultado.linhas, isNotEmpty);
      expect(await service.obterUltimaSincronizacao(), isNull);
    });

    test('falha do Postgrest no upsert retorna erro sem avanÃ§ar o cursor', () async {
      final agora = DateTime(2026, 7, 8, 9, 30);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.WEIGHT, value: 70, dateFrom: agora)],
      );
      stubUpsertMetricas(
        () => Future<dynamic>.error(const PostgrestException(message: 'RLS negou')),
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.erro);
      expect(await service.obterUltimaSincronizacao(), isNull);
    });
  });

  group('divisão agregado nativo vs. leitura crua (RELATÓRIO 20260810)', () {
    // Trava a causa raiz dos bugs de passos/calorias/sono duplicados: os 3
    // tipos com agregado nativo do Health Connect saem por
    // getHealthIntervalDataFromTypes, nunca por getHealthDataFromTypes
    // (que soma registro por registro e pode contar em dobro entre
    // fontes). Os demais tipos seguem no caminho cru de sempre.
    test('STEPS/ACTIVE_ENERGY_BURNED/SLEEP_ASLEEP vão só para getHealthIntervalDataFromTypes', () async {
      await service.sincronizarDeltaDiario();

      final tiposAgregados = verify(
        () => health.getHealthIntervalDataFromTypes(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          types: captureAny(named: 'types'),
          interval: any(named: 'interval'),
        ),
      ).captured.single as List<HealthDataType>;

      expect(tiposAgregados, containsAll([
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.SLEEP_ASLEEP,
      ]));

      final tiposCrus = verify(
        () => health.getHealthDataFromTypes(
          types: captureAny(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured.single as List<HealthDataType>;

      expect(tiposCrus, isNot(contains(HealthDataType.STEPS)));
      expect(tiposCrus, isNot(contains(HealthDataType.ACTIVE_ENERGY_BURNED)));
      expect(tiposCrus, isNot(contains(HealthDataType.SLEEP_ASLEEP)));
      expect(tiposCrus, contains(HealthDataType.HEART_RATE));
    });

    test('SLEEP_SESSION nunca é pedida pela sincronização automática (só lerSonoRecente pede, sob demanda)', () async {
      await service.sincronizarDeltaDiario();

      final tiposCrus = verify(
        () => health.getHealthDataFromTypes(
          types: captureAny(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured.single as List<HealthDataType>;
      final tiposAgregados = verify(
        () => health.getHealthIntervalDataFromTypes(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          types: captureAny(named: 'types'),
          interval: any(named: 'interval'),
        ),
      ).captured.single as List<HealthDataType>;

      expect(tiposCrus, isNot(contains(HealthDataType.SLEEP_SESSION)));
      expect(tiposAgregados, isNot(contains(HealthDataType.SLEEP_SESSION)));
    });

    test('intervalo do agregado é exatamente 1 dia (86400s)', () async {
      await service.sincronizarDeltaDiario();

      final captured = verify(
        () => health.getHealthIntervalDataFromTypes(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          types: any(named: 'types'),
          interval: captureAny(named: 'interval'),
        ),
      ).captured;

      expect(captured.single, 24 * 60 * 60);
    });
  });

  group('carregarHistoricoInicial (N18 — Carga Inicial)', () {
    // BUG CORRIGIDO NESTA TAREFA: antes, este método só lia o Health Connect
    // e devolvia os pontos crus — nunca chamava upsert. Estes testes
    // travam o comportamento novo (persiste igual a sincronizarDeltaDiario)
    // para não regredir de novo.

    // CAUSA RAIZ do bug "só 2 dias" (RELATÓRIO 20260809): READ_HEALTH_DATA_HISTORY
    // é uma permissão separada das READ_* normais — sem pedi-la, o Health
    // Connect só devolve dado gravado depois da concessão original, não os
    // `dias` pedidos aqui. Estes 3 testes travam o pedido dessa permissão.
    test('pede READ_HEALTH_DATA_HISTORY quando ainda não autorizado', () async {
      when(() => health.isHealthDataHistoryAuthorized()).thenAnswer((_) async => false);

      await service.carregarHistoricoInicial();

      verify(() => health.requestHealthDataHistoryAuthorization()).called(1);
    });

    test('não pede de novo quando já autorizado', () async {
      when(() => health.isHealthDataHistoryAuthorized()).thenAnswer((_) async => true);

      await service.carregarHistoricoInicial();

      verifyNever(() => health.requestHealthDataHistoryAuthorization());
    });

    test('sincronizarDeltaDiario nunca pede READ_HEALTH_DATA_HISTORY — só a Carga Inicial precisa', () async {
      await service.sincronizarDeltaDiario();

      verifyNever(() => health.isHealthDataHistoryAuthorized());
      verifyNever(() => health.requestHealthDataHistoryAuthorization());
    });

    test('negação da permissão de histórico não impede a leitura/gravação (best-effort)', () async {
      when(() => health.isHealthDataHistoryAuthorized()).thenAnswer((_) async => false);
      when(() => health.requestHealthDataHistoryAuthorization()).thenAnswer((_) async => false);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.WEIGHT, value: 70, dateFrom: DateTime(2026, 7, 8))],
      );

      final resultado = await service.carregarHistoricoInicial();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      verify(
        () => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')),
      ).called(1);
    });
    test('lê 30 dias por padrão, mescla por dia (passos via agregado) e persiste via upsert', () async {
      final dia1 = DateTime(2026, 6, 10, 8);
      final dia2 = DateTime(2026, 7, 8, 9);
      when(
        () => health.getHealthIntervalDataFromTypes(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          types: any(named: 'types'),
          interval: any(named: 'interval'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.STEPS, value: 2000, dateFrom: dia1),
          _ponto(type: HealthDataType.STEPS, value: 5000, dateFrom: dia2),
        ],
      );

      final resultado = await service.carregarHistoricoInicial();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      expect(resultado.linhas, hasLength(2));
      verify(
        () => metricasBuilder.upsert(
          resultado.linhas,
          onConflict: 'usuario_id_anonimo,data_referencia',
        ),
      ).called(1);
      expect(await service.obterUltimaSincronizacao(), resultado.sincronizadoEm);
    });

    test('janela padrão de leitura são os últimos 30 dias', () async {
      final antes = DateTime.now().subtract(const Duration(days: 30));

      await service.carregarHistoricoInicial();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: captureAny(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;
      final startTime = captured.single as DateTime;

      expect(startTime.isAfter(antes.subtract(const Duration(seconds: 5))), isTrue);
      expect(startTime.isBefore(DateTime.now()), isTrue);
    });

    test('permissão negada não escreve nada e devolve permissaoNegada', () async {
      when(
        () => health.hasPermissions(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);
      when(
        () => health.requestAuthorization(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);

      final resultado = await service.carregarHistoricoInicial();

      expect(resultado.outcome, DeltaSyncOutcome.permissaoNegada);
      verifyNever(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')));
    });

    test('upsert offline devolve as linhas sem avançar o cursor (mesma resiliência do delta)', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.WEIGHT, value: 70, dateFrom: DateTime(2026, 7, 1))],
      );
      stubUpsertMetricas(() => Future<dynamic>.error(const SocketException('sem rede')));

      final resultado = await service.carregarHistoricoInicial();

      expect(resultado.outcome, DeltaSyncOutcome.offline);
      expect(resultado.linhas, isNotEmpty);
      expect(await service.obterUltimaSincronizacao(), isNull);
    });

    test('sem pontos no período retorna semAlteracoes e avança o cursor', () async {
      final resultado = await service.carregarHistoricoInicial();

      expect(resultado.outcome, DeltaSyncOutcome.semAlteracoes);
      expect(await service.obterUltimaSincronizacao(), isNotNull);
      verifyNever(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')));
    });
  });

  group('despacharLinhasPendentes', () {
    test('lista vazia Ã© um no-op bem-sucedido', () async {
      final ok = await service.despacharLinhasPendentes(const []);

      expect(ok, isTrue);
      verifyNever(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')));
    });

    test('sucesso reenvia as linhas em fila e avanÃ§a o cursor', () async {
      final linhas = [
        {'usuario_id_anonimo': _usuarioId, 'data_referencia': '2026-07-07', 'passos': 1000},
      ];

      final ok = await service.despacharLinhasPendentes(linhas);

      expect(ok, isTrue);
      verify(
        () => metricasBuilder.upsert(linhas, onConflict: 'usuario_id_anonimo,data_referencia'),
      ).called(1);
      expect(await service.obterUltimaSincronizacao(), isNotNull);
    });

    test('falha ao reenviar mantÃ©m o cursor intacto', () async {
      stubUpsertMetricas(() => Future<dynamic>.error(const SocketException('sem rede')));
      final linhas = [
        {'usuario_id_anonimo': _usuarioId, 'data_referencia': '2026-07-07', 'passos': 1000},
      ];

      final ok = await service.despacharLinhasPendentes(linhas);

      expect(ok, isFalse);
      expect(await service.obterUltimaSincronizacao(), isNull);
    });
  });

  group('lerFrequenciaCardiacaRecente', () {
    test('pede só HEART_RATE ao health store, nunca os outros tipos', () async {
      await service.lerFrequenciaCardiacaRecente();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: captureAny(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;

      expect(captured.single, [HealthDataType.HEART_RATE]);
    });

    test('janela padrão é as últimas 24h a partir de agora', () async {
      final antes = DateTime.now().subtract(const Duration(hours: 24));

      await service.lerFrequenciaCardiacaRecente();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: captureAny(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;
      final startTime = captured.single as DateTime;

      expect(startTime.isAfter(antes.subtract(const Duration(seconds: 5))), isTrue);
      expect(startTime.isBefore(DateTime.now()), isTrue);
    });

    test('permissão negada devolve granted=false sem pontos', () async {
      when(
        () => health.hasPermissions(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);
      when(
        () => health.requestAuthorization(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);

      final resultado = await service.lerFrequenciaCardiacaRecente();

      expect(resultado.granted, isFalse);
      expect(resultado.points, isEmpty);
    });

    test('sem registro na janela devolve points vazio', () async {
      final resultado = await service.lerFrequenciaCardiacaRecente();

      expect(resultado.granted, isTrue);
      expect(resultado.points, isEmpty);
      expect(HealthSyncService.ultimaLeituraOuNula(resultado.points), isNull);
    });
  });

  group('lerPesoRecente', () {
    test('pede só WEIGHT ao health store, nunca os outros tipos', () async {
      await service.lerPesoRecente();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: captureAny(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;

      expect(captured.single, [HealthDataType.WEIGHT]);
    });

    test('janela padrão são os últimos 30 dias a partir de agora', () async {
      final antes = DateTime.now().subtract(const Duration(days: 30));

      await service.lerPesoRecente();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: captureAny(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;
      final startTime = captured.single as DateTime;

      expect(startTime.isAfter(antes.subtract(const Duration(seconds: 5))), isTrue);
      expect(startTime.isBefore(DateTime.now()), isTrue);
    });

    test('permissão negada devolve granted=false sem pontos', () async {
      when(
        () => health.hasPermissions(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);
      when(
        () => health.requestAuthorization(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);

      final resultado = await service.lerPesoRecente();

      expect(resultado.granted, isFalse);
      expect(resultado.points, isEmpty);
    });

    test('sem registro na janela devolve points vazio', () async {
      final resultado = await service.lerPesoRecente();

      expect(resultado.granted, isTrue);
      expect(resultado.points, isEmpty);
      expect(HealthSyncService.ultimaLeituraOuNula(resultado.points), isNull);
    });

    test('nível de permissão pedido é READ, nunca READ_WRITE', () async {
      await service.lerPesoRecente();

      final captured = verify(
        () => health.hasPermissions(
          any(),
          permissions: captureAny(named: 'permissions'),
        ),
      ).captured;

      final permissoes = captured.single as List<HealthDataAccess>;
      expect(permissoes, everyElement(HealthDataAccess.READ));
    });
  });

  group('lerSonoRecente', () {
    test('pede só SLEEP_SESSION ao health store, nunca os outros tipos', () async {
      await service.lerSonoRecente();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: captureAny(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;

      expect(captured.single, [HealthDataType.SLEEP_SESSION]);
    });

    test('janela padrão são os últimos 7 dias a partir de agora', () async {
      final antes = DateTime.now().subtract(const Duration(days: 7));

      await service.lerSonoRecente();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: captureAny(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;
      final startTime = captured.single as DateTime;

      expect(startTime.isAfter(antes.subtract(const Duration(seconds: 5))), isTrue);
      expect(startTime.isBefore(DateTime.now()), isTrue);
    });

    test('permissão negada devolve granted=false sem pontos', () async {
      when(
        () => health.hasPermissions(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);
      when(
        () => health.requestAuthorization(any(), permissions: any(named: 'permissions')),
      ).thenAnswer((_) async => false);

      final resultado = await service.lerSonoRecente();

      expect(resultado.granted, isFalse);
      expect(resultado.points, isEmpty);
    });

    test('devolve múltiplas sessões de sono na janela, não só a mais recente', () async {
      final noite1 = DateTime(2026, 7, 8, 23);
      final noite2 = DateTime(2026, 7, 9, 22, 30);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.SLEEP_SESSION,
            value: 0,
            dateFrom: noite1,
            dateTo: noite1.add(const Duration(hours: 7)),
          ),
          _ponto(
            type: HealthDataType.SLEEP_SESSION,
            value: 0,
            dateFrom: noite2,
            dateTo: noite2.add(const Duration(hours: 6, minutes: 45)),
          ),
        ],
      );

      final resultado = await service.lerSonoRecente();

      expect(resultado.granted, isTrue);
      expect(resultado.points, hasLength(2));
    });

    test('sem registro na janela devolve points vazio', () async {
      final resultado = await service.lerSonoRecente();

      expect(resultado.granted, isTrue);
      expect(resultado.points, isEmpty);
    });

    test('nível de permissão pedido é READ, nunca READ_WRITE', () async {
      await service.lerSonoRecente();

      final captured = verify(
        () => health.hasPermissions(
          any(),
          permissions: captureAny(named: 'permissions'),
        ),
      ).captured;

      final permissoes = captured.single as List<HealthDataAccess>;
      expect(permissoes, everyElement(HealthDataAccess.READ));
    });
  });

  group('HealthSyncService.ultimaLeituraOuNula', () {
    test('devolve o ponto com dateTo mais tardio, não o último da lista', () {
      final antigo = HealthMetricPoint(
        type: HealthDataType.HEART_RATE,
        value: 60,
        unit: 'bpm',
        dateFrom: DateTime(2026, 7, 8, 8),
        dateTo: DateTime(2026, 7, 8, 8),
        sourceApp: 'Garmin Connect',
      );
      final recente = HealthMetricPoint(
        type: HealthDataType.HEART_RATE,
        value: 72,
        unit: 'bpm',
        dateFrom: DateTime(2026, 7, 8, 14),
        dateTo: DateTime(2026, 7, 8, 14),
        sourceApp: 'Garmin Connect',
      );

      // Lista fora de ordem cronológica de propósito — a janela do Health
      // Connect não garante ordenação.
      final ultima =
          HealthSyncService.ultimaLeituraOuNula([recente, antigo]);

      expect(ultima, same(recente));
    });

    test('lista vazia devolve null', () {
      expect(HealthSyncService.ultimaLeituraOuNula(const []), isNull);
    });
  });

  group('nível de permissão pedido ao health store', () {
    test(
      'pede só READ, nunca READ_WRITE — o serviço nunca escreve no health store',
      () async {
        await service.lerFrequenciaCardiacaRecente();

        final captured = verify(
          () => health.hasPermissions(
            any(),
            permissions: captureAny(named: 'permissions'),
          ),
        ).captured;

        final permissoes = captured.single as List<HealthDataAccess>;
        expect(permissoes, everyElement(HealthDataAccess.READ));
      },
    );

    test('mesmo em carregarHistoricoInicial (todos os tipos) o nível é READ', () async {
      await service.carregarHistoricoInicial();

      final captured = verify(
        () => health.hasPermissions(
          any(),
          permissions: captureAny(named: 'permissions'),
        ),
      ).captured;

      final permissoes = captured.single as List<HealthDataAccess>;
      expect(permissoes, everyElement(HealthDataAccess.READ));
    });
  });
}
