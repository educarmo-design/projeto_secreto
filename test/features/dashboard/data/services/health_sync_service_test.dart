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

/// Encadeamento falso de `.select('altura_cm').eq('id', usuarioId).maybeSingle()`
/// — usado só por [HealthSyncService._buscarAlturaMetros] (inferência de
/// IMC). Duas classes, uma por etapa do builder real (mesmo padrão de
/// [_FakeFilterBuilder] acima, só que .eq() precisa devolver algo
/// encadeável e .maybeSingle() troca de tipo — `PostgrestFilterBuilder` ->
/// `PostgrestTransformBuilder`).
class _FakeAlturaFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeAlturaFilterBuilder(this._resultado);
  final Map<String, dynamic>? _resultado;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) => this as PostgrestFilterBuilder<List<Map<String, dynamic>>>;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _FakeAlturaTransformBuilder(_resultado);
}

class _FakeAlturaTransformBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _FakeAlturaTransformBuilder(this._resultado);
  final Map<String, dynamic>? _resultado;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(Map<String, dynamic>? value) onValue, {
    Function? onError,
  }) => Future.value(_resultado).then(onValue, onError: onError);
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
  late _MockSupabaseQueryBuilder perfisBuilder;
  late FakeSecureStorage secureStorage;
  late HealthSyncService service;

  /// Altura cadastrada em `perfis_usuarios.altura_cm` que o mock devolve —
  /// `null` por padrão (mesma situação da maioria dos usuários hoje: coluna
  /// nova, sem UI de preenchimento ainda). Testes de IMC-por-inferência
  /// chamam de novo com um valor real.
  void stubAltura(double? alturaCm) {
    // thenAnswer, não thenReturn: _FakeAlturaFilterBuilder implementa Future
    // (via .then(), mesmo truque de _FakeFilterBuilder) — mocktail recusa
    // thenReturn com um valor Future-like (mesma pegadinha já documentada
    // em stubUpsertMetricas acima, mas essa é síncrona então não tinha
    // batido nela até agora).
    when(() => perfisBuilder.select(any())).thenAnswer(
      (_) => _FakeAlturaFilterBuilder(
        alturaCm == null ? null : {'altura_cm': alturaCm},
      ),
    );
  }

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
    perfisBuilder = _MockSupabaseQueryBuilder();
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

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('metricas_saude_diarias')).thenAnswer((_) => metricasBuilder);
    when(() => supabase.from('eventos_anomalias_saude')).thenAnswer((_) => anomaliasBuilder);
    when(() => anomaliasBuilder.insert(any()))
        .thenAnswer((_) => _FakeFilterBuilder<dynamic>(Future.value(const <Map<String, dynamic>>[])));
    stubUpsertMetricas(() => Future.value(const <Map<String, dynamic>>[]));

    // Inferência cruzada de IMC (RELATÓRIO 20260811130000) — padrão "sem
    // altura cadastrada" pra não afetar os testes que não são sobre isso;
    // testes específicos chamam stubAltura(valor) para sobrescrever.
    when(() => supabase.from('perfis_usuarios')).thenAnswer((_) => perfisBuilder);
    stubAltura(null);

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

    test('passos: fica com a MAIOR fonte do dia, não a soma de celular+relógio', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          // Celular e relógio ambos tentando cobrir o dia inteiro — o
          // total certo é 4200 (o maior), NUNCA 4200+3900=8100 (a soma).
          // CORRIGIDO NESTA TAREFA — ver RELATÓRIO 20260811.
          _ponto(
            type: HealthDataType.STEPS,
            value: 4200,
            dateFrom: hoje,
            sourceName: 'Garmin Connect',
          ),
          _ponto(
            type: HealthDataType.STEPS,
            value: 3900,
            dateFrom: hoje,
            sourceName: 'Health Connect',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['passos'], 4200);
    });

    test('mescla fc (mÃ©dia) e fc_repouso do mesmo dia em uma Ãºnica linha e sincroniza', () async {
      final hoje = DateTime(2026, 7, 8, 10);
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
          // NA TAREFA ANTERIOR — ver RELATÓRIO 20260810.
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

    test('sono: soma leve+profundo+rem no total, EXCLUI acordado, bucketiza pela manhã do despertar', () async {
      // Sessão de sono que começa às 23h de 8/jul e termina de manhã em
      // 9/jul — TODOS os estágios devem cair no dia 9/jul (a manhã em que
      // a pessoa acordou), mesmo o estágio que começa antes da meia-noite.
      final inicioNoite = DateTime(2026, 7, 8, 23); // 23h de 8/jul
      final madrugada = DateTime(2026, 7, 9, 1); // 1h de 9/jul (mesma noite)

      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        // dateTo obrigatório aqui: o pacote `health` recalcula o `value` de
        // tipos de estágio de sono a partir de (dateTo - dateFrom) em
        // minutos, no PRÓPRIO construtor de HealthDataPoint — ignora
        // qualquer NumericHealthValue passado (ver health_data_point.dart,
        // _convertMinutes()). Sem dateTo explícito, dateTo==dateFrom e todo
        // valor sai 0.
        (_) async => [
          _ponto(
            type: HealthDataType.SLEEP_LIGHT,
            value: 0,
            dateFrom: inicioNoite,
            dateTo: inicioNoite.add(const Duration(minutes: 200)),
          ),
          _ponto(
            type: HealthDataType.SLEEP_DEEP,
            value: 0,
            dateFrom: madrugada,
            dateTo: madrugada.add(const Duration(minutes: 90)),
          ),
          _ponto(
            type: HealthDataType.SLEEP_REM,
            value: 0,
            dateFrom: madrugada,
            dateTo: madrugada.add(const Duration(minutes: 60)),
          ),
          _ponto(
            type: HealthDataType.SLEEP_AWAKE,
            value: 0,
            dateFrom: madrugada,
            dateTo: madrugada.add(const Duration(minutes: 15)),
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas, hasLength(1));
      final linha = resultado.linhas.single;
      expect(linha['data_referencia'], '2026-07-09',
          reason: 'estágio de 23h de 8/jul deve bucketizar para a manhã de 9/jul, não para 8/jul');
      expect(linha['sono_leve_minutos'], 200);
      expect(linha['sono_profundo_minutos'], 90);
      expect(linha['sono_rem_minutos'], 60);
      expect(linha['sono_acordado_minutos'], 15);
      expect(linha['minutos_sono'], 350, reason: '200+90+60, SEM os 15min de acordado');
    });

    test('SLEEP_ASLEEP (fallback sem estágio granular) soma para sono_leve_minutos', () async {
      final hoje = DateTime(2026, 7, 8, 10); // antes das 15h: fica no próprio dia
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.SLEEP_ASLEEP,
            value: 0,
            dateFrom: hoje,
            dateTo: hoje.add(const Duration(minutes: 300)),
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['sono_leve_minutos'], 300);
      expect(linha['minutos_sono'], 300);
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

  group('leitura crua alinhada ao fuso local (RELATÓRIO 20260811)', () {
    // Trava a causa raiz do bug "passos/sono com corte em UTC": a consulta
    // agregada nativa (getHealthIntervalDataFromTypes) foi abandonada por
    // completo — todo tipo, incluindo STEPS/ACTIVE_ENERGY_BURNED/estágios
    // de sono, volta a sair por getHealthDataFromTypes (leitura crua), com
    // a janela alinhada à meia-noite LOCAL, não a um instante qualquer.
    test('nunca chama getHealthIntervalDataFromTypes (método abandonado)', () async {
      await service.sincronizarDeltaDiario();

      verifyNever(
        () => health.getHealthIntervalDataFromTypes(
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          types: any(named: 'types'),
          interval: any(named: 'interval'),
        ),
      );
    });

    test('SLEEP_SESSION nunca é pedida pela sincronização automática (só lerSonoRecente pede, sob demanda)', () async {
      await service.sincronizarDeltaDiario();

      final tipos = verify(
        () => health.getHealthDataFromTypes(
          types: captureAny(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured.single as List<HealthDataType>;

      expect(tipos, isNot(contains(HealthDataType.SLEEP_SESSION)));
      expect(tipos, containsAll([
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_ASLEEP,
      ]));
    });

    test('janela de início é a meia-noite LOCAL do dia, não um instante do meio do dia', () async {
      // Cursor de última sincronização às 14h32 de um dia — a consulta ao
      // Health Connect deve começar às 00:00:00 desse MESMO dia, não às
      // 14h32 (senão passos da manhã, antes do cursor, ficariam de fora
      // da janela — e, mais grave, uma consulta não alinhada à meia-noite
      // é o que causava o corte incorreto em fuso pela API agregada).
      final cursorMeioDoDia = DateTime(2026, 7, 8, 14, 32);
      await secureStorage.write(
        key: 'last_sync_timestamp',
        value: cursorMeioDoDia.toIso8601String(),
      );

      await service.sincronizarDeltaDiario();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: captureAny(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;
      final startTime = captured.single as DateTime;

      expect(startTime, DateTime(2026, 7, 8));
      expect(startTime.hour, 0);
      expect(startTime.minute, 0);
    });
  });

  group('fc_maxima e balança (RELATÓRIO 20260811130000 — restrição F02: só valores absolutos, sem anomalia)', () {
    final hoje = DateTime(2026, 7, 8, 10);

    test('fc_maxima: fica com o MAIOR valor bruto de HEART_RATE do dia, não um limite/evento', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.HEART_RATE, value: 70, dateFrom: hoje),
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 155,
            dateFrom: hoje.add(const Duration(hours: 1)),
          ),
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 90,
            dateFrom: hoje.add(const Duration(hours: 2)),
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['frequencia_cardiaca'], 105); // média (70+155+90)/3, inalterada
      expect(linha['fc_maxima'], 155); // NOVO: só o maior valor bruto lido
    });

    test('agua_corporal: gravado a partir de BODY_WATER_MASS', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.BODY_WATER_MASS, value: 38.4, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['agua_corporal'], 38.4);
    });

    test('imc: quando Health Connect entrega BODY_MASS_INDEX pronto, usa direto e NÃO consulta a altura do perfil', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 70, dateFrom: hoje),
          _ponto(type: HealthDataType.BODY_MASS_INDEX, value: 23.5, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['imc'], 23.5);
      verifyNever(() => perfisBuilder.select(any()));
    });

    test('inferência cruzada: peso + percentual de gordura presentes, massa magra ausente → calcula massa magra', () async {
      // massaMagra = peso × (1 − percentual/100) = 80 × (1 − 25/100) = 60.0
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
          _ponto(type: HealthDataType.BODY_FAT_PERCENTAGE, value: 25, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['percentual_gordura'], 25);
      expect(linha['massa_magra_kg'], 60.0);
    });

    test('inferência cruzada: peso + massa magra presentes, percentual ausente → calcula percentual de gordura', () async {
      // percentual = (1 − massaMagra/peso) × 100 = (1 − 60/80) × 100 = 25.0
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
          _ponto(type: HealthDataType.LEAN_BODY_MASS, value: 60, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['massa_magra_kg'], 60);
      expect(linha['percentual_gordura'], 25.0);
    });

    test('imc: sem BODY_MASS_INDEX, mas com peso e altura cadastrada no perfil → infere peso/altura²', () async {
      // imc = 80 / 1.80² = 24.7 (arredondado a 1 casa)
      stubAltura(180);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['imc'], 24.7);
    });

    test('imc: sem BODY_MASS_INDEX e sem altura cadastrada no perfil → fica de fora, não é erro', () async {
      // stubAltura(null) já é o padrão do setUp — não recadastra nada aqui.
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      expect(resultado.linhas.single['imc'], isNull);
    });

    test('altura do perfil é buscada UMA única vez por sincronização, mesmo com vários dias precisando de IMC', () async {
      stubAltura(180);
      final ontem = hoje.subtract(const Duration(days: 1));
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
          _ponto(type: HealthDataType.WEIGHT, value: 79, dateFrom: ontem),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas, hasLength(2));
      expect(resultado.linhas.every((linha) => linha['imc'] != null), isTrue);
      verify(() => perfisBuilder.select(any())).called(1);
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
    test('lê 30 dias por padrão, mescla por dia e persiste via upsert', () async {
      final dia1 = DateTime(2026, 6, 10, 8);
      final dia2 = DateTime(2026, 7, 8, 9);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
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
      // RELATÓRIO 20260811: a janela é alinhada à meia-noite LOCAL do dia
      // 30 dias atrás, não a "agora menos 30 dias" cru (que teria a hora
      // atual, não meia-noite).
      final trintaDiasAtras = DateTime.now().subtract(const Duration(days: 30));
      final meiaNoiteEsperada =
          DateTime(trintaDiasAtras.year, trintaDiasAtras.month, trintaDiasAtras.day);

      await service.carregarHistoricoInicial();

      final captured = verify(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: captureAny(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).captured;
      final startTime = captured.single as DateTime;

      expect(startTime, meiaNoiteEsperada);
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
