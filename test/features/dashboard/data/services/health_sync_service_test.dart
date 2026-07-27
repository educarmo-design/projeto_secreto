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

    test('mescla passos e fc_repouso do mesmo dia em uma Ãºnica linha e sincroniza', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.STEPS, value: 3000, dateFrom: hoje),
          _ponto(
            type: HealthDataType.STEPS,
            value: 1200,
            dateFrom: hoje.add(const Duration(hours: 1)),
          ),
          _ponto(type: HealthDataType.HEART_RATE, value: 70, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      expect(resultado.linhas, hasLength(1));
      final linha = resultado.linhas.single;
      expect(linha['usuario_id_anonimo'], _usuarioId);
      expect(linha['passos'], 4200);
      expect(linha['fc_repouso'], 70);
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
          expect(eventos.single['parametro'], 'fc_repouso');
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
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 500, dateFrom: agora)],
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
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 500, dateFrom: agora)],
      );
      stubUpsertMetricas(
        () => Future<dynamic>.error(const PostgrestException(message: 'RLS negou')),
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.erro);
      expect(await service.obterUltimaSincronizacao(), isNull);
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
