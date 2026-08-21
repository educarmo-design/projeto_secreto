import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/core/config/app_config.dart';
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
  _FakeAlturaFilterBuilder(this._resultado, {this.erro});
  final Map<String, dynamic>? _resultado;
  // Não-nulo simula a consulta LANÇANDO (rede/RLS/timeout) — usado pelo
  // teste de resiliência do IMC (RELATÓRIO 20260810_0007): distingue de
  // `_resultado: null`, que simula "consulta funcionou, coluna vazia".
  final Object? erro;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) => this as PostgrestFilterBuilder<List<Map<String, dynamic>>>;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _FakeAlturaTransformBuilder(_resultado, erro: erro);
}

class _FakeAlturaTransformBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _FakeAlturaTransformBuilder(this._resultado, {this.erro});
  final Map<String, dynamic>? _resultado;
  final Object? erro;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(Map<String, dynamic>? value) onValue, {
    Function? onError,
  }) {
    // Lazy on purpose (mesmo motivo documentado em stubUpsertMetricas
    // acima): construir o Future de erro só aqui, dentro de then(), e
    // chamar .then(onValue, onError: onError) NELE — não devolver um
    // Future novo direto — é o que faz o protocolo "thenable" do `await`
    // de verdade invocar onError. Devolver só `Future.error(...)` sem
    // encadear nunca chama onError e trava o await pra sempre (bug real
    // encontrado escrevendo este teste).
    final erroLocal = erro;
    final future = erroLocal != null
        ? Future<Map<String, dynamic>?>.error(erroLocal)
        : Future.value(_resultado);
    return future.then(onValue, onError: onError);
  }
}

/// Encadeamento falso de `.upsert(linha, onConflict: ...).select('id').single()`
/// — usado só por [HealthSyncService._processarTreinos] pra descobrir o id
/// do treino recém-gravado (RELATÓRIO 20260811_0002). Três classes, uma por
/// etapa do builder real, mesmo padrão de [_FakeAlturaFilterBuilder]/
/// [_FakeAlturaTransformBuilder] acima.
class _FakeUpsertComSelectBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  _FakeUpsertComSelectBuilder(this._linhaResultado, {this.erro});
  final Map<String, dynamic>? _linhaResultado;
  final Object? erro;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> select([
    String columns = '*',
  ]) => _FakeSelectAposUpsert(_linhaResultado, erro: erro);
}

class _FakeSelectAposUpsert extends Fake
    implements PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  _FakeSelectAposUpsert(this._linhaResultado, {this.erro});
  final Map<String, dynamic>? _linhaResultado;
  final Object? erro;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() =>
      _FakeSingleAposUpsert(_linhaResultado, erro: erro);
}

class _FakeSingleAposUpsert extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>> {
  _FakeSingleAposUpsert(this._linhaResultado, {this.erro});
  final Map<String, dynamic>? _linhaResultado;
  final Object? erro;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(Map<String, dynamic> value) onValue, {
    Function? onError,
  }) {
    final erroLocal = erro;
    final future = erroLocal != null
        ? Future<Map<String, dynamic>>.error(erroLocal)
        : Future.value(_linhaResultado!);
    return future.then(onValue, onError: onError);
  }
}

/// Encadeamento falso de `.delete().eq('treino_id', treinoId)` — usado só
/// por [HealthSyncService._gravarRotaDoTreino] (limpa rotas antigas antes
/// de reinserir, idempotência pedida na tarefa 20260811_0002).
class _FakeRotasDeleteBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) => this;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) => Future.value(const <Map<String, dynamic>>[]).then(onValue, onError: onError);
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
  // Vazio por padrão de propósito: espelha o Android real
  // (HealthDataConverter.kt/HealthDataReader.kt SEMPRE mandam
  // source_id == "" — quem carrega o nome do pacote lá é source_name). A
  // maioria dos testes deste arquivo simula leitura via Health Connect, não
  // HealthKit — só os testes da Hierarquia de Fontes específicos de iOS
  // passam sourceId de verdade (bundle id). Ver doc de
  // HealthMetricPoint.identificadorFonte.
  String sourceId = '',
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
    sourceId: sourceId,
    sourceName: sourceName,
  );
}

/// Ponto WORKOUT cru — RELATÓRIO 20260811_0002. Diferente de [_ponto]:
/// carrega um `WorkoutHealthValue` de verdade (não um `NumericHealthValue`),
/// então `HealthMetricPoint.rawValue` tem o que `_processarTreinos` precisa.
HealthDataPoint _pontoTreino({
  required HealthWorkoutActivityType tipo,
  required DateTime dateFrom,
  required DateTime dateTo,
  int? totalEnergyBurned,
  int? totalDistance,
  int? totalSteps,
  String sourceName = 'TestWearable',
  String sourceId = '',
}) {
  return HealthDataPoint(
    uuid: 'uuid-workout-${dateFrom.microsecondsSinceEpoch}',
    value: WorkoutHealthValue(
      workoutActivityType: tipo,
      totalEnergyBurned: totalEnergyBurned,
      totalDistance: totalDistance,
      totalSteps: totalSteps,
    ),
    type: HealthDataType.WORKOUT,
    unit: HealthDataUnit.NO_UNIT,
    dateFrom: dateFrom,
    dateTo: dateTo,
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'device-1',
    sourceId: sourceId,
    sourceName: sourceName,
  );
}

/// Ponto WORKOUT_ROUTE cru — `locations: []` simula tanto "sem rota mesmo"
/// quanto `ExerciseRouteResult.ConsentRequired` do Android (achado real:
/// indistinguíveis do lado Dart, ver doc de
/// `HealthSyncService._gravarRotaDoTreino`).
HealthDataPoint _pontoRota({
  required DateTime dateFrom,
  required DateTime dateTo,
  List<WorkoutRouteLocation> locations = const [],
  String sourceName = 'TestWearable',
  String sourceId = '',
}) {
  return HealthDataPoint(
    uuid: 'uuid-route-${dateFrom.microsecondsSinceEpoch}',
    value: WorkoutRouteHealthValue(locations: locations),
    type: HealthDataType.WORKOUT_ROUTE,
    unit: HealthDataUnit.NO_UNIT,
    dateFrom: dateFrom,
    dateTo: dateTo,
    sourcePlatform: HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'device-1',
    sourceId: sourceId,
    sourceName: sourceName,
  );
}

