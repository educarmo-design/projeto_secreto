import 'dart:io';
import 'dart:math' as math;

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
///
/// [sourceId] existe só para a Hierarquia de Fontes (RELATÓRIO
/// 20260810_0007) — achado real ao ler o código nativo do pacote `health`
/// (não adivinhado): as duas plataformas preenchem `source_id`/`source_name`
/// de jeitos DIFERENTES:
///   - **Android** (`HealthDataConverter.kt`/`HealthDataReader.kt`):
///     `source_id` é SEMPRE `""` (string vazia, hardcoded); quem carrega o
///     nome do pacote (`metadata.dataOrigin.packageName`, ex.:
///     `com.garmin.android.apps.connectmobile`) é `source_name`.
///   - **iOS** (`HealthDataReader.swift`): `source_id` é o
///     `sourceRevision.source.bundleIdentifier` de verdade (ex.:
///     `com.apple.health`); `source_name` é o nome amigável
///     (`sourceRevision.source.name`, ex.: "Health"/"Garmin Connect").
/// Ou seja, o campo que carrega o identificador de pacote/bundle "de
/// verdade" TROCA de plataforma para plataforma. [identificadorFonte]
/// resolve isso: usa `sourceId` quando não está vazio (iOS), cai para
/// `sourceApp` quando está (Android) — funciona nos dois sistemas sem
/// nenhum `Platform.isIOS` espalhado pelo código de classificação.
class HealthMetricPoint {
  final HealthDataType type;
  final double value;
  final String unit;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String sourceApp;
  final String sourceId;

  /// O [HealthValue] ORIGINAL, sem achatar — RELATÓRIO 20260811_0002
  /// (Treinos/Rotas). [value] só existe pra tipos numéricos
  /// (`NumericHealthValue`); WORKOUT (`WorkoutHealthValue`: tipo de
  /// atividade, energia/distância/passos totais) e WORKOUT_ROUTE
  /// (`WorkoutRouteHealthValue`: lista de pontos GPS) carregam dados
  /// estruturados que [value] simplesmente descarta (vira `0`). Nenhum
  /// código anterior a esta tarefa precisava do valor cru, por isso não
  /// existia; `HealthSyncService._processarTreinos` é o único lugar que lê
  /// este campo.
  final HealthValue rawValue;

  const HealthMetricPoint({
    required this.type,
    required this.value,
    required this.unit,
    required this.dateFrom,
    required this.dateTo,
    required this.sourceApp,
    required this.rawValue,
    this.sourceId = '',
  });

  /// Ver doc da classe — Android deixa `sourceId` vazio, iOS deixa
  /// `sourceApp` como o nome amigável (não o bundle id). Este é o único
  /// identificador que a Hierarquia de Fontes ([HealthSyncService.
  /// _classificarPrioridadeFonte]) usa para reconhecer pacotes nativos.
  String get identificadorFonte => sourceId.isNotEmpty ? sourceId : sourceApp;

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
      sourceId: point.sourceId,
      rawValue: rawValue,
    );
  }

  /// Converts to the normalized [HealthPayloadModel] shape shared with the
  /// camera/AI extraction path — the fixed-column shape written to
  /// `metricas_saude_diarias` alongside camera-origin readings.
  ///
  /// `source:` carrega [identificadorFonte] (pacote/bundle id quando
  /// disponível), não [sourceApp] cru — é o valor usado tanto para
  /// agrupar por fonte em `_mesclarPorDia` quanto para a Hierarquia de
  /// Fontes reconhecer pedômetros nativos.
  HealthPayloadModel toPayload() => HealthPayloadModel.fromHealthDataType(
    type: type,
    value: value,
    dateFrom: dateFrom,
    dateTo: dateTo,
    source: identificadorFonte.isEmpty ? 'wearable' : identificadorFonte,
  );
}

/// Acumulador de passos+distância de UMA fonte, num ÚNICO dia — Hierarquia
/// de Fontes (RELATÓRIO 20260810_0007). `null` (não zero) enquanto a fonte
/// nunca reportou aquela métrica no dia — distingue "esta fonte não mede
/// distância" de "esta fonte mediu 0 metros", igual ao resto do
/// `_mesclarPorDia`/[HealthPayloadModel] (campo ausente ≠ campo zerado).
class _AgregadoFonte {
  num? passos;
  num? distanciaMetros;
}

/// Ver doc de [HealthSyncService._buscarAlturaMetros].
class _AlturaResultado {
  const _AlturaResultado({required this.alturaMetros, required this.sucesso});
  final double? alturaMetros;
  final bool sucesso;
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
  ///
  /// RELATÓRIO 20260813_0015 (Parte 1 — Proteção Extrema no Parsing): era
  /// `points.map((point) => point.toPayload()).where(...).toList()` — o
  /// mesmo risco do `.map().toList()` de [HealthMetricPoint.
  /// fromHealthDataPoint] (ver `_lerComPermissao`): `toPayload()` faz
  /// `.round()` em cima de um `double` (ex.: calorias basais, passos) —
  /// se o plugin nativo alguma vez devolver `NaN`/`Infinity` (valor
  /// numericamente "válido" mas sem cast seguro pra inteiro), `.round()`
  /// lança `UnsupportedError`, e ISSO propagava pro `.map()` inteiro:
  /// um único ponto ruim jogava fora TODOS os payloads do lote, de
  /// QUALQUER dia — exatamente o "distância zerada/ausente em vários dias"
  /// relatado em device físico. Loop explícito com try/catch por ponto: um
  /// ponto ruim é pulado e logado, os demais seguem normais.
  List<HealthPayloadModel> toPayloads() {
    final payloads = <HealthPayloadModel>[];
    for (final point in points) {
      try {
        final payload = point.toPayload();
        if (!payload.isEmpty) payloads.add(payload);
      } catch (e, stackTrace) {
        debugPrint(
          '[SYNC_DIAGNOSTICO] Falha ao converter 1 ponto pra payload '
          '(${point.type.name}, valor bruto ${point.value} '
          '[${point.rawValue.runtimeType}], fonte "${point.sourceApp}") — '
          'pulado, os demais pontos do lote continuam sendo processados: '
          '$e\n$stackTrace',
        );
      }
    }
    return payloads;
  }
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
    // RELATÓRIO 20260819_0020, pedido do fundador — andares subidos, métrica
    // diária cumulativa (mesmo tratamento anti-double-counting de
    // calorias_ativas: "maior fonte do dia", não a Hierarquia de Fontes de
    // passos/distância — floors não precisa vir emparelhado com nenhuma
    // outra métrica). Mapeia pra FloorsClimbedRecord do Health Connect.
    HealthDataType.FLIGHTS_CLIMBED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    // Calorias granulares (RELATÓRIO 20260811_0002, decisão do fundador) —
    // metabolismo basal/repouso, sinal separado de ACTIVE_ENERGY_BURNED.
    HealthDataType.BASAL_ENERGY_BURNED,
    // RELATÓRIO 20260819_0020 — ACHADO REAL (stack trace capturada em
    // device físico via logcat): o pacote `health` lê TotalCaloriesBurnedRecord
    // por baixo dos panos ao processar HealthDataType.WORKOUT (pra calcular
    // a energia queimada de cada sessão) — sem a permissão
    // READ_TOTAL_CALORIES_BURNED no Manifest, essa leitura interna lançava
    // SecurityException e derrubava a leitura do WORKOUT INTEIRO (é por
    // isso que treino nunca aparecia na tela nem gravava no banco, não era
    // um bug de parsing do lado Dart). Adicionar o tipo aqui, além de
    // corrigir os treinos, destrava calorias totais como leitura direta do
    // wearable (Garmin publica esse registro agregado continuamente,
    // inclusive em dias sem pesagem/sem treino — diferente de
    // BASAL_ENERGY_BURNED, que o Garmin nunca publica, ver RELATÓRIO
    // 20260813_0019). Nota anterior (RELATÓRIO 20260810_0007/spike) dizia
    // que TOTAL_CALORIES_BURNED "não tem implementação real no iOS do
    // pacote health" — segue verdade lá (HealthSyncService._mesclarPorDia
    // preserva o fallback ativas+basais quando a leitura direta vem
    // ausente), mas nunca foi um problema no Android, onde este app roda de
    // verdade hoje.
    HealthDataType.TOTAL_CALORIES_BURNED,
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
    // RELATÓRIO 20260810_0003 (spike) mapeou os dois como disponíveis no
    // Android/Health Connect — água corporal (balanças de bioimpedância) e
    // IMC (só quando o dispositivo/app de origem já publica pronto; senão
    // [_aplicarInferenciasCruzadas] calcula depois do merge por dia).
    HealthDataType.BODY_WATER_MASS,
    HealthDataType.BODY_MASS_INDEX,
    HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
    HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    HealthDataType.BLOOD_GLUCOSE,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.BODY_TEMPERATURE,
    HealthDataType.WORKOUT,
    // Treinos/Rotas (RELATÓRIO 20260811_0002, decisão do fundador) — rota
    // GPS de cada WORKOUT. No Android, ler rota exige um consentimento
    // extra POR SESSÃO do próprio Health Connect (ExerciseRouteResult.
    // ConsentRequired) — não é uma permissão estática de manifest, é um
    // fluxo dinâmico; quando negado, o pacote devolve a rota com 0 pontos
    // (indistinguível de "esse treino não tem rota" no lado Dart — ver
    // HealthSyncService._processarTreinos), então o app já lida com isso
    // de graça, sem checagem especial.
    HealthDataType.WORKOUT_ROUTE,
    // RELATÓRIO 20260819_0020, pedido do fundador — velocidade. Série
    // contínua (mesmo perfil de HEART_RATE), por isso tratada igual à FC
    // dentro de um treino em [_processarTreinos] (média/mínima/máxima
    // filtradas pelo intervalo exato da sessão), não como métrica diária
    // solta em metricas_saude_diarias — "velocidade do dia" sozinha não é
    // um conceito com sentido de produto, velocidade de um treino é.
    // Mapeia pra SpeedRecord do Health Connect.
    HealthDataType.SPEED,
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

