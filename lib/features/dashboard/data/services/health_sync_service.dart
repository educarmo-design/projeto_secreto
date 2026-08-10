import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
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
  /// camera/AI extraction path — the fixed-column shape written to
  /// `metricas_saude_diarias` alongside camera-origin readings.
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

  /// Normalized, fixed-column payloads (one per point) ready for
  /// `metricas_saude_diarias`. Points whose [HealthDataType] has no fixed
  /// column mapping (e.g. `WORKOUT`) yield an empty payload, filtered out
  /// here.
  List<HealthPayloadModel> toPayloads() => points
      .map((point) => point.toPayload())
      .where((payload) => !payload.isEmpty)
      .toList();
}

/// One structured entry for the "Caixa Preta" (black box) of health
/// anomalies — `eventos_anomalias_saude`. Mirrors that table's fixed
/// columns exactly; see [toJson].
class EventoAnomaliaSaude {
  final String tipoAnomalia;
  final String parametro;
  final num valorDetectado;
  final num? valorLimiteMin;
  final num? valorLimiteMax;
  final bool emTreino;
  final String severidade;
  final String? origem;
  final DateTime detectadoEm;

  const EventoAnomaliaSaude({
    required this.tipoAnomalia,
    required this.parametro,
    required this.valorDetectado,
    this.valorLimiteMin,
    this.valorLimiteMax,
    required this.emTreino,
    required this.severidade,
    this.origem,
    required this.detectadoEm,
  });

  Map<String, dynamic> toJson(String usuarioIdAnonimo) => {
        'usuario_id_anonimo': usuarioIdAnonimo,
        'tipo_anomalia': tipoAnomalia,
        'parametro': parametro,
        'valor_detectado': valorDetectado,
        if (valorLimiteMin != null) 'valor_limite_min': valorLimiteMin,
        if (valorLimiteMax != null) 'valor_limite_max': valorLimiteMax,
        'em_treino': emTreino,
        'severidade': severidade,
        if (origem != null) 'origem': origem,
        'detectado_em': detectadoEm.toIso8601String(),
      };

  /// Reads a row back from `eventos_anomalias_saude` — the exact,
  /// symmetric counterpart of [toJson]. Used by the Módulo de Inteligência
  /// (`lib/features/intelligence/`) to feed anomaly history into the Dia 7
  /// preventive report; this "Caixa Preta" table was insert-only until then.
  factory EventoAnomaliaSaude.fromJson(Map<String, dynamic> json) {
    return EventoAnomaliaSaude(
      tipoAnomalia: json['tipo_anomalia'] as String,
      parametro: json['parametro'] as String,
      valorDetectado: json['valor_detectado'] as num,
      valorLimiteMin: json['valor_limite_min'] as num?,
      valorLimiteMax: json['valor_limite_max'] as num?,
      emTreino: json['em_treino'] as bool? ?? false,
      severidade: json['severidade'] as String,
      origem: json['origem'] as String?,
      detectadoEm: DateTime.parse(json['detectado_em'] as String),
    );
  }
}

/// Outcome of one [HealthSyncService.sincronizarDeltaDiario] call. Split out
/// from the boolean-ish [HealthSyncResult] because the delta path has a
/// distinct offline case: the on-device health read never needs network, but
/// the write into `metricas_saude_diarias` does — an offline write must be
/// handed back to the caller (see [DeltaSyncResult.linhas]) to queue locally,
/// not silently dropped or lumped in with a real error.
enum DeltaSyncOutcome { sucesso, semAlteracoes, offline, permissaoNegada, erro }

/// Result of a daily-delta sync attempt: reads-then-writes the fixed-column
/// rows for `metricas_saude_diarias` covering everything generated since the
/// last successful sync.
class DeltaSyncResult {
  final DeltaSyncOutcome outcome;

  /// Merged, one-row-per-day fixed-column payloads this attempt tried to
  /// write. Populated even on [DeltaSyncOutcome.offline] so the caller (e.g.
  /// `SyncUiController`) can persist them locally and retry later.
  final List<Map<String, dynamic>> linhas;
  final DateTime? sincronizadoEm;
  final String? errorMessage;
  final bool needsHealthConnectInstall;

  const DeltaSyncResult({
    required this.outcome,
    this.linhas = const [],
    this.sincronizadoEm,
    this.errorMessage,
    this.needsHealthConnectInstall = false,
  });

  bool get isSuccess =>
      outcome == DeltaSyncOutcome.sucesso ||
      outcome == DeltaSyncOutcome.semAlteracoes;
  bool get isOffline => outcome == DeltaSyncOutcome.offline;
}