/// Mesmo formato de `HealthSyncService._dataOnly` — usado só para indexar
/// `resultado.linhas` por dia em testes que precisam checar mais de uma
/// linha (a ordem de `linhas` não é garantida como "hoje antes de ontem").
String _dataIso(DateTime data) => data.toIso8601String().split('T').first;

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
  late _MockSupabaseQueryBuilder treinosBuilder;
  late _MockSupabaseQueryBuilder rotasBuilder;
  late FakeSecureStorage secureStorage;
  late HealthSyncService service;

  /// Id do treino que `.upsert(...).select('id').single()` devolve —
  /// RELATÓRIO 20260811_0002. `erro` não-nulo simula falha no upsert do
  /// treino (best-effort: não pode derrubar a sincronização principal).
  void stubUpsertTreino({String id = 'treino-1', Object? erro}) {
    when(
      () => treinosBuilder.upsert(any(), onConflict: any(named: 'onConflict')),
    ).thenAnswer(
      (_) => _FakeUpsertComSelectBuilder({'id': id}, erro: erro),
    );
  }

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
    treinosBuilder = _MockSupabaseQueryBuilder();
    rotasBuilder = _MockSupabaseQueryBuilder();
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

    // Treinos/Rotas (RELATÓRIO 20260811_0002) — padrão "sucesso", id
    // fixo 'treino-1', pra não afetar os testes que não são sobre isso;
    // nem entra em jogo em testes sem WORKOUT nos pontos (_processarTreinos
    // sai cedo se não houver nenhum).
    when(() => supabase.from('atividades_fisicas_treinos')).thenAnswer((_) => treinosBuilder);
    when(() => supabase.from('atividades_fisicas_rotas')).thenAnswer((_) => rotasBuilder);
    stubUpsertTreino();
    when(() => rotasBuilder.delete()).thenAnswer(
      (_) => _FakeRotasDeleteBuilder(),
    );
    when(() => rotasBuilder.insert(any()))
        .thenAnswer((_) => _FakeFilterBuilder<dynamic>(Future.value(const <Map<String, dynamic>>[])));

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

    test('distância: fica com a MAIOR fonte do dia, não a soma de celular+relógio (RELATÓRIO 20260810_0006)', () async {
      // BUG CONFIRMADO NO TESTE FÍSICO DO FUNDADOR: distancia_metros ainda
      // somava celular+relógio (double-counting), mesmo bug já corrigido
      // para passos numa tarefa anterior. Mesmo cenário de sourceName
      // duplicado, agora para DISTANCE_DELTA/DISTANCE_WALKING_RUNNING —
      // ambos mapeiam pro mesmo campo (HealthPayloadModel.
      // fromHealthDataType), então também precisam entrar no mesmo "maior
      // fonte", não só o mesmo tipo bruto.
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 5200,
            dateFrom: hoje,
            sourceName: 'Garmin Connect',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_WALKING_RUNNING,
            value: 4800,
            dateFrom: hoje,
            sourceName: 'Health Connect',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['distancia_metros'], 5200);
    });

    group('Hierarquia de Fontes (RELATÓRIO 20260810_0007 — passos+distância vêm SEMPRE da mesma fonte)', () {
      final hoje = DateTime(2026, 7, 8, 10);

    test('pedômetro nativo (Google Fit) tem MAIS passos, mas o wearable vence — prioridade bate número bruto', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          // Google Fit: mais passos, mas é pedômetro nativo — despriorizado.
          _ponto(
            type: HealthDataType.STEPS,
            value: 9000,
            dateFrom: hoje,
            sourceName: 'com.google.android.apps.fitness',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 6000, // proporção incoerente de propósito — não deve ganhar
            dateFrom: hoje,
            sourceName: 'com.google.android.apps.fitness',
          ),
          // Garmin: menos passos, mas prioridade alta (não é pedômetro nativo).
          _ponto(
            type: HealthDataType.STEPS,
            value: 7000,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 5100,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['passos'], 7000);
      expect(linha['distancia_metros'], 5100);
    });

    test('sem pedômetro nativo envolvido, desempate pelo maior nº de passos — distância vem da MESMA fonte, nunca mistura', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.STEPS,
            value: 8000,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 6000,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.STEPS,
            value: 6500,
            dateFrom: hoje,
            sourceName: 'com.polar.polarflow',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 4900,
            dateFrom: hoje,
            sourceName: 'com.polar.polarflow',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      // Garmin venceu por ter mais passos (8000 > 6500) — a distância tem
      // que vir DELE também (6000), nunca do Polar (4900), mesmo que 4900
      // não fosse a maior distância isolada.
      expect(linha['passos'], 8000);
      expect(linha['distancia_metros'], 6000);
    });

    test('iOS: classifica pelo bundle id (sourceId), não pelo nome amigável (sourceName)', () async {
      // No iOS, sourceName é o nome amigável ("Health") e sourceId é o
      // bundle id de verdade (com.apple.health) — o oposto do Android, onde
      // sourceId vem sempre vazio (ver doc de
      // HealthMetricPoint.identificadorFonte). Sem usar sourceId aqui, o
      // pedômetro nativo do iPhone não seria reconhecido e "ganharia" por
      // ter mais passos, exatamente o bug que esta tarefa corrige.
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.STEPS,
            value: 9000,
            dateFrom: hoje,
            sourceName: 'Health',
            sourceId: 'com.apple.health',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_WALKING_RUNNING,
            value: 6000,
            dateFrom: hoje,
            sourceName: 'Health',
            sourceId: 'com.apple.health',
          ),
          _ponto(
            type: HealthDataType.STEPS,
            value: 7000,
            dateFrom: hoje,
            sourceName: 'Apple Watch',
            sourceId: 'com.apple.health.watch',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_WALKING_RUNNING,
            value: 5100,
            dateFrom: hoje,
            sourceName: 'Apple Watch',
            sourceId: 'com.apple.health.watch',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['passos'], 7000);
      expect(linha['distancia_metros'], 5100);
    });

    test('RELATÓRIO 20260813_0018 — passos nativos do Health Connect (sem app dono, hash por instalação) têm MAIS passos, mas o wearable vence e a distância dele não é descartada', () async {
      // Achado real (device `atleta1000@teste.com`, 2026-08-11): o próprio
      // Health Connect registra passos contados pelo acelerômetro sob um
      // identificador gerado por instalação — sem estar na lista exata de
      // `_pedometrosNativos`, essa fonte entrava em prioridade ALTA (mesmo
      // nível de um wearable de verdade) e podia vencer a Fonte Vencedora só
      // por ter mais passos, derrubando em silêncio a distância real do
      // Garmin (essa fonte nunca reporta DISTANCE_DELTA).
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          // Passos nativos do Health Connect: mais passos, mas é pedômetro
          // nativo (hash de instalação) — despriorizado, e nunca tem distância.
          _ponto(
            type: HealthDataType.STEPS,
            value: 9000,
            dateFrom: hoje,
            sourceName: 'com.android.healthconnect.phone.j2a624ede62c5300086a4c5d757082ec3',
          ),
          // Garmin: menos passos, mas prioridade alta — e é quem reporta distância.
          _ponto(
            type: HealthDataType.STEPS,
            value: 7000,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 5100,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['passos'], 7000);
      expect(linha['distancia_metros'], 5100);
    });
    });

    group('preenchimento defensivo de distância faltante (RELATÓRIO 20260812_0013 — investigação de "distância sumindo em dias aleatórios")', () {
      /// A leitura combinada (todos os tipos de uma vez) só devolve
      /// [tipos] contidos em [aceitos] — simula "o Health Connect devolveu
      /// passos mas não distância nessa consulta ampla" sem precisar saber
      /// a lista exata de ~20 tipos que `_tiposSuportados` pede.
      void stubLeituraDupla({
        required List<HealthDataPoint> respostaAmpla,
        required List<HealthDataPoint> respostaEstreita,
      }) {
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types', that: predicate<List<HealthDataType>>((tipos) => tipos.length > 2)),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer((_) async => respostaAmpla);

        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types', that: predicate<List<HealthDataType>>(
                (tipos) =>
                    tipos.length == 2 &&
                    tipos.contains(HealthDataType.DISTANCE_DELTA) &&
                    tipos.contains(HealthDataType.DISTANCE_WALKING_RUNNING),
              )),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer((_) async => respostaEstreita);
      }

      test('leitura ampla sem distância (só passos) + leitura estreita COM distância -> preenche', () async {
        final hoje = DateTime(2026, 7, 8, 10);
        stubLeituraDupla(
          respostaAmpla: [
            _ponto(
              type: HealthDataType.STEPS,
              value: 8000,
              dateFrom: hoje,
              sourceName: 'com.garmin.android.apps.connectmobile',
            ),
          ],
          respostaEstreita: [
            _ponto(
              type: HealthDataType.DISTANCE_DELTA,
              value: 6200,
              dateFrom: hoje,
              sourceName: 'com.garmin.android.apps.connectmobile',
            ),
          ],
        );

        final resultado = await service.sincronizarDeltaDiario();

        final linha = resultado.linhas.single;
        expect(linha['passos'], 8000);
        expect(linha['distancia_metros'], 6200);
      });

      test('leitura estreita TAMBÉM sem distância -> dia fica sem distância, sem quebrar o sync', () async {
        final hoje = DateTime(2026, 7, 8, 10);
        stubLeituraDupla(
          respostaAmpla: [
            _ponto(
              type: HealthDataType.STEPS,
              value: 8000,
              dateFrom: hoje,
              sourceName: 'com.garmin.android.apps.connectmobile',
            ),
          ],
          respostaEstreita: const [],
        );

        final resultado = await service.sincronizarDeltaDiario();

        final linha = resultado.linhas.single;
        expect(linha['passos'], 8000);
        expect(linha.containsKey('distancia_metros'), isFalse);
      });

      test('distância já veio na leitura ampla -> NÃO dispara a leitura estreita (nem risco de somar em dobro)', () async {
        final hoje = DateTime(2026, 7, 8, 10);
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            _ponto(
              type: HealthDataType.STEPS,
              value: 8000,
              dateFrom: hoje,
              sourceName: 'com.garmin.android.apps.connectmobile',
            ),
            _ponto(
              type: HealthDataType.DISTANCE_DELTA,
              value: 6200,
              dateFrom: hoje,
              sourceName: 'com.garmin.android.apps.connectmobile',
            ),
          ],
        );

        final resultado = await service.sincronizarDeltaDiario();

        expect(resultado.linhas.single['distancia_metros'], 6200);
        verify(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).called(1);
      });

      test('sem passos nenhum no dia -> não tenta preencher distância (nada a completar)', () async {
        final hoje = DateTime(2026, 7, 8, 10);
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            _ponto(type: HealthDataType.HEART_RATE, value: 70, dateFrom: hoje),
          ],
        );

        final resultado = await service.sincronizarDeltaDiario();

        verify(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).called(1);
        expect(resultado.linhas.single.containsKey('distancia_metros'), isFalse);
      });

      test('leitura estreita lança exceção -> best-effort, sync principal ainda sucede', () async {
        final hoje = DateTime(2026, 7, 8, 10);
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types', that: predicate<List<HealthDataType>>((tipos) => tipos.length > 2)),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            _ponto(
              type: HealthDataType.STEPS,
              value: 8000,
              dateFrom: hoje,
              sourceName: 'com.garmin.android.apps.connectmobile',
            ),
          ],
        );
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types', that: predicate<List<HealthDataType>>((tipos) => tipos.length == 2)),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenThrow(Exception('timeout de rede'));

        final resultado = await service.sincronizarDeltaDiario();

        expect(resultado.outcome, DeltaSyncOutcome.sucesso);
        expect(resultado.linhas.single['passos'], 8000);
        expect(resultado.linhas.single.containsKey('distancia_metros'), isFalse);
      });
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
      // RELATÓRIO 20260811_0002 (upsert destrutivo): um .upsert() POR
      // LINHA, nunca o lote inteiro num só request — ver doc de
      // _enviarLinhas. Com 1 linha só, isso ainda é uma chamada só, mas
      // com a linha (Map), não a lista.
      verify(
        () => metricasBuilder.upsert(
          linha,
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

  group('Modo Raio-X (RELATÓRIO 20260811_0002 — diretriz "até o último fio de cabelo")', () {
    late DebugPrintCallback debugPrintOriginal;
    late List<String> logsCapturados;

    setUp(() {
      debugPrintOriginal = debugPrint;
      logsCapturados = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logsCapturados.add(message);
      };
    });

    tearDown(() {
      debugPrint = debugPrintOriginal;
    });

    test('imprime resumo cru por dia/fonte ANTES de qualquer agregação nossa', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.STEPS,
            value: 4000,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.DISTANCE_DELTA,
            value: 3000,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.STEPS,
            value: 3500,
            dateFrom: hoje,
            sourceName: 'com.google.android.apps.fitness',
          ),
        ],
      );

      await service.sincronizarDeltaDiario();

      final linhaResumo =
          logsCapturados.firstWhere((l) => l.contains('[RAIO-X] 3 registros'));
      expect(linhaResumo, contains('cobrindo 1 dia(s)'));

      final linhaDoDia =
          logsCapturados.firstWhere((l) => l.contains('Dia 2026-07-08'));
      expect(linhaDoDia, contains('Recebidos 3 registros'));
      expect(linhaDoDia, contains('com.garmin.android.apps.connectmobile: STEPS'));
      expect(linhaDoDia, contains('DISTANCE_DELTA'));
      expect(linhaDoDia, contains('com.google.android.apps.fitness: STEPS'));
    });

    test('0 registros brutos também loga (não fica em silêncio quando o Health Connect não devolve nada)', () async {
      await service.sincronizarDeltaDiario();

      expect(
        logsCapturados,
        contains('🩻 [RAIO-X] 0 registros brutos recebidos do health store.'),
      );
    });

    test('RELATÓRIO 20260813_0014 — uma exceção na leitura (rede, parsing, plugin) não fica mais silenciosa: aparece no console', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenThrow(Exception('falha simulada de leitura do health store'));

      final resultado = await service.sincronizarDeltaDiario();

      // Comportamento preservado: ainda vira "permissão negada" (best-effort,
      // não derruba o app) — o que muda é só a observabilidade.
      expect(resultado.outcome, DeltaSyncOutcome.permissaoNegada);
      expect(
        logsCapturados,
        contains(predicate<String>(
          (log) =>
              log.contains('HealthSyncService: falha ao ler do health store') &&
              log.contains('falha simulada de leitura do health store'),
        )),
      );
    });
  });

  group('Proteção Extrema no Parsing (RELATÓRIO 20260813_0015, Parte 1)', () {
    test('1 ponto com valor NaN (ex.: STEPS, que usa .round()) não derruba os demais pontos do lote', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      final ontem = hoje.subtract(const Duration(days: 1));
      // STEPS usa `.round()` na conversão pra payload — `double.nan.round()`
      // lança `UnsupportedError`. Antes desta tarefa, isso propagava pro
      // `.map().toList()` de `toPayloads()` e derrubava TODOS os payloads
      // do lote inteiro, de QUALQUER dia — não só o de `hoje`.
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.STEPS, value: double.nan, dateFrom: hoje),
          _ponto(type: HealthDataType.WEIGHT, value: 79, dateFrom: ontem),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      final porData = {
        for (final linha in resultado.linhas) linha['data_referencia']: linha,
      };
      // O dia com o ponto ruim fica de fora (não dá pra confiar num NaN),
      // mas o dia bom não é afetado.
      expect(porData.containsKey(_dataIso(hoje)), isFalse);
      expect(porData[_dataIso(ontem)]!['peso_kg'], 79);
    });

    test('mistura de ponto ruim e bons no MESMO dia: o dia ainda é gravado com os campos bons', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.STEPS, value: double.nan, dateFrom: hoje),
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      final linha = resultado.linhas.single;
      expect(linha['data_referencia'], _dataIso(hoje));
      expect(linha['peso_kg'], 80);
      expect(linha.containsKey('passos'), isFalse);
    });
  });

  group('Modo de Diagnóstico Profundo (RELATÓRIO 20260813_0015, Parte 2)', () {
    late DebugPrintCallback debugPrintOriginal;
    late List<String> logsCapturados;

    setUp(() {
      debugPrintOriginal = debugPrint;
      logsCapturados = [];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logsCapturados.add(message);
      };
    });

    tearDown(() {
      debugPrint = debugPrintOriginal;
    });

    bool logContem(String trecho) =>
        logsCapturados.any((l) => l.contains(trecho));

    test('desligado por padrão: sincronizarDeltaDiario/carregarHistoricoInicial NUNCA imprimem [SYNC_DIAGNOSTICO]', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 4000, dateFrom: hoje)],
      );

      await service.sincronizarDeltaDiario();
      await service.carregarHistoricoInicial();

      expect(logsCapturados.any((l) => l.contains('[SYNC_DIAGNOSTICO]')), isFalse);
    });

    test('executarDiagnosticoProfundo imprime os limites exatos startTime/endTime (endTime = agora, não meia-noite)', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer((_) async => const []);

      await service.executarDiagnosticoProfundo();

      expect(
        logsCapturados,
        contains(predicate<String>(
          (l) =>
              l.contains('[SYNC_DIAGNOSTICO] Janela pedida ao pacote health') &&
              l.contains('startTime=') &&
              l.contains('endTime=') &&
              l.contains('endTime = DateTime.now() exato'),
        )),
      );
    });

    test('imprime contagem por tipo/dia e o valor bruto + runtimeType de cada ponto', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje),
          _ponto(
            type: HealthDataType.BASAL_ENERGY_BURNED,
            value: 1650,
            dateFrom: hoje,
          ),
        ],
      );

      await service.executarDiagnosticoProfundo();

      expect(logContem('WEIGHT: 1 ponto(s)'), isTrue);
      expect(logContem('BASAL_ENERGY_BURNED: 1 ponto(s)'), isTrue);
      expect(logContem('valor=80.0'), isTrue);
      expect(logContem('tipoNativo=NumericHealthValue'), isTrue);
    });

    test('distância com pontos recebidos mas soma 0/null: imprime o dump bruto de diagnóstico daquele dia', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.DISTANCE_DELTA, value: 0, dateFrom: hoje),
        ],
      );

      await service.executarDiagnosticoProfundo();

      expect(
        logContem('⚠️ Dia ${_dataIso(hoje)} tem 1 ponto(s) de distância mas a soma deu 0.0'),
        isTrue,
      );
      expect(logContem('⚠️ rawValue='), isTrue);
    });

    test('dia com distância normal (soma > 0) NÃO dispara o alerta de dump bruto', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.DISTANCE_DELTA, value: 500, dateFrom: hoje),
        ],
      );

      await service.executarDiagnosticoProfundo();

      expect(logsCapturados.any((l) => l.contains('⚠️')), isFalse);
    });

    test('RELATÓRIO 20260813_0016 — HEART_RATE (leitura contínua) imprime só a contagem, NUNCA o detalhe ponto a ponto', () async {
      // Achado real em device físico: um único dia pode ter 600-950
      // leituras de HEART_RATE — imprimir detalhe de cada uma (como as
      // outras métricas fazem) fazia o relatório inteiro de 30 dias levar
      // mais de 33 MINUTOS pra imprimir (limitador de taxa do
      // `debugPrint`), o que na prática parecia "não gerou nada".
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => List.generate(
          200,
          (i) => _ponto(
            type: HealthDataType.HEART_RATE,
            value: 60 + i % 10,
            dateFrom: hoje.add(Duration(minutes: i)),
          ),
        ),
      );

      await service.executarDiagnosticoProfundo();

      expect(logContem('HEART_RATE: 200 ponto(s)'), isTrue);
      expect(logsCapturados.any((l) => l.contains('tipoNativo=')), isFalse);
    });

    test('teto de segurança: um tipo de baixa frequência com volume anormalmente alto detalha só os primeiros 50 e resume o resto', () async {
      final hoje = DateTime(2026, 7, 8, 10);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => List.generate(
          70,
          (i) => _ponto(
            type: HealthDataType.WEIGHT,
            value: 80,
            dateFrom: hoje.add(Duration(minutes: i)),
          ),
        ),
      );

      await service.executarDiagnosticoProfundo();

      expect(logContem('WEIGHT: 70 ponto(s)'), isTrue);
      expect(
        logsCapturados.where((l) => l.contains('tipoNativo=')).length,
        50,
      );
      expect(logContem('... e mais 20 ponto(s) omitido(s)'), isTrue);
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

    test('achado RELATÓRIO 20260810_0007: falha transitória na 1ª tentativa NÃO apaga o IMC do resto do lote — tenta de novo', () async {
      // Antes desta tarefa, alturaJaBuscada virava true mesmo quando a
      // busca LANÇAVA (não só quando tinha sucesso) — uma falha pontual no
      // primeiro dia processado matava o IMC do lote de 30 dias inteiro,
      // com só um debugPrint invisível como rastro. Aqui: 1ª tentativa
      // lança, 2ª tem sucesso — o dia da 1ª tentativa fica sem IMC (correto,
      // não dava pra saber a altura ainda), mas o lote NÃO desiste: o dia
      // seguinte tenta de novo e consegue.
      var tentativas = 0;
      when(() => perfisBuilder.select(any())).thenAnswer((_) {
        tentativas++;
        return tentativas == 1
            ? _FakeAlturaFilterBuilder(null, erro: Exception('timeout de rede'))
            : _FakeAlturaFilterBuilder({'altura_cm': 180});
      });
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

      final porData = {
        for (final linha in resultado.linhas) linha['data_referencia']: linha,
      };
      expect(porData[_dataIso(hoje)]!['imc'], isNull);
      expect(porData[_dataIso(ontem)]!['imc'], isNotNull);
      verify(() => perfisBuilder.select(any())).called(2);
    });
  });

  group('Calorias granulares (RELATÓRIO 20260811_0002 — decisão do fundador)', () {
    final hoje = DateTime(2026, 7, 8, 10);

    test('calorias_basais: fica com a MAIOR fonte do dia, mesmo tratamento anti-double-counting de calorias_ativas', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.BASAL_ENERGY_BURNED,
            value: 1650,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.BASAL_ENERGY_BURNED,
            value: 1500,
            dateFrom: hoje,
            sourceName: 'com.google.android.apps.fitness',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['calorias_basais'], 1650);
    });

    test('RELATÓRIO 20260813_0019 — calorias_basais só do app da balança (Fitdays) no dia: fica de fora, nunca vira fallback', () async {
      // Achado real (device atleta1000@teste.com): Fitdays só calcula
      // BASAL_ENERGY_BURNED no instante exato de uma pesagem (mesmo
      // timestamp do WEIGHT) — é uma estimativa pontual via fórmula, não
      // medição contínua de wearable. Sem o Garmin reportando naquele dia,
      // calorias_basais tem que ficar ausente, nunca preenchido com a
      // estimativa da balança.
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.WEIGHT,
            value: 80.6,
            dateFrom: hoje,
            sourceName: 'cn.fitdays.fitdays',
          ),
          _ponto(
            type: HealthDataType.BASAL_ENERGY_BURNED,
            value: 1890,
            dateFrom: hoje,
            sourceName: 'cn.fitdays.fitdays',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['peso_kg'], 80.6); // peso em si continua vindo normalmente
      expect(linha.containsKey('calorias_basais'), isFalse);
    });

    test('RELATÓRIO 20260813_0019 — Fitdays reporta MAIS calorias basais que o Garmin no mesmo dia: Garmin vence mesmo assim, nunca a balança', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.BASAL_ENERGY_BURNED,
            value: 1650,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.BASAL_ENERGY_BURNED,
            value: 1890, // maior que o Garmin — mesmo assim não pode vencer
            dateFrom: hoje,
            sourceName: 'cn.fitdays.fitdays',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['calorias_basais'], 1650);
    });

    test('calorias_totais = ativas + basais quando as duas estão presentes', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.ACTIVE_ENERGY_BURNED, value: 480, dateFrom: hoje),
          _ponto(type: HealthDataType.BASAL_ENERGY_BURNED, value: 1650, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha['calorias_ativas'], 480);
      expect(linha['calorias_basais'], 1650);
      expect(linha['calorias_totais'], 2130);
    });

    test('calorias_totais só com ativas presente (sem basais naquele dia): soma tratando o ausente como 0, não fica de fora', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.ACTIVE_ENERGY_BURNED, value: 480, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      final linha = resultado.linhas.single;
      expect(linha.containsKey('calorias_basais'), isFalse);
      expect(linha['calorias_totais'], 480);
    });

    test('sem nenhum dado de caloria no dia: calorias_totais fica de fora, não é gravado como 0', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: hoje)],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single.containsKey('calorias_totais'), isFalse);
    });

    test('RELATÓRIO 20260819_0020 — TOTAL_CALORIES_BURNED presente no dia: usa a leitura direta do wearable, ignora o cálculo ativas+basais', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.TOTAL_CALORIES_BURNED,
            value: 2239,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          // ativas+basais somariam só 480 — a leitura direta (2239) tem que
          // vencer, nunca o fallback.
          _ponto(type: HealthDataType.ACTIVE_ENERGY_BURNED, value: 480, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['calorias_totais'], 2239);
    });

    test('RELATÓRIO 20260819_0020 — TOTAL_CALORIES_BURNED só do Fitdays no dia: fica de fora da leitura direta, cai pro fallback ativas+basais', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.TOTAL_CALORIES_BURNED,
            value: 1897,
            dateFrom: hoje,
            sourceName: 'cn.fitdays.fitdays',
          ),
          _ponto(type: HealthDataType.ACTIVE_ENERGY_BURNED, value: 480, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['calorias_totais'], 480);
    });

    test('RELATÓRIO 20260819_0020 — TOTAL_CALORIES_BURNED ausente no dia (ex.: iOS, ou o wearable não publicou): fallback ativas+basais continua funcionando, comportamento preservado', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.ACTIVE_ENERGY_BURNED, value: 480, dateFrom: hoje),
          _ponto(type: HealthDataType.BASAL_ENERGY_BURNED, value: 1650, dateFrom: hoje),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['calorias_totais'], 2130);
    });
  });

  group('Andares subidos (RELATÓRIO 20260819_0020, pedido do fundador)', () {
    final hoje = DateTime(2026, 7, 8, 10);

    test('FLIGHTS_CLIMBED: fica com a MAIOR fonte do dia, mesmo tratamento anti-double-counting de calorias_ativas', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(
            type: HealthDataType.FLIGHTS_CLIMBED,
            value: 8,
            dateFrom: hoje,
            sourceName: 'com.garmin.android.apps.connectmobile',
          ),
          _ponto(
            type: HealthDataType.FLIGHTS_CLIMBED,
            value: 5,
            dateFrom: hoje,
            sourceName: 'com.google.android.apps.fitness',
          ),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['andares_subidos'], 8);
    });

    test('sem FLIGHTS_CLIMBED no dia: andares_subidos fica de fora, não é gravado como 0', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 1000, dateFrom: hoje)],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single.containsKey('andares_subidos'), isFalse);
    });
  });

  // RELATÓRIO 20260820 — SOLUÇÃO DEFINITIVA pro bug real (device físico,
  // atleta1000@teste.com, viagem Brasília→Lima): dado histórico é
  // bucketizado pelo fuso REALMENTE ativo quando foi gravado (via um
  // histórico de transições próprio do app), nunca pelo fuso atual do
  // sistema — decisão do fundador ("é um produto, qualquer usuário que
  // viajar vai passar por isso").
  group('Histórico de fuso horário (RELATÓRIO 20260820)', () {
    test('ponto bucketiza pelo fuso HISTÓRICO ativo no instante dele, não o fuso atual do sistema de testes', () async {
      // 03:30 UTC de 08/jul: sob UTC-3 vira 00:30 do dia 08 (mesmo dia UTC);
      // sob UTC-5 vira 22:30 do dia 07 (dia ANTERIOR) — a mesma instante
      // absoluta cai em dias de calendário diferentes dependendo só do
      // fuso usado, provando que a bucketização depende do histórico
      // seedado abaixo, não do relógio da máquina rodando o teste.
      final instante = DateTime.utc(2026, 7, 8, 3, 30);
      final transicaoAntes = instante.subtract(const Duration(days: 30));

      await secureStorage.write(
        key: AppConfig.storageKeyTimezoneHistory,
        value: jsonEncode([
          {'t': transicaoAntes.millisecondsSinceEpoch, 'o': -180}, // UTC-3
        ]),
      );

      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 1000, dateFrom: instante)],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['data_referencia'], '2026-07-08');
    });

    test('mesmo instante, histórico com offset DIFERENTE (UTC-5) bucketiza no dia calendário anterior', () async {
      final instante = DateTime.utc(2026, 7, 8, 3, 30);
      final transicaoAntes = instante.subtract(const Duration(days: 30));

      await secureStorage.write(
        key: AppConfig.storageKeyTimezoneHistory,
        value: jsonEncode([
          {'t': transicaoAntes.millisecondsSinceEpoch, 'o': -300}, // UTC-5
        ]),
      );

      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 1000, dateFrom: instante)],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.linhas.single['data_referencia'], '2026-07-07');
    });

    test('sem histórico nenhum (primeira sincronização de um usuário novo): não quebra, cai pro comportamento de antes desta tarefa', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 1000, dateFrom: DateTime(2026, 7, 8, 10))],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      expect(resultado.linhas.single['passos'], 1000);
    });

    test('após uma sincronização bem-sucedida, o histórico de fuso passa a existir no storage (primeira transição registrada)', () async {
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 1000, dateFrom: DateTime(2026, 7, 8, 10))],
      );

      await service.sincronizarDeltaDiario();

      final gravado = await secureStorage.read(key: AppConfig.storageKeyTimezoneHistory);
      expect(gravado, isNotNull);
      final decodificado = jsonDecode(gravado!) as List<dynamic>;
      expect(decodificado, hasLength(1));
    });

    test('histórico já com o mesmo offset atual: não grava uma segunda transição (só transições de verdade)', () async {
      final agora = DateTime.now();
      await secureStorage.write(
        key: AppConfig.storageKeyTimezoneHistory,
        value: jsonEncode([
          {
            't': agora.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            'o': agora.timeZoneOffset.inMinutes,
          },
        ]),
      );

      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [_ponto(type: HealthDataType.STEPS, value: 1000, dateFrom: DateTime(2026, 7, 8, 10))],
      );

      await service.sincronizarDeltaDiario();

      final gravado = await secureStorage.read(key: AppConfig.storageKeyTimezoneHistory);
      final decodificado = jsonDecode(gravado!) as List<dynamic>;
      expect(decodificado, hasLength(1)); // continua 1, não virou 2
    });
  });

  group('Treinos e Rotas (RELATÓRIO 20260811_0002)', () {
    test('FC do treino: média/máxima/mínima só das leituras DENTRO do intervalo do treino, ignora as de fora', () async {
      final inicioTreino = DateTime(2026, 7, 8, 7, 0);
      final fimTreino = DateTime(2026, 7, 8, 8, 0);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(
            tipo: HealthWorkoutActivityType.RUNNING,
            dateFrom: inicioTreino,
            dateTo: fimTreino,
            totalEnergyBurned: 450,
            totalDistance: 8000,
            totalSteps: 9500,
          ),
          // ANTES do treino começar — não pode entrar na conta.
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 65,
            dateFrom: inicioTreino.subtract(const Duration(minutes: 10)),
          ),
          // DENTRO do treino — essas três entram: média (150+160+170)/3=160.
          _ponto(type: HealthDataType.HEART_RATE, value: 150, dateFrom: inicioTreino),
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 170,
            dateFrom: inicioTreino.add(const Duration(minutes: 30)),
          ),
          _ponto(type: HealthDataType.HEART_RATE, value: 160, dateFrom: fimTreino),
          // DEPOIS do treino terminar — não pode entrar na conta.
          _ponto(
            type: HealthDataType.HEART_RATE,
            value: 90,
            dateFrom: fimTreino.add(const Duration(minutes: 15)),
          ),
        ],
      );

      await service.sincronizarDeltaDiario();

      final linhaGravada = verify(
        () => treinosBuilder.upsert(
          captureAny(),
          onConflict: 'usuario_id,inicio_atividade',
        ),
      ).captured.single as Map<String, dynamic>;

      expect(linhaGravada['tipo_atividade_codigo'], 'RUNNING');
      expect(linhaGravada['energia_queimada_kcal'], 450);
      expect(linhaGravada['distancia_metros'], 8000);
      expect(linhaGravada['passos_totais'], 9500);
      expect(linhaGravada['fc_media'], 160);
      expect(linhaGravada['fc_maxima'], 170);
      expect(linhaGravada['fc_minima'], 150);
    });

    test('RELATÓRIO 20260819_0020 — velocidade do treino: média/máxima só das leituras DENTRO do intervalo, mesmo tratamento de FC', () async {
      final inicioTreino = DateTime(2026, 7, 8, 7, 0);
      final fimTreino = DateTime(2026, 7, 8, 8, 0);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(
            tipo: HealthWorkoutActivityType.RUNNING,
            dateFrom: inicioTreino,
            dateTo: fimTreino,
          ),
          // ANTES do treino — não pode entrar na conta.
          _ponto(
            type: HealthDataType.SPEED,
            value: 10,
            dateFrom: inicioTreino.subtract(const Duration(minutes: 10)),
          ),
          // DENTRO do treino — média (2+4+3)/3=3.
          _ponto(type: HealthDataType.SPEED, value: 2, dateFrom: inicioTreino),
          _ponto(
            type: HealthDataType.SPEED,
            value: 4,
            dateFrom: inicioTreino.add(const Duration(minutes: 30)),
          ),
          _ponto(type: HealthDataType.SPEED, value: 3, dateFrom: fimTreino),
        ],
      );

      await service.sincronizarDeltaDiario();

      final linhaGravada = verify(
        () => treinosBuilder.upsert(
          captureAny(),
          onConflict: 'usuario_id,inicio_atividade',
        ),
      ).captured.single as Map<String, dynamic>;

      expect(linhaGravada['velocidade_media_ms'], 3.0);
      expect(linhaGravada['velocidade_maxima_ms'], 4.0);
    });

    test('sem SPEED nenhuma no intervalo do treino: gravado sem velocidade_media_ms/velocidade_maxima_ms (não zeradas)', () async {
      final inicio = DateTime(2026, 7, 8, 7);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(
            tipo: HealthWorkoutActivityType.WALKING,
            dateFrom: inicio,
            dateTo: inicio.add(const Duration(minutes: 20)),
          ),
        ],
      );

      await service.sincronizarDeltaDiario();

      final linhaGravada = verify(
        () => treinosBuilder.upsert(
          captureAny(),
          onConflict: 'usuario_id,inicio_atividade',
        ),
      ).captured.single as Map<String, dynamic>;

      expect(linhaGravada.containsKey('velocidade_media_ms'), isFalse);
      expect(linhaGravada.containsKey('velocidade_maxima_ms'), isFalse);
    });

    test('idempotência: upsert do treino usa onConflict (usuario_id, inicio_atividade)', () async {
      final inicio = DateTime(2026, 7, 8, 7);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(
            tipo: HealthWorkoutActivityType.SWIMMING,
            dateFrom: inicio,
            dateTo: inicio.add(const Duration(minutes: 40)),
          ),
        ],
      );

      await service.sincronizarDeltaDiario();

      verify(
        () => treinosBuilder.upsert(
          any(that: containsPair('usuario_id', _usuarioId)),
          onConflict: 'usuario_id,inicio_atividade',
        ),
      ).called(1);
    });

    // RELATÓRIO 20260820 — achado real: treino de força nunca aparecia na
    // tela nem gravava no banco. Causa raiz não era um bug de código Dart
    // (esta suíte usa mocks, não exercita a FK real de
    // tipos_atividades_fisicas), e sim o dicionário no banco nunca ter sido
    // semeado com nenhum código de força (STRENGTH_TRAINING/WEIGHTLIFTING
    // são Android-only, FUNCTIONAL/TRADITIONAL_STRENGTH_TRAINING são
    // iOS-only — nenhum é "Both", a seção que o seed original cobria).
    // Corrigido via migration `20260820100000_tipos_atividades_treino_
    // forca.sql`. Este teste trava a string exata que
    // `WorkoutHealthValue.workoutActivityType.name` produz pro upsert —
    // tem que bater com `nome_codigo` da migration, ou a FK real volta a
    // rejeitar silenciosamente.
    for (final tipo in [
      HealthWorkoutActivityType.STRENGTH_TRAINING,
      HealthWorkoutActivityType.WEIGHTLIFTING,
    ]) {
      test('treino de força (${tipo.name}) é processado com o código exato semeado no dicionário', () async {
        final inicio = DateTime(2026, 7, 8, 7);
        when(
          () => health.getHealthDataFromTypes(
            types: any(named: 'types'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
          ),
        ).thenAnswer(
          (_) async => [
            _pontoTreino(
              tipo: tipo,
              dateFrom: inicio,
              dateTo: inicio.add(const Duration(minutes: 45)),
            ),
          ],
        );

        await service.sincronizarDeltaDiario();

        final linhaGravada = verify(
          () => treinosBuilder.upsert(
            captureAny(),
            onConflict: 'usuario_id,inicio_atividade',
          ),
        ).captured.single as Map<String, dynamic>;

        expect(linhaGravada['tipo_atividade_codigo'], tipo.name);
      });
    }

    test('sem HEART_RATE nenhum no intervalo: treino é gravado sem fc_media/fc_maxima/fc_minima (não zerados)', () async {
      final inicio = DateTime(2026, 7, 8, 7);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(
            tipo: HealthWorkoutActivityType.YOGA,
            dateFrom: inicio,
            dateTo: inicio.add(const Duration(minutes: 30)),
          ),
        ],
      );

      await service.sincronizarDeltaDiario();

      final linhaGravada = verify(
        () => treinosBuilder.upsert(
          captureAny(),
          onConflict: any(named: 'onConflict'),
        ),
      ).captured.single as Map<String, dynamic>;

      expect(linhaGravada.containsKey('fc_media'), isFalse);
      expect(linhaGravada.containsKey('fc_maxima'), isFalse);
      expect(linhaGravada.containsKey('fc_minima'), isFalse);
    });

    test('rota GPS: grava os pontos linkados ao treino, limpando rotas antigas antes (idempotência)', () async {
      final inicio = DateTime(2026, 7, 8, 7);
      final fim = inicio.add(const Duration(minutes: 45));
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(tipo: HealthWorkoutActivityType.RUNNING, dateFrom: inicio, dateTo: fim),
          _pontoRota(
            dateFrom: inicio,
            dateTo: fim,
            locations: [
              WorkoutRouteLocation(latitude: -23.55, longitude: -46.63, timestamp: inicio),
              WorkoutRouteLocation(
                latitude: -23.551,
                longitude: -46.631,
                timestamp: inicio.add(const Duration(minutes: 20)),
                altitude: 760,
                horizontalAccuracy: 5,
              ),
            ],
          ),
        ],
      );
      stubUpsertTreino(id: 'treino-xyz');

      await service.sincronizarDeltaDiario();

      verify(() => rotasBuilder.delete()).called(1);
      final pontosGravados = verify(
        () => rotasBuilder.insert(captureAny()),
      ).captured.single as List<dynamic>;
      expect(pontosGravados, hasLength(2));
      expect(pontosGravados[0]['treino_id'], 'treino-xyz');
      expect(pontosGravados[0]['latitude'], -23.55);
      expect(pontosGravados[1]['altitude'], 760);
      expect(pontosGravados[1]['precisao'], 5);
    });

    test('rota vazia (sem GPS de verdade OU ConsentRequired do Android — indistinguíveis): ignora silenciosamente, não grava nada', () async {
      // Achado real (RELATÓRIO 20260811_0002): quando o Health Connect exige
      // consentimento extra pra rota, a resposta que chega no Dart já vem
      // com locations vazio — o mesmo formato de "este treino não tem
      // rota". Não existe um jeito de distinguir os dois casos por aqui, e
      // o comportamento certo (ignorar sem quebrar nada) é o mesmo pros
      // dois.
      final inicio = DateTime(2026, 7, 8, 7);
      final fim = inicio.add(const Duration(minutes: 45));
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(tipo: HealthWorkoutActivityType.RUNNING, dateFrom: inicio, dateTo: fim),
          _pontoRota(dateFrom: inicio, dateTo: fim, locations: const []),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      expect(resultado.outcome, DeltaSyncOutcome.semAlteracoes);
      verifyNever(() => rotasBuilder.delete());
      verifyNever(() => rotasBuilder.insert(any()));
    });

    test('falha ao gravar o treino (rede/RLS) é best-effort — não derruba a sincronização principal', () async {
      stubUpsertTreino(erro: Exception('RLS negou'));
      final inicio = DateTime(2026, 7, 8, 7);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _pontoTreino(
            tipo: HealthWorkoutActivityType.RUNNING,
            dateFrom: inicio,
            dateTo: inicio.add(const Duration(minutes: 30)),
          ),
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: inicio),
        ],
      );

      final resultado = await service.sincronizarDeltaDiario();

      // A falha foi só no treino — a sincronização de metricas_saude_diarias
      // (peso, nesse caso) segue funcionando normalmente.
      expect(resultado.outcome, DeltaSyncOutcome.sucesso);
      expect(resultado.linhas.single['peso_kg'], 80);
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

    test('BUG CRÍTICO CORRIGIDO (RELATÓRIO 20260811_0002 — "upsert destrutivo"): dias com colunas diferentes no mesmo lote NÃO viram um upsert só com o lote inteiro', () async {
      // Cenário exato do bug: dia A só tem passos, dia B só tem peso — bem
      // comum na Carga de 30 dias (nem todo dia tem toda métrica). Antes
      // desta correção, um único `.upsert([linhaA, linhaB])` fazia o
      // PostgREST unir as colunas dos dois dias e preencher com NULL a
      // coluna que cada linha não tem (confirmado no teste
      // "bulk insert without column defaults" do próprio pacote
      // postgrest) — sobrescrevendo, por exemplo, um peso_kg bom do dia A
      // com null, mesmo o dia A nunca tendo mandado peso_kg=null.
      final diaA = DateTime(2026, 7, 7);
      final diaB = DateTime(2026, 7, 8);
      when(
        () => health.getHealthDataFromTypes(
          types: any(named: 'types'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
        ),
      ).thenAnswer(
        (_) async => [
          _ponto(type: HealthDataType.STEPS, value: 4000, dateFrom: diaA),
          _ponto(type: HealthDataType.WEIGHT, value: 80, dateFrom: diaB),
        ],
      );

      final resultado = await service.carregarHistoricoInicial();

      expect(resultado.linhas, hasLength(2));
      final linhaA =
          resultado.linhas.firstWhere((l) => l['data_referencia'] == '2026-07-07');
      final linhaB =
          resultado.linhas.firstWhere((l) => l['data_referencia'] == '2026-07-08');
      // Cada linha só tem as colunas que aquele dia teve dado — nenhuma
      // chave 'peso_kg'/'passos' cruzada, nem null explícito.
      expect(linhaA.containsKey('peso_kg'), isFalse);
      expect(linhaB.containsKey('passos'), isFalse);

      // O ponto central do teste: DOIS upserts SEPARADOS, um por linha —
      // nunca um upsert só recebendo a lista com as duas.
      verify(
        () => metricasBuilder.upsert(linhaA, onConflict: 'usuario_id_anonimo,data_referencia'),
      ).called(1);
      verify(
        () => metricasBuilder.upsert(linhaB, onConflict: 'usuario_id_anonimo,data_referencia'),
      ).called(1);
      verifyNever(
        () => metricasBuilder.upsert(
          resultado.linhas,
          onConflict: any(named: 'onConflict'),
        ),
      );
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
      // RELATÓRIO 20260811_0002 (upsert destrutivo): 2 dias com colunas
      // diferentes NÃO podem ir num único .upsert() com o lote inteiro —
      // é exatamente isso que fazia o PostgREST encher a coluna que um dia
      // não tem com NULL explícito, sobrescrevendo dado bom de outro sync.
      // Cada linha vira sua PRÓPRIA chamada.
      for (final linha in resultado.linhas) {
        verify(
          () => metricasBuilder.upsert(
            linha,
            onConflict: 'usuario_id_anonimo,data_referencia',
          ),
        ).called(1);
      }
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
      // RELATÓRIO 20260811_0002: um .upsert() por linha (linhas.single),
      // não a lista inteira — ver doc de _enviarLinhas.
      verify(
        () => metricasBuilder.upsert(
          linhas.single,
          onConflict: 'usuario_id_anonimo,data_referencia',
        ),
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
        rawValue: NumericHealthValue(numericValue: 60),
      );
      final recente = HealthMetricPoint(
        type: HealthDataType.HEART_RATE,
        value: 72,
        unit: 'bpm',
        dateFrom: DateTime(2026, 7, 8, 14),
        dateTo: DateTime(2026, 7, 8, 14),
        sourceApp: 'Garmin Connect',
        rawValue: NumericHealthValue(numericValue: 72),
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