  /// Modo de Diagnóstico Profundo (RELATÓRIO 20260813_0015, decisão do
  /// fundador) — botão "GERAR LOG DIAGNÓSTICO (30 DIAS)" da tela de
  /// histórico. Reaproveita o MESMO [_lerEGravar] de [carregarHistoricoInicial]
  /// (mesma permissão de histórico, mesma janela de 30 dias, mesmo
  /// merge+upsert real — este NÃO é um modo "só leitura", ele sincroniza de
  /// verdade) só com `diagnosticoProfundo: true`, que liga o log verboso
  /// ponto-a-ponto em [_logDiagnosticoProfundo] — desligado por padrão em
  /// todo o resto do app (delta diário automático, carga inicial ao
  /// conectar wearable) porque é verboso demais pra rodar toda vez.
  Future<DeltaSyncResult> executarDiagnosticoProfundo({int dias = 30}) async {
    await _configured;
    await _garantirPermissaoHistorico();
    return _lerEGravar(_tiposSuportados, dias: dias, diagnosticoProfundo: true);
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
    bool diagnosticoProfundo = false,
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

      _logRaioX(rawPoints);

      // RELATÓRIO 20260813_0015 (Parte 1 — Proteção Extrema no Parsing):
      // era `rawPoints.map(HealthMetricPoint.fromHealthDataPoint).toList()`
      // — um `.map().toList()` avalia TODO ponto de uma vez; se UM único
      // ponto do lote lançasse (ex.: um cast numérico ruim vindo do
      // plugin nativo), o `.toList()` inteiro lançava e NENHUM ponto do
      // lote — de nenhum dia, de nenhum tipo — chegava a ser processado.
      // Loop explícito com try/catch POR PONTO: um ponto ruim é pulado e
      // logado, os demais (do mesmo dia ou de outros) continuam normais.
      final points = <HealthMetricPoint>[];
      for (final rawPoint in rawPoints) {
        try {
          points.add(HealthMetricPoint.fromHealthDataPoint(rawPoint));
        } catch (e, stackTrace) {
          debugPrint(
            '[SYNC_DIAGNOSTICO] Falha ao converter 1 ponto bruto '
            '(${rawPoint.type.name}, fonte "${rawPoint.sourceName}", '
            'valor bruto ${rawPoint.value} [${rawPoint.value.runtimeType}]) — '
            'pulado, os demais pontos do lote continuam sendo processados: '
            '$e\n$stackTrace',
          );
        }
      }

      if (diagnosticoProfundo) {
        _logDiagnosticoProfundo(points, start, now);
      }

      // Checagem defensiva em primeiro plano: roda inline, como parte do
      // próprio sync, e nunca deixa uma falha de gravação (rede, RLS, sessão
      // ausente) derrubar o resultado da sincronização — é best-effort.
      await _detectarEregistrarAnomalias(points);

      return HealthSyncResult(granted: true, points: points);
    } catch (e, stackTrace) {
      // RELATÓRIO 20260813_0014 — ACHADO: este catch engolia QUALQUER
      // exceção (rede, parsing de um HealthDataPoint malformado, plugin
      // nativo) sem nenhum rastro — nem `debugPrint`, nem o `e` original.
      // O chamador ([_lerEGravar]) trata `granted: false` como "permissão
      // negada" e aborta o lote inteiro (nenhuma coluna é gravada, nem
      // passos/distância que não têm nada a ver com a causa real da
      // falha) — um erro de rede pontual virava, pro fundador, "a
      // sincronização parou", sem nenhum log pra investigar por quê. Não
      // muda o comportamento (ainda devolve `denied`, best-effort igual
      // antes) — só passa a expor o erro de verdade no console.
      debugPrint('HealthSyncService: falha ao ler do health store: $e\n$stackTrace');
      return HealthSyncResult.denied(i18n.tr('dashboard.health_sync_error'));
    }
  }

  /// ⚠️ ACHADO REGULATÓRIO (RELATÓRIO desta tarefa, N17/N18 — não corrigido
  /// aqui, fora do escopo/ARQUIVOS pedidos): a restrição desta tarefa diz
  /// "Fica ESTRITAMENTE PROIBIDA a implementação de detecção de anomalias
  /// cardíacas (eventos de FC fora do normal). Isso pertence ao Motor
  /// Clínico (F02), que está no Backlog." Este método FAZ EXATAMENTE ISSO
  /// para FC (`frequencia_cardiaca_fora_faixa`, ver abaixo) — já existia
  /// antes desta tarefa (Adendo v5.1, "Caixa Preta"), não foi criado por
  /// mim. Nenhum código NOVO desta tarefa adiciona lógica de anomalia — só
  /// grava métricas absolutas (média/máxima/repouso/HRV), como pedido. Não
  /// removi/desliguei esta detecção pré-existente unilateralmente: é uma
  /// mudança de escopo maior (a "Caixa Preta" também alimenta o Módulo de
  /// Inteligência, ver doc de [EventoAnomaliaSaude.fromJson]) que precisa de
  /// decisão explícita do fundador — ver RELATÓRIO/resposta desta tarefa.
  ///
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

    // RELATÓRIO 20260813_0015 (Parte 1 — Proteção Extrema no Parsing):
    // ACHADO REAL, não hipotético — `ponto.toPayload()` sem try/catch
    // aqui era o terceiro (e mais grave) lugar com o mesmo risco de
    // [HealthSyncResult.toPayloads()]: um único ponto com valor NaN/
    // Infinity (ex.: STEPS, que usa `.round()`) lançava DENTRO de
    // `_lerComPermissao` — ANTES do método sequer retornar — e o catch
    // externo dele (RELATÓRIO 20260813_0014) tratava isso como "permissão
    // negada", abortando o LOTE INTEIRO (todos os dias, todos os tipos:
    // distância, calorias basais, peso, treinos — bate exatamente com o
    // sintoma relatado em device físico). Confirmado escrevendo o teste
    // antes da correção: um único ponto ruim derrubava até dias/campos
    // completamente sem relação com ele. Try/catch por ponto: um ponto
    // ruim é pulado e logado, a checagem de anomalia segue pros demais.
    for (final ponto in points) {
      try {
        final payload = ponto.toPayload();
        final origem = ponto.sourceApp.isEmpty ? 'wearable' : ponto.sourceApp;

        // N17/N18: checa frequenciaCardiaca (leitura genérica/contínua),
        // não mais fcRepouso — antes desta tarefa os dois eram o mesmo
        // campo (HEART_RATE só existia como fcRepouso); agora que são
        // sinais distintos, o pico que faz sentido pegar em primeiro
        // plano é o da leitura contínua, não a métrica de repouso do
        // Health Connect (calculada pelo próprio SO, tipicamente durante
        // o sono — chega no máximo 1x/dia e já É esperada estar baixa,
        // não é onde um pico fora de treino apareceria). Comportamento de
        // detecção preservado: é a mesma fonte de dado (HEART_RATE) que
        // já alimentava esta checagem antes, só o nome do campo/parametro
        // que corrige.
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
            severidade:
                sistolica > _sistolicaCriticoMax ? 'critico' : 'atencao',
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
      } catch (e, stackTrace) {
        debugPrint(
          '[SYNC_DIAGNOSTICO] Falha ao checar anomalia de 1 ponto '
          '(${ponto.type.name}, valor bruto ${ponto.value} '
          '[${ponto.rawValue.runtimeType}]) — pulado, os demais pontos '
          'continuam sendo checados: $e\n$stackTrace',
        );
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
    bool diagnosticoProfundo = false,
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

    final leitura = await _lerComPermissao(
      types,
      start: inicioAlinhado,
      diagnosticoProfundo: diagnosticoProfundo,
    );
    if (!leitura.granted) {
      return DeltaSyncResult(
        outcome: DeltaSyncOutcome.permissaoNegada,
        errorMessage: leitura.errorMessage,
        needsHealthConnectInstall: leitura.needsHealthConnectInstall,
      );
    }

    // Treinos/Rotas (RELATÓRIO 20260811_0002) — roda sobre leitura.points
    // (cru, com HealthMetricPoint.rawValue), não sobre `payloads`:
    // WORKOUT/WORKOUT_ROUTE não mapeiam pra nenhum campo de
    // HealthPayloadModel (toPayloads() os filtra fora por isEmpty), então
    // se o lote só tivesse treino e nada mais, `payloads.isEmpty` abaixo
    // sairia cedo demais e o treino nunca seria processado. Best-effort,
    // mesmo espírito de _detectarEregistrarAnomalias: nunca derruba o sync
    // principal.
    await _processarTreinos(usuarioId, leitura.points);

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
    await _aplicarInferenciasCruzadas(usuarioId, linhas);
    await _preencherDistanciaFaltante(linhas, inicioAlinhado);
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

  /// BUG CRÍTICO CORRIGIDO NESTA TAREFA — "Upsert Destrutivo" (RELATÓRIO
  /// 20260811_0002, confirmado no teste físico: dados de dias anteriores
  /// sumindo/sendo zerados, distância e calorias somem em dias aleatórios).
  ///
  /// Achado real, não suposição: cada linha de [linhas] só tem as colunas
  /// que aquele dia realmente teve dado — `_mesclarPorDia` nunca escreve
  /// uma coluna sem valor (é assim desde sempre, é o padrão certo). O
  /// problema nunca foi ESSA parte. O problema é que a versão anterior
  /// deste método mandava TODAS as linhas do lote (até 30, numa Carga
  /// Inicial) num ÚNICO `.upsert(linhas)`. Quando dois dias do MESMO lote
  /// têm conjuntos de colunas DIFERENTES (ex.: dia A só teve passos, dia B
  /// só teve peso), o PostgREST precisa gerar UM `INSERT ... VALUES (...),
  /// (...) ON CONFLICT DO UPDATE` só, com uma lista de colunas ÚNICA pra
  /// todas as linhas — e por padrão (`defaultToNull: true`, o padrão do
  /// pacote `postgrest`), preenche a coluna que uma linha não tem com
  /// `NULL` explícito, mesmo que a coluna já tivesse um valor bom gravado
  /// no banco de um sync anterior. Confirmado lendo o teste
  /// `bulk insert without column defaults` do próprio pacote `postgrest`
  /// (`test/basic_test.dart`) — a linha que omite uma coluna que a OUTRA
  /// linha do mesmo lote tem recebe `null`, mesmo a coluna tendo um
  /// default de verdade no schema. `defaultToNull: false` NÃO resolve
  /// aqui: nenhuma coluna de `metricas_saude_diarias` (`passos`,
  /// `distancia_metros`, `calorias_ativas`, `imc`, ...) tem `DEFAULT`
  /// declarado no schema — "usar o default" ainda resultaria em `NULL`.
  ///
  /// Correção definitiva: um `.upsert()` POR LINHA. Sem outras linhas no
  /// mesmo request, não existe união de colunas pra preencher — o
  /// PostgREST só enxerga as colunas que aquele dia específico realmente
  /// tem. Efeito colateral positivo (não regressão): se uma linha no meio
  /// do lote falhar, as anteriores já gravadas continuam gravadas — antes,
  /// uma falha em QUALQUER linha descartava o lote inteiro.
  Future<DeltaSyncOutcome> _enviarLinhas(List<Map<String, dynamic>> linhas) async {
    for (final linha in linhas) {
      try {
        await _supabase.from('metricas_saude_diarias').upsert(
          linha,
          onConflict: 'usuario_id_anonimo,data_referencia',
        );
      } on SocketException {
        return DeltaSyncOutcome.offline;
      } on http.ClientException {
        return DeltaSyncOutcome.offline;
      } on PostgrestException catch (e) {
        debugPrint(
          'Erro ao gravar metricas_saude_diarias (${linha['data_referencia']}): ${e.message}',
        );
        return DeltaSyncOutcome.erro;
      }
    }
    return DeltaSyncOutcome.sucesso;
  }

  /// Merges [payloads] — each one carrying a single fixed column, per
  /// [HealthMetricPoint.toPayload] — into one row per calendar day, since
  /// `metricas_saude_diarias` has a `unique (usuario_id_anonimo,
  /// data_referencia)` constraint a single upsert batch can't violate twice.
  ///
  /// Cinco estratégias de junção, uma por natureza de sinal:
  ///   - **Fonte Vencedora do dia** (passos + distância, SEMPRE juntos):
  ///     Hierarquia de Fontes, RELATÓRIO 20260810_0007. Somar todo ponto do
  ///     dia (o que este código fazia antes de qualquer correção) conta em
  ///     dobro quando mais de uma fonte grava o mesmo intervalo — celular E
  ///     relógio ambos contando os mesmos passos. Escolher a "maior fonte"
  ///     PARA CADA MÉTRICA SEPARADAMENTE (correção anterior, RELATÓRIO
  ///     20260810_0006) resolvia o double-count mas abria um bug novo:
  ///     passos podiam vir do pedômetro do celular e distância do Garmin no
  ///     MESMO dia — dois aparelhos diferentes, proporção passos/distância
  ///     sem sentido biológico. A partir desta tarefa as duas métricas
  ///     escolhem a fonte JUNTAS: prioridade alta (qualquer fonte que não
  ///     seja um pedômetro nativo reconhecido — ver [_ehPedometroNativo])
  ///     ganha de prioridade baixa; dentro da mesma prioridade, quem tem
  ///     mais passos vence. Passos E distância desse dia saem OS DOIS da
  ///     mesma fonte vencedora — nunca misturados.
  ///   - **Maior fonte do dia** (só calorias ativas, sozinha): mesma lógica
  ///     de double-count acima, mas sem o requisito de vir "junto" com outra
  ///     métrica — não faz parte da Hierarquia de Fontes desta tarefa.
  ///   - **Somados por estágio, bucketizados pela manhã do despertar**
  ///     (sono_leve/profundo/rem/acordado_minutos): sono já vem granular do
  ///     Health Connect (ver [todosOsTipos]) — soma normalmente dentro do
  ///     MESMO dia. A parte não-óbvia é QUAL dia: um estágio às 23h de
  ///     segunda pertence à noite de sono que só termina terça de manhã, não
  ///     ao "dia de segunda" que `_dataOnly` daria. Ver [_dataDoSonoLocal].
  ///   - **Média aritmética** (frequência cardíaca genérica — `fc`, NÃO
  ///     `fc_repouso`): FC não sofre double-counting entre fontes do mesmo
  ///     jeito que passos/distância (não é cumulativo por natureza).
  ///   - **Última leitura** (fc_repouso, peso, HRV, pressão, glicose, ...):
  ///     sinais pontuais/de baixa frequência — a leitura mais recente do dia
  ///     é o que importa.
  /// Pacotes/bundle ids reconhecidos como pedômetro NATIVO do sistema
  /// operacional (Hierarquia de Fontes, RELATÓRIO 20260810_0007) — o app
  /// "contador de passos" que já vem instalado por padrão em praticamente
  /// todo Android/iPhone, contando pelo acelerômetro do próprio aparelho.
  /// Lista-NEGRA de propósito (despriorizar o que reconhecemos), não
  /// lista-branca: qualquer fonte não listada aqui (Garmin, Polar, Apple
  /// Watch, ou qualquer wearable futuro que ainda não existe) entra em
  /// prioridade ALTA por padrão — nunca corre o risco de derrubar um
  /// wearable de verdade só por não estar cadastrado nominalmente.
  ///
  /// Os identificadores batem contra [HealthMetricPoint.identificadorFonte]
  /// (bundle id no iOS, nome de pacote Android) — ver doc da classe para o
  /// porquê de sourceId/sourceName trocarem de papel entre as duas
  /// plataformas.
  static const _pedometrosNativos = <String>{
    'com.google.android.apps.fitness', // Google Fit
    'com.sec.android.app.shealth', // Samsung Health
    'com.apple.health', // app "Saúde" do iPhone (HealthKit, coprocessador M)
  };

  /// RELATÓRIO 20260813_0018 — achado real, confirmado por device físico
  /// (`atleta1000@teste.com`, `2026-08-11`): o próprio Health Connect
  /// registra passos contados pelo acelerômetro do aparelho sob um
  /// identificador gerado por instalação, no formato
  /// `com.android.healthconnect.phone.<hash>` — não é nenhum app de
  /// terceiros, é o equivalente ao pedômetro nativo do sistema (mesmo
  /// papel de Google Fit/Samsung Health/Apple Health), só que sem
  /// identificador fixo porque o hash muda por device/instalação. Como
  /// `_pedometrosNativos` era lista exata, essa fonte entrava em
  /// prioridade ALTA (mesmo nível de um wearable de verdade) e podia
  /// vencer a Fonte Vencedora só por ter mais passos brutos num dia —
  /// e como ela nunca reporta `DISTANCE_DELTA`/`DISTANCE_WALKING_RUNNING`,
  /// a distância do dia inteiro era descartada em silêncio mesmo com o
  /// Garmin tendo reportado distância real naquele mesmo dia. Prefixo
  /// (não lista exata) porque o hash é por instalação — não dá pra
  /// cadastrar nominalmente.
  static const _prefixosPedometrosNativos = <String>{
    'com.android.healthconnect.phone.',
  };

  /// RELATÓRIO 20260813_0019 — decisão do fundador, alinhada à
  /// especificação: calorias (ativas/basais) precisam vir de um wearable de
  /// verdade (Garmin ou equivalente), nunca de um app de balança/celular.
  /// Achado real, confirmado por device físico: `cn.fitdays.fitdays` (app
  /// da balança inteligente) só calcula/grava `BASAL_ENERGY_BURNED` no
  /// INSTANTE exato de uma pesagem — mesmo timestamp do ponto de `WEIGHT`,
  /// mesma fonte — porque é uma ESTIMATIVA pontual via fórmula (usa o peso
  /// que acabou de medir), não uma medição contínua de metabolismo basal
  /// como a de um wearable. Misturar isso no mesmo campo `calorias_basais`
  /// do Garmin fazia a coluna só existir em dias de pesagem, mascarada de
  /// dado do dia inteiro.
  ///
  /// Diferente da Hierarquia de Fontes de passos/distância (que aceita uma
  /// fonte nativa como último recurso quando não há wearable naquele dia —
  /// ver [_ehPedometroNativo]), calorias NUNCA caem para uma fonte
  /// excluída: sem wearable reportando naquele dia, o campo fica `null`,
  /// nunca preenchido com a estimativa de um app de balança/celular.
  static const _fontesCaloriasExcluidas = <String>{
    'cn.fitdays.fitdays', // balança inteligente — estimativa pontual no instante da pesagem, não medição contínua
  };

  static bool _ehFonteValidaParaCalorias(String identificadorFonte) =>
      !_ehPedometroNativo(identificadorFonte) &&
      !_fontesCaloriasExcluidas.contains(identificadorFonte);

  /// "Modo Raio-X" (RELATÓRIO 20260811_0002, diretriz do fundador — "até o
  /// último fio de cabelo"): imprime um resumo cru do que o health store
  /// devolveu, chamado logo depois de [Health.getHealthDataFromTypes] e
  /// ANTES de qualquer filtro/agregação nossa (`_AgregadoFonte`, Hierarquia
  /// de Fontes, merge por dia) tocar nos dados. Existe pra responder uma
  /// pergunta específica que só de olhar o resultado final não dá: "esse
  /// dado de distância/calorias do dia X saiu do Health Connect/HealthKit,
  /// ou foi estrangulado pela NOSSA lógica depois?" — sem isso, um dia sem
  /// distância na tela é indistinguível entre "o Health Connect nunca teve
  /// esse dado" e "nosso código descartou/agregou errado".
  ///
  /// `debugPrint` — roda em toda sincronização (delta diário e Carga de 30
  /// dias), aparece no console/logcat de debug, não afeta build de
  /// release.
  void _logRaioX(List<HealthDataPoint> rawPoints) {
    if (rawPoints.isEmpty) {
      debugPrint('🩻 [RAIO-X] 0 registros brutos recebidos do health store.');
      return;
    }

    // dia -> fonte -> conjunto de tipos vistos daquela fonte naquele dia.
    // Mesma regra de identificador de fonte da Hierarquia de Fontes (ver
    // HealthMetricPoint.identificadorFonte): sourceId quando não vazio
    // (iOS), senão sourceName (Android) — aqui em cima do HealthDataPoint
    // cru, antes de virar HealthMetricPoint.
    final tiposPorDiaEFonte = <String, Map<String, Set<String>>>{};
    final contagemPorDia = <String, int>{};

    for (final ponto in rawPoints) {
      final dia = _dataOnly(ponto.dateFrom);
      final fonte =
          ponto.sourceId.isNotEmpty ? ponto.sourceId : ponto.sourceName;
      final identificadorFonte = fonte.isEmpty ? '(fonte desconhecida)' : fonte;

      contagemPorDia[dia] = (contagemPorDia[dia] ?? 0) + 1;
      tiposPorDiaEFonte
          .putIfAbsent(dia, () => {})
          .putIfAbsent(identificadorFonte, () => {})
          .add(ponto.type.name);
    }

    debugPrint(
      '🩻 [RAIO-X] ${rawPoints.length} registros brutos recebidos do health '
      'store, cobrindo ${tiposPorDiaEFonte.length} dia(s).',
    );
    for (final dia in tiposPorDiaEFonte.keys.toList()..sort()) {
      final fontes = tiposPorDiaEFonte[dia]!;
      final resumoFontes = fontes.entries
          .map((e) => '[${e.key}: ${e.value.join(', ')}]')
          .join(', ');
      debugPrint(
        '🩻 [RAIO-X] Dia $dia - Recebidos ${contagemPorDia[dia]} registros. '
        'Fontes: $resumoFontes',
      );
    }
  }

  /// RELATÓRIO 20260813_0016 — ACHADO REAL rodando em device físico: a
  /// primeira versão desta função imprimia detalhe ponto a ponto de TODO
  /// tipo, sem exceção. Um usuário real gerou 41.446 pontos brutos em 30
  /// dias — só `HEART_RATE` (leitura contínua a cada 1-2min) respondeu por
  /// 23.437 deles. `debugPrint` tem um limitador de taxa embutido (existe
  /// pra não afogar o `adb logcat`/Android Runtime); nesse volume, o
  /// relatório levou mais de 33 MINUTOS só pra imprimir 26 dos 30 dias, e
  /// ainda não tinha terminado — na prática, "não aparece nada na tela"
  /// (a saída real é só console, mas mesmo lá demorava tempo demais pra
  /// alguém perceber). Tipos de leitura CONTÍNUA/alta-frequência
  /// ([_tiposAltaFrequenciaResumidosNoDiagnostico]) agora só imprimem a
  /// CONTAGEM por dia, nunca o detalhe ponto a ponto — nenhum deles é um
  /// dos 4 sinais citados no pedido original (distância/calorias
  /// basais/peso/treinos), então o detalhe nunca ajudou o diagnóstico,
  /// só afogava as linhas que importam. Para os demais tipos (baixa
  /// frequência — no máximo algumas dezenas de pontos/dia em qualquer
  /// cenário real), o detalhe completo é mantido, com um teto de
  /// segurança ([_maxPontosDetalhadosPorTipo]) contra qualquer tipo
  /// futuro que surpreenda com volume alto sem estar nesta lista.
  static const _tiposAltaFrequenciaResumidosNoDiagnostico = <HealthDataType>{
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_ASLEEP,
  };

  static const _maxPontosDetalhadosPorTipo = 50;

  /// Modo de Diagnóstico Profundo (RELATÓRIO 20260813_0015, decisão do
  /// fundador) — diferente do "Raio-X" (que roda em TODA sincronização e só
  /// resume contagem por dia/fonte), este só roda sob demanda (botão
  /// "GERAR LOG DIAGNÓSTICO (30 DIAS)" da tela de histórico, via
  /// [executarDiagnosticoProfundo]) e vai fundo demais pra rodar sempre:
  /// tipo NATIVO (`runtimeType`) e valor bruto de CADA ponto individual
  /// (fora dos tipos de alta frequência, ver acima), não só contagem.
  /// Existe porque o Raio-X e as duas auditorias anteriores (RELATÓRIOs
  /// 20260812_0013/20260813_0014) não conseguiram reproduzir em código as
  /// falhas relatadas em device físico (distância/calorias basais/peso/
  /// treinos faltando em dias específicos) — o próximo passo só é possível
  /// com o valor CRU que o pacote `health` devolveu na hora, direto do
  /// aparelho real.
  void _logDiagnosticoProfundo(
    List<HealthMetricPoint> points,
    DateTime start,
    DateTime end,
  ) {
    debugPrint('[SYNC_DIAGNOSTICO] ============ INÍCIO DO RELATÓRIO ============');
    // Restrição explícita da tarefa: `endTime` tem que ser o instante EXATO
    // de agora, nunca truncado pra meia-noite anterior — já era assim antes
    // desta tarefa (`_lerComPermissao` sempre usou `DateTime.now()` puro),
    // este log só torna isso verificável olhando o console, sem precisar
    // ler o código-fonte pra confirmar.
    debugPrint(
      '[SYNC_DIAGNOSTICO] Janela pedida ao pacote health: '
      'startTime=${start.toIso8601String()} endTime=${end.toIso8601String()} '
      '(endTime = DateTime.now() exato, nunca truncado à meia-noite).',
    );
    debugPrint(
      '[SYNC_DIAGNOSTICO] Total de pontos brutos convertidos com sucesso: '
      '${points.length}',
    );

    if (points.isEmpty) {
      debugPrint(
        '[SYNC_DIAGNOSTICO] Nenhum ponto na janela inteira — nada a detalhar.',
      );
      debugPrint('[SYNC_DIAGNOSTICO] ============= FIM DO RELATÓRIO =============');
      return;
    }

    final porDia = <String, List<HealthMetricPoint>>{};
    for (final ponto in points) {
      porDia.putIfAbsent(_dataOnly(ponto.dateFrom), () => []).add(ponto);
    }

    for (final dia in porDia.keys.toList()..sort()) {
      final pontosDoDia = porDia[dia]!;
      final porTipo = <HealthDataType, List<HealthMetricPoint>>{};
      for (final ponto in pontosDoDia) {
        porTipo.putIfAbsent(ponto.type, () => []).add(ponto);
      }

      debugPrint(
        '[SYNC_DIAGNOSTICO] --- Dia $dia: ${pontosDoDia.length} ponto(s) '
        'brutos, ${porTipo.length} tipo(s) diferente(s) ---',
      );
      for (final tipo in porTipo.keys) {
        final pontosDoTipo = porTipo[tipo]!;
        debugPrint(
          '[SYNC_DIAGNOSTICO]   ${tipo.name}: ${pontosDoTipo.length} ponto(s)',
        );

        // RELATÓRIO 20260813_0016: tipos de leitura contínua (HEART_RATE e
        // afins) nunca imprimem detalhe ponto a ponto — só a contagem
        // acima. Ver doc da classe pra o achado real que motivou isso.
        if (_tiposAltaFrequenciaResumidosNoDiagnostico.contains(tipo)) {
          continue;
        }

        final pontosParaDetalhar =
            pontosDoTipo.take(_maxPontosDetalhadosPorTipo);
        for (final ponto in pontosParaDetalhar) {
          debugPrint(
            '[SYNC_DIAGNOSTICO]     valor=${ponto.value} '
            'tipoNativo=${ponto.rawValue.runtimeType} unidade=${ponto.unit} '
            'fonte=${ponto.sourceApp} de=${ponto.dateFrom.toIso8601String()} '
            'até=${ponto.dateTo.toIso8601String()}',
          );
        }
        final omitidos = pontosDoTipo.length - _maxPontosDetalhadosPorTipo;
        if (omitidos > 0) {
          debugPrint(
            '[SYNC_DIAGNOSTICO]     ... e mais $omitidos ponto(s) '
            'omitido(s) (teto de segurança — tipo com volume maior que o '
            'esperado; contagem total já reportada acima).',
          );
        }
      }

      // Achado específico pedido pela tarefa: dia com pontos de distância
      // recebidos mas soma 0/null — dump bruto completo desses pontos, pra
      // diagnosticar se é falha de conversão/cast do nosso lado ou o
      // Health Connect genuinamente devolvendo 0.
      final pontosDistancia = pontosDoDia
          .where((p) =>
              p.type == HealthDataType.DISTANCE_DELTA ||
              p.type == HealthDataType.DISTANCE_WALKING_RUNNING)
          .toList();
      if (pontosDistancia.isNotEmpty) {
        final somaDistancia =
            pontosDistancia.fold<double>(0, (soma, p) => soma + p.value);
        if (somaDistancia <= 0) {
          debugPrint(
            '[SYNC_DIAGNOSTICO]   ⚠️ Dia $dia tem ${pontosDistancia.length} '
            'ponto(s) de distância mas a soma deu $somaDistancia — dump '
            'bruto completo:',
          );
          for (final p in pontosDistancia) {
            debugPrint(
              '[SYNC_DIAGNOSTICO]     ⚠️ rawValue=${p.rawValue} '
              '(${p.rawValue.runtimeType}) value=${p.value} unidade=${p.unit} '
              'fonte=${p.sourceApp}/${p.sourceId}',
            );
          }
        }
      }
    }

    debugPrint('[SYNC_DIAGNOSTICO] ============= FIM DO RELATÓRIO =============');
  }

  static bool _ehPedometroNativo(String identificadorFonte) =>
      _pedometrosNativos.contains(identificadorFonte) ||
      _prefixosPedometrosNativos
          .any((prefixo) => identificadorFonte.startsWith(prefixo));

  List<Map<String, dynamic>> _mesclarPorDia(
    String usuarioId,
    List<HealthPayloadModel> payloads,
  ) {
    final porDia = <String, Map<String, dynamic>>{};
    final somaFcPorDia = <String, double>{};
    final contagemFcPorDia = <String, int>{};
    final maximaFcPorDia = <String, int>{};
    final caloriasPorDiaFonte = <String, Map<String, num>>{};
    // Calorias basais (RELATÓRIO 20260811_0002) — mesmo tratamento
    // anti-double-counting de calorias ativas: mais de uma fonte pode
    // reportar metabolismo basal do mesmo dia (celular+relógio), então
    // maior fonte, nunca soma entre fontes.
    final caloriasBasaisPorDiaFonte = <String, Map<String, num>>{};
    // RELATÓRIO 20260819_0020 — leitura direta de TOTAL_CALORIES_BURNED,
    // mesmo tratamento anti-double-counting/exclusão de fonte de
    // calorias_ativas/calorias_basais (nunca cai pra Fitdays/pedômetro
    // nativo — ver _ehFonteValidaParaCalorias). Tem prioridade sobre o
    // fallback ativas+basais somadas no Dart (ver bloco depois do loop).
    final caloriasTotaisDiretasPorDiaFonte = <String, Map<String, num>>{};
    // RELATÓRIO 20260819_0020, pedido do fundador — andares subidos.
    // Mesmo padrão "maior fonte do dia" de calorias_ativas (sem a exclusão
    // de _ehFonteValidaParaCalorias: FLIGHTS_CLIMBED não tem o mesmo
    // problema de app-de-balança-mascarando-estimativa-pontual que motivou
    // aquela lista — qualquer fonte que reporte é candidata).
    final andaresSubidosPorDiaFonte = <String, Map<String, num>>{};
    // Hierarquia de Fontes (RELATÓRIO 20260810_0007, decisão do fundador):
    // passos e distância NÃO escolhem mais a "maior fonte" cada um por
    // conta própria (isso é o que produzia proporção passos/distância
    // biologicamente incoerente — ex.: passos do pedômetro do celular
    // misturados com distância do Garmin no mesmo dia). Os dois vêm juntos
    // da MESMA "Fonte Vencedora" — um só mapa por (dia, fonte) acumulando
    // ambos, ver _fonteVencedoraDoDia depois do loop principal.
    final agregadoPorDiaFonte = <String, Map<String, _AgregadoFonte>>{};

    // RELATÓRIO 20260813_0015 (Parte 1 — Proteção Extrema no Parsing): o
    // corpo inteiro do loop agora roda dentro de um try/catch por
    // iteração. Antes, qualquer exceção aqui dentro (ex.: um cast
    // inesperado num campo do payload) escapava do `for` e cancelava o
    // processamento de TODOS os payloads restantes do lote inteiro
    // (outros dias, outras métricas) — não só o ponto problemático.
    for (final payload in payloads) {
      try {
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

        if (payload.passos != null || payload.distanciaMetros != null) {
          final porFonte =
              agregadoPorDiaFonte.putIfAbsent(dataReferencia, () => {});
          final agregado =
              porFonte.putIfAbsent(payload.source, () => _AgregadoFonte());
          if (payload.passos != null) {
            agregado.passos = (agregado.passos ?? 0) + payload.passos!;
          }
          if (payload.distanciaMetros != null) {
            agregado.distanciaMetros =
                (agregado.distanciaMetros ?? 0) + payload.distanciaMetros!;
          }
        }
        if (payload.caloriasAtivas != null &&
            _ehFonteValidaParaCalorias(payload.source)) {
          final porFonte = caloriasPorDiaFonte.putIfAbsent(dataReferencia, () => {});
          porFonte[payload.source] =
              (porFonte[payload.source] ?? 0) + payload.caloriasAtivas!;
        }
        if (payload.caloriasBasais != null &&
            _ehFonteValidaParaCalorias(payload.source)) {
          final porFonte =
              caloriasBasaisPorDiaFonte.putIfAbsent(dataReferencia, () => {});
          porFonte[payload.source] =
              (porFonte[payload.source] ?? 0) + payload.caloriasBasais!;
        }
        if (payload.caloriasTotais != null &&
            _ehFonteValidaParaCalorias(payload.source)) {
          final porFonte = caloriasTotaisDiretasPorDiaFonte.putIfAbsent(
              dataReferencia, () => {});
          porFonte[payload.source] =
              (porFonte[payload.source] ?? 0) + payload.caloriasTotais!;
        }
        if (payload.andaresSubidos != null) {
          final porFonte =
              andaresSubidosPorDiaFonte.putIfAbsent(dataReferencia, () => {});
          porFonte[payload.source] =
              (porFonte[payload.source] ?? 0) + payload.andaresSubidos!;
        }
        somar('sono_leve_minutos', payload.sonoLeveMinutos);
        somar('sono_profundo_minutos', payload.sonoProfundoMinutos);
        somar('sono_rem_minutos', payload.sonoRemMinutos);
        somar('sono_acordado_minutos', payload.sonoAcordadoMinutos);

        if (payload.frequenciaCardiaca != null) {
          final valor = payload.frequenciaCardiaca!;
          somaFcPorDia[dataReferencia] = (somaFcPorDia[dataReferencia] ?? 0) + valor;
          contagemFcPorDia[dataReferencia] =
              (contagemFcPorDia[dataReferencia] ?? 0) + 1;
          // fc_maxima: SÓ o maior valor absoluto do dia — nenhuma lógica de
          // limite/faixa/evento aqui (Parte 5/BL.1, ver doc de
          // _detectarEregistrarAnomalias). É a mesma fonte de dado
          // (HEART_RATE) que já alimenta a média, não uma leitura à parte.
          maximaFcPorDia[dataReferencia] =
              math.max(valor, maximaFcPorDia[dataReferencia] ?? valor);
        }
        sobrescrever('fc_repouso', payload.fcRepouso);
        sobrescrever('hrv_medio', payload.hrvMedio);
        sobrescrever('peso_kg', payload.pesoKg);
        sobrescrever('massa_magra_kg', payload.massaMagraKg);
        sobrescrever('percentual_gordura', payload.percentualGordura);
        sobrescrever('agua_corporal', payload.aguaCorporalKg);
        sobrescrever('imc', payload.imc);
        sobrescrever('pressao_sistolica', payload.pressaoSistolica);
        sobrescrever('pressao_diastolica', payload.pressaoDiastolica);
        sobrescrever('glicose_jejum', payload.glicoseJejum);
        sobrescrever('saturacao_oxigenio', payload.saturacaoOxigenio);
        sobrescrever('temperatura_corporal', payload.temperaturaCorporal);
      } catch (e, stackTrace) {
        debugPrint(
          '[SYNC_DIAGNOSTICO] Falha ao agregar 1 payload no dia '
          '(origem "${payload.source}", de ${payload.dateFrom}) — pulado, '
          'os demais payloads do lote continuam sendo processados: '
          '$e\n$stackTrace',
        );
      }
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

    aplicarMaiorFonte(caloriasPorDiaFonte, 'calorias_ativas', arredondar: false);
    aplicarMaiorFonte(caloriasBasaisPorDiaFonte, 'calorias_basais', arredondar: false);
    aplicarMaiorFonte(andaresSubidosPorDiaFonte, 'andares_subidos', arredondar: true);

    // RELATÓRIO 20260819_0020: dia com leitura real de TOTAL_CALORIES_BURNED
    // usa ela direto (maior fonte, mesmo tratamento acima) — é o dado mais
    // fiel que existe (o próprio wearable soma ativa+basal com o algoritmo
    // dele). Guardado num map à parte (não em `porDia` ainda) porque o
    // fallback abaixo precisa saber, por dia, se já existe leitura direta
    // antes de decidir se soma ativas+basais.
    final diasComCaloriasTotaisDiretas = <String, num>{};
    for (final entry in caloriasTotaisDiretasPorDiaFonte.entries) {
      diasComCaloriasTotaisDiretas[entry.key] =
          entry.value.values.reduce((a, b) => a > b ? a : b);
    }

    // calorias_totais: leitura direta de TOTAL_CALORIES_BURNED quando o
    // wearable publicou naquele dia (ver achado acima); senão, fallback
    // "melhor esforço" = ativas + basais (soma tratando o ausente como 0),
    // só quando pelo menos uma das duas existir — mesmo comportamento de
    // antes desta tarefa, preservado pros dias/plataforma (iOS) sem leitura
    // direta.
    for (final entry in porDia.entries) {
      final dataReferencia = entry.key;
      final linha = entry.value;
      final direta = diasComCaloriasTotaisDiretas[dataReferencia];
      if (direta != null) {
        linha['calorias_totais'] = direta;
        continue;
      }
      final ativas = (linha['calorias_ativas'] as num?)?.toDouble();
      final basais = (linha['calorias_basais'] as num?)?.toDouble();
      if (ativas == null && basais == null) continue;
      linha['calorias_totais'] = (ativas ?? 0) + (basais ?? 0);
    }

    // Hierarquia de Fontes: passos e distância do dia vêm os DOIS da mesma
    // Fonte Vencedora — prioridade alta (qualquer coisa que não seja um
    // pedômetro nativo reconhecido) primeiro, desempate pelo maior nº de
    // passos dentro da mesma prioridade. Nunca mistura passos de uma fonte
    // com distância de outra.
    for (final entry in agregadoPorDiaFonte.entries) {
      final dataReferencia = entry.key;
      final fontes = entry.value;
      if (fontes.isEmpty) continue;

      final vencedora = fontes.entries.reduce((a, b) {
        final aPrioridadeAlta = !_ehPedometroNativo(a.key);
        final bPrioridadeAlta = !_ehPedometroNativo(b.key);
        if (aPrioridadeAlta != bPrioridadeAlta) {
          return aPrioridadeAlta ? a : b;
        }
        return (a.value.passos ?? 0) >= (b.value.passos ?? 0) ? a : b;
      }).value;

      if (vencedora.passos != null) {
        porDia[dataReferencia]!['passos'] = vencedora.passos!.round();
      }
      if (vencedora.distanciaMetros != null) {
        porDia[dataReferencia]!['distancia_metros'] = vencedora.distanciaMetros;
      }
    }

    // Fecha média e máxima de FC por último — precisa de todos os pontos do
    // dia somados/comparados antes de dividir pela contagem.
    for (final entry in somaFcPorDia.entries) {
      final dataReferencia = entry.key;
      final contagem = contagemFcPorDia[dataReferencia]!;
      porDia[dataReferencia]!['frequencia_cardiaca'] =
          (entry.value / contagem).round();
      porDia[dataReferencia]!['fc_maxima'] = maximaFcPorDia[dataReferencia];
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

  /// Treinos + Rotas GPS (RELATÓRIO 20260811_0002, decisão do fundador) —
  /// um `atividades_fisicas_treinos` por ponto `WORKOUT` lido, com FC
  /// isolada ao INTERVALO de tempo daquele treino específico (não a FC do
  /// dia inteiro) e a rota GPS correspondente, quando existir.
  ///
  /// Best-effort do início ao fim (mesmo espírito de
  /// [_detectarEregistrarAnomalias]/[_garantirPermissaoHistorico]): uma
  /// falha em UM treino (upsert, rota, o que for) é logada e o loop segue
  /// pros próximos — nunca derruba a sincronização principal de
  /// `metricas_saude_diarias`.
  Future<void> _processarTreinos(
    String usuarioId,
    List<HealthMetricPoint> points,
  ) async {
    final treinos =
        points.where((p) => p.type == HealthDataType.WORKOUT).toList();
    if (treinos.isEmpty) return;

    // Cru, não achatado — precisa de HealthMetricPoint.value (o número em
    // bpm), só filtrado pelo INTERVALO do treino, não do dia inteiro.
    final fcBruta =
        points.where((p) => p.type == HealthDataType.HEART_RATE).toList();
    // RELATÓRIO 20260819_0020, pedido do fundador — velocidade (m/s), mesmo
    // tratamento de fcBruta: série contínua filtrada pelo intervalo exato
    // do treino, não uma métrica diária solta.
    final velocidadeBruta =
        points.where((p) => p.type == HealthDataType.SPEED).toList();
    final rotas =
        points.where((p) => p.type == HealthDataType.WORKOUT_ROUTE).toList();

    bool dentroDoIntervalo(HealthMetricPoint ponto, HealthMetricPoint treino) =>
        !ponto.dateFrom.isBefore(treino.dateFrom) &&
        !ponto.dateTo.isAfter(treino.dateTo);

    for (final treino in treinos) {
      final workout = treino.rawValue;
      if (workout is! WorkoutHealthValue) continue;

      try {
        // FC do treino: filtra o array de HEART_RATE bruto do LOTE inteiro
        // (pode cobrir vários dias) pelas leituras cujo timestamp cai
        // exatamente entre o início e o fim DESTE treino — pedido explícito
        // do fundador. Sem lógica de anomalia/evento aqui (restrição F02,
        // RELATÓRIO 20260810_0004) — só min/média/máxima, valores absolutos.
        final fcDoTreino = fcBruta
            .where((p) => dentroDoIntervalo(p, treino))
            .map((p) => p.value)
            .toList();
        final velocidadeDoTreino = velocidadeBruta
            .where((p) => dentroDoIntervalo(p, treino))
            .map((p) => p.value)
            .toList();

        final linhaTreino = <String, dynamic>{
          'usuario_id': usuarioId,
          'tipo_atividade_codigo': workout.workoutActivityType.name,
          'inicio_atividade': treino.dateFrom.toIso8601String(),
          'fim_atividade': treino.dateTo.toIso8601String(),
          'origem': treino.identificadorFonte.isEmpty
              ? 'wearable'
              : treino.identificadorFonte,
          if (workout.totalEnergyBurned != null)
            'energia_queimada_kcal': workout.totalEnergyBurned,
          if (workout.totalDistance != null)
            'distancia_metros': workout.totalDistance,
          if (workout.totalSteps != null) 'passos_totais': workout.totalSteps,
          if (fcDoTreino.isNotEmpty) ...{
            'fc_media':
                (fcDoTreino.reduce((a, b) => a + b) / fcDoTreino.length).round(),
            'fc_maxima': fcDoTreino.reduce(math.max).round(),
            'fc_minima': fcDoTreino.reduce(math.min).round(),
          },
          // RELATÓRIO 20260819_0020, pedido do fundador — m/s (mesma
          // unidade de HealthDataType.SPEED, ver HealthConstants.kt do
          // pacote `health`).
          if (velocidadeDoTreino.isNotEmpty) ...{
            'velocidade_media_ms': double.parse(
              (velocidadeDoTreino.reduce((a, b) => a + b) /
                      velocidadeDoTreino.length)
                  .toStringAsFixed(2),
            ),
            'velocidade_maxima_ms': double.parse(
              velocidadeDoTreino.reduce(math.max).toStringAsFixed(2),
            ),
          },
        };

        // onConflict na chave (usuario_id, inicio_atividade) — idempotência:
        // reprocessar os mesmos 30 dias atualiza o mesmo treino, nunca
        // duplica. .select('id') porque precisamos do id gerado (mesmo em
        // cima de um conflito, PostgREST devolve a linha final) pra linkar
        // a rota, sem uma segunda ida ao banco só pra descobrir.
        final treinoGravado = await _supabase
            .from('atividades_fisicas_treinos')
            .upsert(linhaTreino, onConflict: 'usuario_id,inicio_atividade')
            .select('id')
            .single();
        final treinoId = treinoGravado['id'] as String;

        await _gravarRotaDoTreino(treinoId, treino, rotas, dentroDoIntervalo);
      } catch (e) {
        debugPrint(
          'HealthSyncService: falha ao gravar treino de '
          '${treino.dateFrom} (best-effort, sync principal segue): $e',
        );
      }
    }
  }

  /// Grava a rota GPS de UM treino já upsertado — idempotência via
  /// "limpa e reinsere" (pedido explícito da tarefa): sem uma chave única
  /// de negócio por PONTO de rota para dar onConflict, apagar as rotas
  /// antigas do treino e inserir as novas de novo é o jeito direto de
  /// nunca duplicar pontos ao reprocessar os mesmos 30 dias.
  ///
  /// ACHADO REAL (não suposição): no Android, quando o Health Connect exige
  /// consentimento extra POR SESSÃO para expor a rota
  /// (`ExerciseRouteResult.ConsentRequired`, achado lendo `HealthDataReader.
  /// kt` do pacote `health`), a resposta que chega aqui no Dart é uma rota
  /// com `locations` VAZIO — não existe nenhum jeito de distinguir, do lado
  /// Dart, "consentimento negado" de "este treino não tem rota GPS mesmo".
  /// Por isso o `if (locations.isEmpty) return` abaixo já cobre os dois
  /// casos ao mesmo tempo — é exatamente o "ignore a rota silenciosamente"
  /// pedido pela tarefa, sem precisar de nenhuma checagem especial.
  Future<void> _gravarRotaDoTreino(
    String treinoId,
    HealthMetricPoint treino,
    List<HealthMetricPoint> rotas,
    bool Function(HealthMetricPoint, HealthMetricPoint) dentroDoIntervalo,
  ) async {
    try {
      final candidatas =
          rotas.where((r) => dentroDoIntervalo(r, treino)).toList();
      if (candidatas.isEmpty) return;
      final rotaDoTreino = candidatas.first;

      final rotaValue = rotaDoTreino.rawValue;
      if (rotaValue is! WorkoutRouteHealthValue) return;
      if (rotaValue.locations.isEmpty) return;

      await _supabase
          .from('atividades_fisicas_rotas')
          .delete()
          .eq('treino_id', treinoId);

      await _supabase.from('atividades_fisicas_rotas').insert(
        rotaValue.locations
            .map(
              (ponto) => {
                'treino_id': treinoId,
                'latitude': ponto.latitude,
                'longitude': ponto.longitude,
                'timestamp_ponto': ponto.timestamp.toIso8601String(),
                if (ponto.altitude != null) 'altitude': ponto.altitude,
                if (ponto.horizontalAccuracy != null)
                  'precisao': ponto.horizontalAccuracy,
              },
            )
            .toList(),
      );
    } catch (e) {
      // Best-effort: falha ao gravar rota (rede, RLS, o que for) nunca
      // pode derrubar o treino em si, que já foi upsertado com sucesso
      // antes desta chamada.
      debugPrint(
        'HealthSyncService: falha ao gravar rota do treino $treinoId '
        '(best-effort): $e',
      );
    }
  }

  /// Inferência cruzada de balança/composição corporal — decisão do
  /// fundador (RELATÓRIO desta tarefa), roda DEPOIS de [_mesclarPorDia]
  /// porque precisa dos valores já consolidados por dia (peso/percentual/
  /// massa magra podem ter vindo de payloads/pontos diferentes dentro do
  /// mesmo dia; só faz sentido inferir sobre o que sobrou depois do merge).
  ///
  /// Duas equações, cada uma só preenche o que está faltando (nunca
  /// sobrescreve um valor que o Health Connect já mandou):
  ///   massaMagra = peso × (1 − percentual/100)
  ///   percentual = (1 − massaMagra/peso) × 100
  ///
  /// IMC: se [_mesclarPorDia] já não preencheu `imc` (Health Connect não
  /// entregou `BODY_MASS_INDEX` pronto naquele dia) e há peso, busca a
  /// altura em `perfis_usuarios.altura_cm` — UMA vez por chamada (mesmo
  /// usuário em todas as linhas de um sync), não uma vez por dia — e
  /// calcula `imc = peso / altura_m²`. Sem altura cadastrada, o IMC
  /// simplesmente fica de fora daquele dia; não é erro.
  ///
  /// ACHADO DESTA TAREFA (RELATÓRIO 20260810_0007 — "IMC não calculou no
  /// histórico" mesmo com altura preenchida): [_buscarAlturaMetros] marcava
  /// `alturaJaBuscada = true` mesmo quando a busca FALHAVA (rede/RLS/timeout
  /// — o `catch` interno devolvia `null` do mesmo jeito que "coluna vazia").
  /// Numa Carga de 30 dias, se a PRIMEIRA linha processada batesse nessa
  /// falha, TODAS as ~30 linhas seguintes perdiam o IMC, mesmo tendo peso —
  /// a falha de UM dia "envenenava" o lote inteiro, e o único rastro era um
  /// `debugPrint` que não aparece em lugar nenhum que o fundador veja. Não
  /// achei nenhum jeito de reproduzir uma falha DETERMINÍSTICA lendo o
  /// código (a consulta em si está correta — testada e comprovada abaixo);
  /// o mais provável é ter sido uma falha de rede pontual no momento exato
  /// da primeira linha. De qualquer forma, "uma falha transitória apaga o
  /// lote inteiro sem deixar rastro" É um erro silencioso de verdade — por
  /// isso a correção: só passa a NÃO tentar de novo quando a consulta
  /// respondeu com sucesso (com ou sem altura cadastrada); se lançou
  /// exceção, a próxima linha do lote tenta de novo.
  Future<void> _aplicarInferenciasCruzadas(
    String usuarioId,
    List<Map<String, dynamic>> linhas,
  ) async {
    double? alturaMetros;
    var alturaConfirmada = false;

    for (final linha in linhas) {
      final peso = (linha['peso_kg'] as num?)?.toDouble();
      final percentual = (linha['percentual_gordura'] as num?)?.toDouble();
      final massaMagra = (linha['massa_magra_kg'] as num?)?.toDouble();

      if (peso != null && peso > 0) {
        if (percentual != null && massaMagra == null) {
          linha['massa_magra_kg'] =
              double.parse((peso * (1 - percentual / 100)).toStringAsFixed(2));
        } else if (massaMagra != null && percentual == null) {
          linha['percentual_gordura'] =
              double.parse(((1 - massaMagra / peso) * 100).toStringAsFixed(2));
        }
      }

      if (linha['imc'] == null && peso != null && peso > 0) {
        if (!alturaConfirmada) {
          final resultado = await _buscarAlturaMetros(usuarioId);
          alturaMetros = resultado.alturaMetros;
          alturaConfirmada = resultado.sucesso;
        }
        if (alturaMetros != null && alturaMetros > 0) {
          linha['imc'] = double.parse(
            (peso / (alturaMetros * alturaMetros)).toStringAsFixed(1),
          );
        }
      }
    }
  }

  /// RELATÓRIO 20260812_0013 — investigação de "distância sumindo em dias
  /// aleatórios" (05/08, 11/08, 12/08... — sem padrão de dia da semana nem
  /// de volume de passos). Auditoria completa (banco + código) não achou
  /// NENHUM bug de bucketing/conversão/tipo — `distancia_metros` passa
  /// pelo MESMO loop, MESMA função de bucketização por dia
  /// (`_dataOnly`) e MESMA lógica de "maior fonte" que `passos`, que nunca
  /// falha nesses dias. A consulta única e combinada (`getHealthDataFromTypes`
  /// pedindo ~20 `HealthDataType`s de uma vez, incluindo `DISTANCE_DELTA`
  /// — um tipo que pode gerar MUITOS registros pequenos por dia, mais
  /// granular que passos) é o único lugar restante onde uma limitação de
  /// paginação/truncamento da plataforma (Health Connect) ou do pacote
  /// `health` poderia derrubar silenciosamente só o tipo mais numeroso, sem
  /// lançar exceção nenhuma — não reproduzível lendo código (precisaria de
  /// um device real), mas a mitigação abaixo é segura mesmo que essa
  /// hipótese esteja errada: só PREENCHE dias que ficaram sem distância
  /// apesar de terem passos, nunca sobrescreve um valor já resolvido pela
  /// leitura combinada — zero risco de contar a mesma distância duas vezes.
  ///
  /// Best-effort, mesmo espírito de [_aplicarInferenciasCruzadas]/
  /// [_detectarEregistrarAnomalias]: uma falha aqui (rede, permissão) nunca
  /// derruba o sync principal, que já terminou com sucesso antes desta
  /// chamada extra rodar.
  Future<void> _preencherDistanciaFaltante(
    List<Map<String, dynamic>> linhas,
    DateTime inicioJanela,
  ) async {
    final linhasFaltantes = <String, Map<String, dynamic>>{
      for (final linha in linhas)
        if (linha['passos'] != null && linha['distancia_metros'] == null)
          linha['data_referencia'] as String: linha,
    };
    if (linhasFaltantes.isEmpty) return;

    try {
      final leitura = await _lerComPermissao(
        const [HealthDataType.DISTANCE_WALKING_RUNNING, HealthDataType.DISTANCE_DELTA],
        start: inicioJanela,
      );
      if (!leitura.granted) return;

      // Mesma agregação "maior fonte por dia" de _mesclarPorDia — só que
      // isolada aqui, e só para os dias que já sabemos que faltam.
      final somaPorDiaFonte = <String, Map<String, num>>{};
      for (final ponto in leitura.points) {
        final payload = ponto.toPayload();
        final distancia = payload.distanciaMetros;
        if (distancia == null) continue;

        final dataReferencia = _dataOnly(payload.dateFrom);
        if (!linhasFaltantes.containsKey(dataReferencia)) continue;

        final porFonte = somaPorDiaFonte.putIfAbsent(dataReferencia, () => {});
        porFonte[payload.source] = (porFonte[payload.source] ?? 0) + distancia;
      }

      for (final entry in somaPorDiaFonte.entries) {
        if (entry.value.isEmpty) continue;
        final maiorFonte = entry.value.values.reduce((a, b) => a > b ? a : b);
        linhasFaltantes[entry.key]!['distancia_metros'] = maiorFonte;
      }
    } catch (e) {
      debugPrint(
        'HealthSyncService: falha ao tentar preencher distância faltante '
        '(best-effort, não afeta o resto do sync): $e',
      );
    }
  }

  /// Busca `perfis_usuarios.altura_cm` e converte para metros.
  /// [_AlturaResultado.sucesso] distingue "consulta funcionou" (mesmo que
  /// sem altura cadastrada — cacheável pelo resto do lote, ver
  /// [_aplicarInferenciasCruzadas]) de "a consulta lançou exceção" (rede/
  /// RLS/timeout — NÃO cacheável, a próxima linha do lote tenta de novo em
  /// vez de desistir pro resto da Carga de 30 dias inteira).
  Future<_AlturaResultado> _buscarAlturaMetros(String usuarioId) async {
    try {
      final resposta = await _supabase
          .from('perfis_usuarios')
          .select('altura_cm')
          .eq('id', usuarioId)
          .maybeSingle();
      final alturaCm = (resposta?['altura_cm'] as num?)?.toDouble();
      if (alturaCm == null || alturaCm <= 0) {
        return const _AlturaResultado(alturaMetros: null, sucesso: true);
      }
      return _AlturaResultado(alturaMetros: alturaCm / 100, sucesso: true);
    } catch (e) {
      debugPrint(
        'HealthSyncService: falha ao buscar altura do perfil (tentará de '
        'novo na próxima linha do lote, se houver): $e',
      );
      return const _AlturaResultado(alturaMetros: null, sucesso: false);
    }
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