/// Bridges Health Connect (Android) / HealthKit (iOS) via the `health`
/// plugin. Zero-cost by design: no per-wearable vendor SDK and no paid
/// aggregation service — the device's OS health store already merges data
/// from every connected wearable and any third-party app that writes into
/// it, so a single read here covers all of them.
class HealthSyncService {
  HealthSyncService({
    Health? health,
    SupabaseClient? supabaseClient,
    FlutterSecureStorage? secureStorage,
  })  : _health = health ?? Health(),
        _supabase = supabaseClient ?? Supabase.instance.client,
        _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    _configured = _health.configure();
  }

  final Health _health;
  final SupabaseClient _supabase;
  final FlutterSecureStorage _secureStorage;
  late final Future<void> _configured;

  // Faixas de referência clínica usadas pela checagem defensiva em primeiro
  // plano (Caixa Preta). Fora da faixa "normal" gera um evento com
  // severidade 'atencao'; fora da faixa "crítica" gera severidade 'critico'.
  static const int _fcForaTreinoMin = 40;
  static const int _fcForaTreinoMax = 120;
  static const int _fcCriticoMin = 35;
  static const int _fcCriticoMax = 160;

  static const double _glicoseMin = 70;
  static const double _glicoseMax = 180;
  static const double _glicoseCriticoMin = 54;
  static const double _glicoseCriticoMax = 250;

  static const int _sistolicaMax = 140;
  static const int _sistolicaCriticoMax = 180;
  static const int _diastolicaMax = 90;
  static const int _diastolicaCriticoMax = 120;

  /// The full superset of biological/clinical signals this app tracks.
  /// Some are platform-specific variants of the same signal (distance,
  /// sleep, HRV have a different [HealthDataType] on iOS vs. Android) —
  /// both variants are listed here and [_tiposSuportados] filters down to
  /// whichever this platform's health store actually exposes, so callers
  /// never have to branch on platform.
  static const List<HealthDataType> todosOsTipos = [
    HealthDataType.HEART_RATE,
    // N17/N18: métrica dedicada do Health Connect para FC de repouso —
    // distinta de HEART_RATE genérico (ver HealthPayloadModel.fromHealthDataType
    // e o RELATÓRIO da tarefa para a decisão de separar os dois sinais).
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_WALKING_RUNNING,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    // RELATÓRIO 20260811 — sono por estágio granular, não mais um total
    // único. SLEEP_SESSION continua fora daqui (mesmo motivo do RELATÓRIO
    // 20260810: cobre bedtime->waketime inteiro, incluindo acordado —
    // `lerSonoRecente`, tela de teste manual, continua pedindo ela sozinha,
    // sem afetar esta lista/a gravação). Os 5 tipos abaixo alimentam as
    // colunas sono_leve_minutos/sono_profundo_minutos/sono_rem_minutos/
    // sono_acordado_minutos (ver HealthPayloadModel.fromHealthDataType e
    // HealthSyncService._mesclarPorDia) — SLEEP_ASLEEP é o fallback de
    // dispositivos que só reportam "dormindo" sem quebrar em estágio;
    // some para sono_leve_minutos (ver nota no merge).
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.WEIGHT,
    // N17/N18: massa magra — nenhum HealthDataType cobria este sinal antes.
    HealthDataType.LEAN_BODY_MASS,
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

  /// Carga Inicial (N18): reads the complete telemetry history across every
  /// biological/clinical parameter this app tracks — heart rate (both
  /// generic and resting), steps, distance, calories, sleep, HRV, weight,
  /// lean mass, body fat, blood pressure, glucose, oxygen saturation and
  /// body temperature — for the last [dias] days (default 30), merges it
  /// into one row per day and **persists it** into `metricas_saude_diarias`
  /// via the same idempotent upsert [sincronizarDeltaDiario] uses.
  ///
  /// BUG CORRIGIDO NESTA TAREFA: até aqui este método só lia (delegava para
  /// `_lerComPermissao` e devolvia os pontos crus) — nunca escrevia nada no
  /// Supabase. `RegistrarMetricaPage` mostrava "N registros sincronizados"
  /// só com base na leitura, sem persistir nada; é exatamente o "lê, mas
  /// não grava" já confirmado pelo fundador e registrado no Mestre (Parte 2
  /// C2). Corrigido reaproveitando [_lerEGravar] — o mesmo caminho de
  /// leitura+merge+upsert+cursor que [sincronizarDeltaDiario] já usa, só com
  /// uma janela de [dias] em vez de "desde o último sync".
  ///
  /// Chamado quando o usuário conecta um wearable pela primeira vez (ver
  /// [SyncUiController.conectarWearablePelaPrimeiraVez]) — destrava o
  /// dashboard/histórico no dia 1 em vez de começar vazio.
  ///
  /// CAUSA RAIZ DO BUG "só 2 dias na Carga Inicial" (teste físico N17/N18,
  /// ver RELATÓRIO 20260809): pedir `dias: 30` aqui SEMPRE pediu a janela
  /// certa ao Health Connect — o bug não estava nesta conta. O Health
  /// Connect, por padrão, só deixa um app ler dado a partir do MOMENTO em
  /// que a permissão normal (READ_STEPS, READ_HEART_RATE, ...) foi
  /// concedida, não os `dias` anteriores a "agora" — é uma restrição de
  /// privacidade da plataforma, documentada pelo próprio pacote `health`
  /// ("By default, Health Connect restricts read data to 30 days from when
  /// permission has been granted"). Sem [_garantirPermissaoHistorico], a
  /// primeira conexão só enxergava dado gravado depois da concessão —
  /// exatamente "ontem e hoje" no teste do fundador, porque foi quando ele
  /// concedeu a permissão.
  Future<DeltaSyncResult> carregarHistoricoInicial({int dias = 30}) async {
    await _configured;
    await _garantirPermissaoHistorico();
    return _lerEGravar(_tiposSuportados, dias: dias);
  }

  /// Pede a permissão especial `READ_HEALTH_DATA_HISTORY` — separada das
  /// `READ_*` normais que [_lerComPermissao] já pede, com diálogo próprio
  /// do Health Connect. Só chamado por [carregarHistoricoInicial]: é a
  /// única leitura que pede dado anterior à concessão original;
  /// [sincronizarDeltaDiario] nunca precisa dela (janela de 24-48h sempre
  /// cabe dentro do período normalmente autorizado). Best-effort — se o
  /// usuário negar ou o dispositivo não suportar, a leitura segue adiante
  /// do mesmo jeito, só que limitada à janela que o Health Connect
  /// permitir (mesmo comportamento de antes desta correção, não uma
  /// regressão nova).
  Future<void> _garantirPermissaoHistorico() async {
    try {
      final jaAutorizado = await _health.isHealthDataHistoryAuthorized();
      if (!jaAutorizado) {
        await _health.requestHealthDataHistoryAuthorization();
      }
    } catch (e) {
      debugPrint('HealthSyncService: falha ao pedir READ_HEALTH_DATA_HISTORY: $e');
    }
  }

  /// Leitura pontual, só de [HealthDataType.HEART_RATE], das últimas [horas]
  /// (padrão 24h) — gatilho manual de teste/validação do fundador (Adendo
  /// v5.1 §B: "validação = completa funcionalmente, crua visualmente").
  /// Passa por exatamente o mesmo caminho de permissão/instalação do Health
  /// Connect que [carregarHistoricoInicial]/[sincronizarDeltaDiario] já
  /// usam — [_lerComPermissao] — só que pedindo um único tipo, então não
  /// aciona (nem exige permissão de) nenhum dos outros sinais que o app
  /// rastreia. Não grava nada — quem chama decide o que fazer com
  /// [HealthSyncResult.points]; ver [ultimaLeituraOuNula] para o valor bruto
  /// mais recente.
  Future<HealthSyncResult> lerFrequenciaCardiacaRecente({int horas = 24}) {
    return _lerComPermissao(
      const [HealthDataType.HEART_RATE],
      start: DateTime.now().subtract(Duration(hours: horas)),
    );
  }

  /// Leitura pontual, só de [HealthDataType.WEIGHT], dos últimos [dias]
  /// (padrão 30) — mesmo gatilho manual de teste/validação do fundador que
  /// [lerFrequenciaCardiacaRecente] já serve, mas com janela em dias, não
  /// horas: peso é um sinal discreto/de baixa frequência (a balança Fitdays
  /// só produz um ponto por pesagem, tipicamente alguns por semana, nunca
  /// contínuo como frequência cardíaca), então uma janela de 24h quase
  /// sempre voltaria vazia mesmo com o dado presente no Health Connect.
  /// Passa pelo mesmo [_lerComPermissao] — mesma checagem de instalação,
  /// mesmo pedido de permissão nativo (aqui, só
  /// `android.permission.health.READ_WEIGHT`, já declarada no Manifest) —
  /// pedindo um único tipo, então não aciona nenhum dos outros sinais que o
  /// app rastreia. Não grava nada.
  Future<HealthSyncResult> lerPesoRecente({int dias = 30}) {
    return _lerComPermissao(
      const [HealthDataType.WEIGHT],
      start: DateTime.now().subtract(Duration(days: dias)),
    );
  }

  /// Leitura pontual, só de [HealthDataType.SLEEP_SESSION], dos últimos
  /// [dias] (padrão 7) — mesmo gatilho manual de teste/validação do
  /// fundador que [lerFrequenciaCardiacaRecente]/[lerPesoRecente] já servem.
  /// Existe para isolar uma dúvida específica (Adendo v5.1): se um backfill
  /// de histórico falhar para um dispositivo/app de terceiros (ex.: uma
  /// balança), este método prova se o problema é o pipeline de leitura
  /// deste app ou o app de terceiros — sessões de sono de um Garmin já
  /// sincronizado servem de referência "conhecida boa" porque o Garmin
  /// mantém histórico contínuo e confiável no Health Connect. Diferente de
  /// [lerFrequenciaCardiacaRecente]/[lerPesoRecente] (que mostram só a
  /// leitura mais recente via [ultimaLeituraOuNula]), quem chama este
  /// método normalmente quer a LISTA inteira de [HealthSyncResult.points]
  /// — provar múltiplas noites, não uma só. Não grava nada.
  Future<HealthSyncResult> lerSonoRecente({int dias = 7}) {
    return _lerComPermissao(
      const [HealthDataType.SLEEP_SESSION],
      start: DateTime.now().subtract(Duration(days: dias)),
    );
  }

  /// O ponto mais recente (`dateTo` mais tardio) dentre [points] — o
  /// "último registro" que a leitura pontual de frequência cardíaca (ou de
  /// peso, ver [lerPesoRecente]) precisa mostrar, já que o Health Connect
  /// pode devolver vários pontos dentro da janela pedida (um por
  /// sincronização do Garmin ou pesagem na balança, por exemplo). `null`
  /// quando a janela não tem nenhum ponto (nenhum wearable/balança
  /// sincronizou o sinal no período).
  static HealthMetricPoint? ultimaLeituraOuNula(List<HealthMetricPoint> points) {
    if (points.isEmpty) return null;
    return points.reduce((a, b) => a.dateTo.isAfter(b.dateTo) ? a : b);
  }

  /// Android-only: routes the user to install Health Connect from the
  /// store. No-op on iOS. Call when a [HealthSyncResult] comes back with
  /// [HealthSyncResult.needsHealthConnectInstall] set.
  Future<void> instalarHealthConnect() => _health.installHealthConnect();

  /// Reads [types] from [start] through now — a janela exata pedida por
  /// quem chama, sem nenhum alinhamento/ajuste próprio. Usado tanto pelos 3
  /// métodos de leitura pontual (`lerFrequenciaCardiacaRecente`/
  /// `lerPesoRecente`/`lerSonoRecente` — não gravam nada, [start] é a
  /// janela exata "últimas 24h"/"7 dias"/"30 dias" que pedem) quanto por
  /// [_lerEGravar] (que já entra aqui com um [start] alinhado à meia-noite
  /// local — ver nota lá; este método não faz esse alinhamento sozinho de
  /// propósito, pra não mudar a janela exata que os 3 métodos de leitura
  /// pontual pedem).
  Future<HealthSyncResult> _lerComPermissao(
    List<HealthDataType> types, {
    required DateTime start,
  }) async {
    await _configured;

    try {
      if (Platform.isAndroid && !(await _health.isHealthConnectAvailable())) {
        return HealthSyncResult.needsInstall(
          i18n.tr('dashboard.health_connect_unavailable'),
        );
      }

      // READ, não READ_WRITE: este serviço nunca chama
      // `Health.writeHealthData` (nem nenhum outro método de escrita) em
      // lugar nenhum — todo o app só LÊ do Health Connect/HealthKit e grava
      // seus próprios dados no Supabase, nunca de volta no health store do
      // SO. Pedir WRITE que nunca é usado é permissão a mais do que o app
      // precisa (achado registrado no RELATÓRIO da tarefa anterior).
      final permissions = List<HealthDataAccess>.filled(
        types.length,
        HealthDataAccess.READ,
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

      final rawPoints = await _health.getHealthDataFromTypes(
        types: types,
        startTime: start,
        endTime: now,
      );

      final points =
          rawPoints.map(HealthMetricPoint.fromHealthDataPoint).toList();

      // Checagem defensiva em primeiro plano: roda inline, como parte do
      // próprio sync, e nunca deixa uma falha de gravação (rede, RLS, sessão
      // ausente) derrubar o resultado da sincronização — é best-effort.
      await _detectarEregistrarAnomalias(points);

      return HealthSyncResult(granted: true, points: points);
    } catch (_) {
      return HealthSyncResult.denied(i18n.tr('dashboard.health_sync_error'));
    }
  }

  /// Scans freshly-synced [points] for readings outside a safe clinical
  /// range — a heart-rate spike/drop while no workout is in progress, or a
  /// critical glucose/blood-pressure reading — and writes each one found as
  /// a structured [EventoAnomaliaSaude] into `eventos_anomalias_saude`
  /// (the "Caixa Preta"). Best-effort: any failure (no session, offline,
  /// RLS) is swallowed so the defensive check never breaks the sync flow.
  Future<void> _detectarEregistrarAnomalias(
    List<HealthMetricPoint> points,
  ) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return;

    final treinos =
        points.where((p) => p.type == HealthDataType.WORKOUT).toList();
    bool emTreino(HealthMetricPoint ponto) => treinos.any(
          (treino) =>
              !ponto.dateFrom.isBefore(treino.dateFrom) &&
              !ponto.dateTo.isAfter(treino.dateTo),
        );

    final anomalias = <EventoAnomaliaSaude>[];

    for (final ponto in points) {
      final payload = ponto.toPayload();
      final origem = ponto.sourceApp.isEmpty ? 'wearable' : ponto.sourceApp;

      // N17/N18: checa frequenciaCardiaca (leitura genérica/contínua), não
      // mais fcRepouso — antes desta tarefa os dois eram o mesmo campo
      // (HEART_RATE só existia como fcRepouso); agora que são sinais
      // distintos, o pico que faz sentido pegar em primeiro plano é o da
      // leitura contínua, não a métrica de repouso do Health Connect
      // (calculada pelo próprio SO, tipicamente durante o sono — chega
      // no máximo 1x/dia e já É esperada estar baixa, não é onde um pico
      // fora de treino apareceria). Comportamento de detecção preservado:
      // é a mesma fonte de dado (HEART_RATE) que já alimentava esta
      // checagem antes, só o nome do campo/parametro que corrige.
      final fc = payload.frequenciaCardiaca;
      if (fc != null && (fc < _fcForaTreinoMin || fc > _fcForaTreinoMax)) {
        final foraDoTreino = !emTreino(ponto);
        if (foraDoTreino) {
          anomalias.add(EventoAnomaliaSaude(
            tipoAnomalia: 'frequencia_cardiaca_fora_faixa',
            parametro: 'frequencia_cardiaca',
            valorDetectado: fc,
            valorLimiteMin: _fcForaTreinoMin,
            valorLimiteMax: _fcForaTreinoMax,
            emTreino: false,
            severidade: (fc < _fcCriticoMin || fc > _fcCriticoMax)
                ? 'critico'
                : 'atencao',
            origem: origem,
            detectadoEm: ponto.dateTo,
          ));
        }
      }

      final glicose = payload.glicoseJejum;
      if (glicose != null &&
          (glicose < _glicoseMin || glicose > _glicoseMax)) {
        anomalias.add(EventoAnomaliaSaude(
          tipoAnomalia: 'glicose_critica',
          parametro: 'glicose_jejum',
          valorDetectado: glicose,
          valorLimiteMin: _glicoseMin,
          valorLimiteMax: _glicoseMax,
          emTreino: emTreino(ponto),
          severidade:
              (glicose < _glicoseCriticoMin || glicose > _glicoseCriticoMax)
                  ? 'critico'
                  : 'atencao',
          origem: origem,
          detectadoEm: ponto.dateTo,
        ));
      }

      final sistolica = payload.pressaoSistolica;
      if (sistolica != null && sistolica > _sistolicaMax) {
        anomalias.add(EventoAnomaliaSaude(
          tipoAnomalia: 'pressao_critica',
          parametro: 'pressao_sistolica',
          valorDetectado: sistolica,
          valorLimiteMax: _sistolicaMax,
          emTreino: emTreino(ponto),
          severidade: sistolica > _sistolicaCriticoMax ? 'critico' : 'atencao',
          origem: origem,
          detectadoEm: ponto.dateTo,
        ));
      }

      final diastolica = payload.pressaoDiastolica;
      if (diastolica != null && diastolica > _diastolicaMax) {
        anomalias.add(EventoAnomaliaSaude(
          tipoAnomalia: 'pressao_critica',
          parametro: 'pressao_diastolica',
          valorDetectado: diastolica,
          valorLimiteMax: _diastolicaMax,
          emTreino: emTreino(ponto),
          severidade:
              diastolica > _diastolicaCriticoMax ? 'critico' : 'atencao',
          origem: origem,
          detectadoEm: ponto.dateTo,
        ));
      }
    }

    if (anomalias.isEmpty) return;

    try {
      await _supabase
          .from('eventos_anomalias_saude')
          .insert(anomalias.map((a) => a.toJson(usuarioId)).toList());
    } on PostgrestException catch (e) {
      debugPrint('Erro ao gravar eventos_anomalias_saude: ${e.message}');
    }
  }

  static const String _chaveUltimaSincronizacao =
      AppConfig.storageKeySyncTimestamp;

  /// Timestamp of the last *successful* [sincronizarDeltaDiario] write, read
  /// from the local cache — `null` means the delta has never run (or its
  /// last attempt never reached [DeltaSyncOutcome.sucesso]/[semAlteracoes]).
  Future<DateTime?> obterUltimaSincronizacao() async {
    final raw = await _secureStorage.read(key: _chaveUltimaSincronizacao);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _registrarUltimaSincronizacao(DateTime quando) {
    return _secureStorage.write(
      key: _chaveUltimaSincronizacao,
      value: quando.toIso8601String(),
    );
  }

  /// Delta Diário (Onda 1.5): reads only what the health store produced
  /// since the last successful sync (falling back to the last 24h the very
  /// first time it runs), maps every point directly onto
  /// `metricas_saude_diarias`'s fixed columns, runs the same "Caixa Preta"
  /// anomaly check as the initial backfill, and advances the last-sync
  /// cursor only once the write actually lands on the server.
  ///
  /// Called both from the nightly `sync_diario_wearables` background task
  /// and, in foreground, from `SyncUiController.forcarSincronizacaoAtleta`
  /// (the manual/opportunistic path) — same method, same cursor, so neither
  /// path can duplicate or skip a day's data relative to the other.
  Future<DeltaSyncResult> sincronizarDeltaDiario() async {
    final desde = await obterUltimaSincronizacao() ??
        DateTime.now().subtract(const Duration(hours: 24));
    return _lerEGravar(_tiposSuportados, start: desde);
  }

  /// Núcleo comum de leitura+merge+upsert+cursor compartilhado por
  /// [sincronizarDeltaDiario] (janela = desde o último sync, ou 24h da
  /// primeira vez) e [carregarHistoricoInicial] (janela = [dias] fixos,
  /// tipicamente 30). As duas só diferem em COMO calculam a janela — todo o
  /// resto (permissão, leitura, merge por dia, upsert idempotente, avanço do
  /// cursor de última sincronização) é idêntico, e extrair para um só lugar
  /// garante que as duas nunca possam divergir em como gravam
  /// (idempotência, tratamento de offline, etc.).
  Future<DeltaSyncResult> _lerEGravar(
    List<HealthDataType> types, {
    int? dias,
    DateTime? start,
  }) async {
    await _configured;

    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return DeltaSyncResult(
        outcome: DeltaSyncOutcome.erro,
        errorMessage: i18n.tr('dashboard.health_sync_error'),
      );
    }

    // CAUSA RAIZ do bug "passos/sono com fuso errado" (RELATÓRIO 20260811,
    // corrigindo a tentativa anterior do RELATÓRIO 20260810): a consulta
    // agregada nativa do Health Connect (`getHealthIntervalDataFromTypes`,
    // `AggregateGroupByDurationRequest` do lado Kotlin) fatiava o período em
    // blocos de N segundos usando aritmética de `Instant` (UTC/absoluta),
    // NÃO alinhada à meia-noite do fuso local do aparelho — um bloco de
    // 86400s começando a qualquer hora que não seja exatamente meia-noite
    // UTC corta passos da madrugada de um dia junto com a manhã do outro.
    // Abandonado por completo: de volta para `getHealthDataFromTypes`
    // (leitura crua) — mas alinhando a janela aqui, só no caminho de
    // sincronização/gravação (não em [_lerComPermissao] diretamente, para
    // não mudar a janela exata que os 3 métodos de leitura pontual pedem —
    // ver doc de [_lerComPermissao]). `DateTime.fromMillisecondsSinceEpoch`
    // (usado pelo pacote `health` para construir dateFrom/dateTo) já devolve
    // horário local, então bucketizar por dia em Dart
    // (`_dataOnly`/`_dataDoSonoLocal` em [_mesclarPorDia]) é correto por
    // construção — o problema nunca esteve aí, só na fatia nativa em UTC.
    final agoraParaJanela = DateTime.now();
    final inicioBruto =
        start ?? agoraParaJanela.subtract(Duration(days: dias ?? 30));
    final inicioAlinhado =
        DateTime(inicioBruto.year, inicioBruto.month, inicioBruto.day);

    final leitura = await _lerComPermissao(types, start: inicioAlinhado);
    if (!leitura.granted) {
      return DeltaSyncResult(
        outcome: DeltaSyncOutcome.permissaoNegada,
        errorMessage: leitura.errorMessage,
        needsHealthConnectInstall: leitura.needsHealthConnectInstall,
      );
    }

    final payloads = leitura.toPayloads();
    if (payloads.isEmpty) {
      final agora = DateTime.now();
      await _registrarUltimaSincronizacao(agora);
      return DeltaSyncResult(
        outcome: DeltaSyncOutcome.semAlteracoes,
        sincronizadoEm: agora,
      );
    }

    final linhas = _mesclarPorDia(usuarioId, payloads);
    final envio = await _enviarLinhas(linhas);

    if (envio == DeltaSyncOutcome.sucesso) {
      final agora = DateTime.now();
      await _registrarUltimaSincronizacao(agora);
      return DeltaSyncResult(
        outcome: DeltaSyncOutcome.sucesso,
        linhas: linhas,
        sincronizadoEm: agora,
      );
    }

    return DeltaSyncResult(
      outcome: envio,
      linhas: linhas,
      errorMessage: envio == DeltaSyncOutcome.erro
          ? i18n.tr('dashboard.sync_error')
          : null,
    );
  }

  /// Dispatches previously-queued fixed-column rows (see
  /// `SyncUiController`'s offline queue) once connectivity is back. Unlike
  /// [sincronizarDeltaDiario], this never touches the health store — the
  /// rows were already read, merged and cached locally while offline; this
  /// only retries the Supabase write and, on success, advances the
  /// last-sync cursor so a subsequent delta doesn't re-read the same range.
  Future<bool> despacharLinhasPendentes(List<Map<String, dynamic>> linhas) async {
    if (linhas.isEmpty) return true;
    final envio = await _enviarLinhas(linhas);
    if (envio != DeltaSyncOutcome.sucesso) return false;
    await _registrarUltimaSincronizacao(DateTime.now());
    return true;
  }

  Future<DeltaSyncOutcome> _enviarLinhas(List<Map<String, dynamic>> linhas) async {
    try {
      await _supabase.from('metricas_saude_diarias').upsert(
        linhas,
        onConflict: 'usuario_id_anonimo,data_referencia',
      );
      return DeltaSyncOutcome.sucesso;
    } on SocketException {
      return DeltaSyncOutcome.offline;
    } on http.ClientException {
      return DeltaSyncOutcome.offline;
    } on PostgrestException catch (e) {
      debugPrint('Erro ao gravar metricas_saude_diarias: ${e.message}');
      return DeltaSyncOutcome.erro;
    }
  }

  /// Merges [payloads] — each one carrying a single fixed column, per
  /// [HealthMetricPoint.toPayload] — into one row per calendar day, since
  /// `metricas_saude_diarias` has a `unique (usuario_id_anonimo,
  /// data_referencia)` constraint a single upsert batch can't violate twice.
  ///
  /// Quatro estratégias de junção, uma por natureza de sinal:
  ///   - **Maior fonte do dia** (passos, calorias ativas): CORRIGIDO NO
  ///     RELATÓRIO 20260810/reafirmado no 20260811. Somar todo ponto do dia
  ///     (como este código fazia antes de qualquer correção) conta em dobro
  ///     quando mais de uma fonte grava o mesmo intervalo — celular E
  ///     relógio ambos contando os mesmos passos. Em vez de somar TODAS as
  ///     fontes, soma cada fonte separadamente e fica com a MAIOR — não com
  ///     a soma delas. Evita o double-count sem hardcodar o nome de um
  ///     fabricante específico (Garmin hoje, outro relógio amanhã): duas
  ///     fontes tentando cobrir o mesmo dia inteiro deveriam relatar totais
  ///     parecidos — o maior tende a ser o mais completo; era a SOMA que
  ///     estava errada, não uma fonte específica sendo "a certa".
  ///   - **Somados por estágio, bucketizados pela manhã do despertar**
  ///     (sono_leve/profundo/rem/acordado_minutos): CORRIGIDO NESTA TAREFA.
  ///     Cada estágio já vem granular do Health Connect (ver [todosOsTipos])
  ///     — soma normalmente dentro do MESMO dia. A parte não-óbvia é QUAL
  ///     dia: um estágio às 23h de segunda pertence à noite de sono que só
  ///     termina terça de manhã, não ao "dia de segunda" que `_dataOnly`
  ///     daria. Ver [_dataDoSonoLocal].
  ///   - **Somados normais** (distância): não sofre o mesmo double-counting
  ///     dos passos/calorias na prática (fundador confirmou correta) — sem
  ///     motivo pra mudar.
  ///   - **Média aritmética** (frequência cardíaca genérica — `fc`, NÃO
  ///     `fc_repouso`): mesma correção do RELATÓRIO 20260810, inalterada
  ///     aqui.
  ///   - **Última leitura** (fc_repouso, peso, HRV, pressão, glicose, ...):
  ///     sinais pontuais/de baixa frequência — a leitura mais recente do dia
  ///     é o que importa.
  List<Map<String, dynamic>> _mesclarPorDia(
    String usuarioId,
    List<HealthPayloadModel> payloads,
  ) {
    final porDia = <String, Map<String, dynamic>>{};
    final somaFcPorDia = <String, double>{};
    final contagemFcPorDia = <String, int>{};
    final passosPorDiaFonte = <String, Map<String, num>>{};
    final caloriasPorDiaFonte = <String, Map<String, num>>{};

    for (final payload in payloads) {
      final ehSono = payload.sonoLeveMinutos != null ||
          payload.sonoProfundoMinutos != null ||
          payload.sonoRemMinutos != null ||
          payload.sonoAcordadoMinutos != null;
      final dataReferencia = ehSono
          ? _dataDoSonoLocal(payload.dateFrom)
          : _dataOnly(payload.dateFrom);

      final linha = porDia.putIfAbsent(
        dataReferencia,
        () => {
          'usuario_id_anonimo': usuarioId,
          'data_referencia': dataReferencia,
          'origem': payload.source,
        },
      );

      void somar(String coluna, num? valor) {
        if (valor == null) return;
        linha[coluna] = ((linha[coluna] as num?) ?? 0) + valor;
      }

      void sobrescrever(String coluna, num? valor) {
        if (valor == null) return;
        linha[coluna] = valor;
      }

      if (payload.passos != null) {
        final porFonte = passosPorDiaFonte.putIfAbsent(dataReferencia, () => {});
        porFonte[payload.source] = (porFonte[payload.source] ?? 0) + payload.passos!;
      }
      if (payload.caloriasAtivas != null) {
        final porFonte = caloriasPorDiaFonte.putIfAbsent(dataReferencia, () => {});
        porFonte[payload.source] =
            (porFonte[payload.source] ?? 0) + payload.caloriasAtivas!;
      }
      somar('distancia_metros', payload.distanciaMetros);
      somar('sono_leve_minutos', payload.sonoLeveMinutos);
      somar('sono_profundo_minutos', payload.sonoProfundoMinutos);
      somar('sono_rem_minutos', payload.sonoRemMinutos);
      somar('sono_acordado_minutos', payload.sonoAcordadoMinutos);

      if (payload.frequenciaCardiaca != null) {
        somaFcPorDia[dataReferencia] =
            (somaFcPorDia[dataReferencia] ?? 0) + payload.frequenciaCardiaca!;
        contagemFcPorDia[dataReferencia] =
            (contagemFcPorDia[dataReferencia] ?? 0) + 1;
      }
      sobrescrever('fc_repouso', payload.fcRepouso);
      sobrescrever('hrv_medio', payload.hrvMedio);
      sobrescrever('peso_kg', payload.pesoKg);
      sobrescrever('massa_magra_kg', payload.massaMagraKg);
      sobrescrever('percentual_gordura', payload.percentualGordura);
      sobrescrever('pressao_sistolica', payload.pressaoSistolica);
      sobrescrever('pressao_diastolica', payload.pressaoDiastolica);
      sobrescrever('glicose_jejum', payload.glicoseJejum);
      sobrescrever('saturacao_oxigenio', payload.saturacaoOxigenio);
      sobrescrever('temperatura_corporal', payload.temperaturaCorporal);
    }

    void aplicarMaiorFonte(
      Map<String, Map<String, num>> porDiaFonte,
      String coluna, {
      required bool arredondar,
    }) {
      for (final entry in porDiaFonte.entries) {
        final maiorFonte = entry.value.values.reduce((a, b) => a > b ? a : b);
        porDia[entry.key]![coluna] =
            arredondar ? maiorFonte.round() : maiorFonte;
      }
    }

    aplicarMaiorFonte(passosPorDiaFonte, 'passos', arredondar: true);
    aplicarMaiorFonte(caloriasPorDiaFonte, 'calorias_ativas', arredondar: false);

    // Fecha a média de FC por último — precisa de todos os pontos do dia
    // somados antes de dividir pela contagem.
    for (final entry in somaFcPorDia.entries) {
      final dataReferencia = entry.key;
      final contagem = contagemFcPorDia[dataReferencia]!;
      porDia[dataReferencia]!['frequencia_cardiaca'] =
          (entry.value / contagem).round();
    }

    // sono_total (coluna minutos_sono, já existente) = ESTRITAMENTE
    // leve + profundo + REM — nunca soma sono_acordado_minutos (pedido
    // explícito da tarefa). Só grava a coluna em dias que realmente tiveram
    // algum estágio de sono lido, mesmo padrão de `somar` (não escreve 0
    // para um dia sem dado nenhum de sono).
    for (final linha in porDia.values) {
      final temSono = linha.containsKey('sono_leve_minutos') ||
          linha.containsKey('sono_profundo_minutos') ||
          linha.containsKey('sono_rem_minutos');
      if (!temSono) continue;
      final leve = (linha['sono_leve_minutos'] as num?) ?? 0;
      final profundo = (linha['sono_profundo_minutos'] as num?) ?? 0;
      final rem = (linha['sono_rem_minutos'] as num?) ?? 0;
      linha['minutos_sono'] = leve + profundo + rem;
    }

    return porDia.values.toList();
  }

  static String _dataOnly(DateTime date) =>
      date.toIso8601String().split('T').first;

  /// Bucketiza um instante de estágio de sono na data (LOCAL) da manhã em
  /// que a pessoa acordou, não no dia calendário em que o instante caiu.
  /// Heurística deliberada (documentada, não chutada): sono que começa às
  /// 15h ou depois pertence à noite que leva à manhã seguinte — cobre o
  /// padrão comum (dormir à noite, acordar de manhã) sem precisar
  /// reconstruir a SleepSessionRecord inteira a partir dos estágios
  /// espalhados que o Health Connect devolve. Sono às 15h ou depois de
  /// segunda conta para terça; sono entre meia-noite e 15h de terça (o
  /// resto da mesma noite, já depois da virada) também conta para terça.
  /// Limitação conhecida, registrada no RELATÓRIO: não modela cochilos à
  /// tarde nem rotina de trabalho noturno — reavaliar se algum dia isso
  /// virar um caso real.
  static String _dataDoSonoLocal(DateTime instante) {
    final data = instante.hour >= 15
        ? instante.add(const Duration(days: 1))
        : instante;
    return _dataOnly(DateTime(data.year, data.month, data.day));
  }
}
