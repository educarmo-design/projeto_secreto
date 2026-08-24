import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/services/health_sync_service.dart';

enum SyncUiStatus { idle, carregando, sucesso, falha, offline }

@immutable
class SyncUiState {
  final SyncUiStatus status;
  final DateTime? ultimaSincronizacaoEm;
  final String? errorMessage;

  /// Rows still waiting in the offline queue (Secure Storage) for the next
  /// connectivity window.
  final int pendentesNaFila;

  const SyncUiState({
    this.status = SyncUiStatus.idle,
    this.ultimaSincronizacaoEm,
    this.errorMessage,
    this.pendentesNaFila = 0,
  });

  bool get isLoading => status == SyncUiStatus.carregando;
  bool get isOffline => status == SyncUiStatus.offline;
  bool get isError => status == SyncUiStatus.falha;
  bool get isSuccess => status == SyncUiStatus.sucesso;
  bool get temPendentes => pendentesNaFila > 0;

  /// Friendly i18n label for the last successful sync, e.g. "Última
  /// atualização: Hoje às 08:30" — falls back to "Ainda não sincronizado"
  /// before the first sync ever completes.
  String ultimaSincronizacaoLabel() {
    final quando = ultimaSincronizacaoEm;
    if (quando == null) return i18n.tr('dashboard.sync_never');

    final hora = quando.hour.toString().padLeft(2, '0');
    final minuto = quando.minute.toString().padLeft(2, '0');
    final horaFormatada = '$hora:$minuto';

    final agora = DateTime.now();
    if (_mesmoDia(quando, agora)) {
      return i18n.tr(
        'dashboard.sync_last_today',
        params: {'hora': horaFormatada},
      );
    }

    final ontem = agora.subtract(const Duration(days: 1));
    if (_mesmoDia(quando, ontem)) {
      return i18n.tr(
        'dashboard.sync_last_yesterday',
        params: {'hora': horaFormatada},
      );
    }

    final dia = quando.day.toString().padLeft(2, '0');
    final mes = quando.month.toString().padLeft(2, '0');
    return i18n.tr(
      'dashboard.sync_last_date',
      params: {'data': '$dia/$mes', 'hora': horaFormatada},
    );
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Drives the dashboard's sync UI: surfaces Loading/Success/Failure/Offline
/// states, the friendly last-sync label, the manual "sync now" button, and
/// the offline queue that backstops [forcarSincronizacaoAtleta] when the
/// write to `metricas_saude_diarias` can't reach the server.
///
/// `ValueNotifier`-based, matching [CameraCaptureController] and
/// [CadastroController] in this codebase — a single-screen concern doesn't
/// need Riverpod's dependency graph.
class SyncUiController extends ValueNotifier<SyncUiState> {
  SyncUiController({
    HealthSyncService? healthSyncService,
    FlutterSecureStorage? secureStorage,
    Connectivity? connectivity,
  })  : _healthSyncService = healthSyncService ?? HealthSyncService(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _connectivity = connectivity ?? Connectivity(),
        super(const SyncUiState()) {
    _carregarEstadoInicial();
    _observarConectividade();
  }

  final HealthSyncService _healthSyncService;
  final FlutterSecureStorage _secureStorage;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Secure Storage key for the queued fixed-column rows awaiting dispatch —
  /// see the class doc's "Resiliência Offline" note.
  static const String _chaveFilaPendente = 'pending_metricas_saude_payloads';

  Future<void> _carregarEstadoInicial() async {
    final quando = await _healthSyncService.obterUltimaSincronizacao();
    final pendentes = await _lerFilaPendente();
    value = SyncUiState(
      ultimaSincronizacaoEm: quando,
      pendentesNaFila: pendentes.length,
    );
  }

  void _observarConectividade() {
    _connectivitySub =
        _connectivity.onConnectivityChanged.listen((resultados) {
      final online = resultados.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(_tentarDespacharFila());
      }
    });
  }

  /// Sincronização Oportunista (N17): runs the daily delta immediately in
  /// foreground — when the user opens the app or taps the "sync now"
  /// button — without registering or waking the WorkManager task. The
  /// nightly `sync_diario_wearables` job stays reserved for the
  /// Wi-Fi + charging window; this path is explicitly allowed to run over
  /// any connection, right now, because the user asked for it.
  /// N19: devolve o [DeltaSyncResult] (antes era `Future<void>`) — o botão
  /// de debug "FORÇAR SYNC HOJE" precisa do resultado pra decidir a
  /// mensagem que mostra; chamadores que só querem disparar e não ligam
  /// pro retorno (ex.: `unawaited(...)` em `MainNavigationPage.initState`)
  /// continuam funcionando sem mudança — `Future<T>` é atribuível a
  /// `Future<void>` em Dart.
  Future<DeltaSyncResult> forcarSincronizacaoAtleta() {
    return _executar(_healthSyncService.sincronizarDeltaDiario);
  }

  /// Carga Inicial (N18): dispara [HealthSyncService.carregarHistoricoInicial]
  /// (30 dias) através do mesmo estado/fila-offline de
  /// [forcarSincronizacaoAtleta] — chamado quando o usuário conecta um
  /// wearable pela primeira vez (`RegistrarMetricaPage`, botão "Sincronizar
  /// via Relógio/App Inteligente"). Devolve o [DeltaSyncResult] também
  /// diretamente para quem chamou poder mostrar um resumo específico dessa
  /// tela (ex.: "N dias sincronizados"), além de já atualizar [value] como
  /// qualquer outra sincronização.
  Future<DeltaSyncResult> conectarWearablePelaPrimeiraVez() {
    return _executar(_healthSyncService.carregarHistoricoInicial);
  }

  /// Modo de Diagnóstico Profundo (RELATÓRIO 20260813_0015) — mesmo
  /// [_executar] (loading/sucesso/offline/erro) de
  /// [forcarSincronizacaoAtleta]/[conectarWearablePelaPrimeiraVez], só que
  /// aciona [HealthSyncService.executarDiagnosticoProfundo]: sincroniza os
  /// 30 dias de verdade E imprime o relatório `[SYNC_DIAGNOSTICO]` ponto a
  /// ponto no console enquanto isso — botão "GERAR LOG DIAGNÓSTICO
  /// (30 DIAS)" da tela de histórico.
  Future<DeltaSyncResult> gerarDiagnosticoProfundo() {
    return _executar(_healthSyncService.executarDiagnosticoProfundo);
  }

  /// Núcleo comum entre [forcarSincronizacaoAtleta] e
  /// [conectarWearablePelaPrimeiraVez] — as duas só diferem em qual método
  /// do [HealthSyncService] chamam; todo o resto (estado de loading,
  /// sucesso, fila offline, erro) é idêntico e precisa ficar em um lugar só
  /// para as duas nunca poderem divergir em como tratam uma falha de rede.
  Future<DeltaSyncResult> _executar(
    Future<DeltaSyncResult> Function() acao,
  ) async {
    if (value.isLoading) {
      return const DeltaSyncResult(outcome: DeltaSyncOutcome.erro);
    }

    value = SyncUiState(
      status: SyncUiStatus.carregando,
      ultimaSincronizacaoEm: value.ultimaSincronizacaoEm,
      pendentesNaFila: value.pendentesNaFila,
    );

    final resultado = await acao();

    if (resultado.isSuccess) {
      value = SyncUiState(
        status: SyncUiStatus.sucesso,
        ultimaSincronizacaoEm: resultado.sincronizadoEm ??
            value.ultimaSincronizacaoEm ??
            DateTime.now(),
        pendentesNaFila: value.pendentesNaFila,
      );
      return resultado;
    }

    if (resultado.isOffline) {
      await _enfileirarOffline(resultado.linhas);
      final pendentes = await _lerFilaPendente();
      value = SyncUiState(
        status: SyncUiStatus.offline,
        ultimaSincronizacaoEm: value.ultimaSincronizacaoEm,
        errorMessage: i18n.tr('dashboard.sync_offline_queued'),
        pendentesNaFila: pendentes.length,
      );
      return resultado;
    }

    value = SyncUiState(
      status: SyncUiStatus.falha,
      ultimaSincronizacaoEm: value.ultimaSincronizacaoEm,
      errorMessage:
          resultado.errorMessage ?? i18n.tr('dashboard.health_sync_error'),
      pendentesNaFila: value.pendentesNaFila,
    );
    return resultado;
  }

  /// Resiliência Offline: merges [novasLinhas] into the queue already
  /// persisted in Secure Storage, keyed by `data_referencia` so a day
  /// queued twice while offline overwrites rather than duplicates.
  Future<void> _enfileirarOffline(List<Map<String, dynamic>> novasLinhas) async {
    if (novasLinhas.isEmpty) return;

    final atuais = await _lerFilaPendente();
    final porDia = {
      for (final linha in atuais)
        linha['data_referencia'] as String: linha,
    };
    for (final linha in novasLinhas) {
      porDia[linha['data_referencia'] as String] = linha;
    }

    await _secureStorage.write(
      key: _chaveFilaPendente,
      value: jsonEncode(porDia.values.toList()),
    );
  }

  Future<List<Map<String, dynamic>>> _lerFilaPendente() async {
    final raw = await _secureStorage.read(key: _chaveFilaPendente);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Fires automatically from the connectivity listener the moment the
  /// device comes back online, dispatching whatever [forcarSincronizacaoAtleta]
  /// (or a failed background run) left queued.
  Future<void> _tentarDespacharFila() async {
    final pendentes = await _lerFilaPendente();
    if (pendentes.isEmpty) return;

    final enviado = await _healthSyncService.despacharLinhasPendentes(pendentes);
    if (!enviado) return;

    await _secureStorage.delete(key: _chaveFilaPendente);
    final quando = await _healthSyncService.obterUltimaSincronizacao();
    value = SyncUiState(
      status: SyncUiStatus.sucesso,
      ultimaSincronizacaoEm: quando,
      pendentesNaFila: 0,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
