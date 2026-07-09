import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../models/b2b_analytics_payload.dart';
import '../services/health_score_engine.dart';

/// ONDA 3 — envia os relatórios B2B consolidados (Painel Web das
/// Seguradoras/Médicos) uma vez por noite, em um único lote GZIP.
///
/// Zero Trust: esta classe roda dentro do app do usuário final, sob a
/// mesma sessão RLS-restrita de sempre — ela só consegue ler/exportar os
/// próprios dados do usuário logado, nunca os de terceiros. A agregação de
/// *múltiplos* usuários num relatório consolidado para a seguradora é
/// necessariamente um job server-side com privilégio elevado (fora do
/// alcance de um app mobile); o que este repositório estrutura é a
/// contribuição individual — a "linha" que cada usuário opt-in envia — que
/// esse job do lado do servidor consolida depois.
///
/// Custo Zero de banda: os pontos da curva de HealthScore são acumulados
/// localmente noite após noite ([registrarSnapshotDiario]) e só saem pela
/// rede quando [sincronizarLoteNoturno] finalmente os envia — comprimidos
/// com GZIP — como um único lote, nunca ponto a ponto. Pensado para ser
/// chamado a partir da mesma janela de execução noturna (Wi-Fi + carregador
/// conectados) que `BackgroundSyncManager` já usa para o
/// `sync_diario_wearables`.
class B2BSyncRepository {
  B2BSyncRepository({
    http.Client? httpClient,
    SupabaseClient? client,
    FlutterSecureStorage? secureStorage,
    HealthScoreEngine? healthScoreEngine,
  })  : _httpClient = httpClient ?? http.Client(),
        _client = client ?? Supabase.instance.client,
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _healthScoreEngine = healthScoreEngine ?? HealthScoreEngine();

  final http.Client _httpClient;
  final SupabaseClient _client;
  final FlutterSecureStorage _secureStorage;
  final HealthScoreEngine _healthScoreEngine;

  static const Duration _requestTimeout = Duration(seconds: 60);
  static const int _diasHistoricoClinico = 30;
  static const String _filaSnapshotsKey = 'b2b_sync_fila_snapshots_v1';

  /// Calcula o HealthScore de hoje e enfileira localmente — chamado uma vez
  /// por dia (job noturno). Não fala com a rede: só acumula mais um ponto
  /// da curva para o próximo [sincronizarLoteNoturno].
  Future<void> registrarSnapshotDiario() async {
    final resultado = await _healthScoreEngine.calcularParaUsuarioAtual();
    if (resultado == null) return;

    final fila = await _lerFila();
    fila.add(resultado);
    await _salvarFila(fila);
  }

  /// Monta o [B2BAnalyticsPayload] a partir da fila local acumulada +
  /// histórico clínico recente, comprime em GZIP e envia num único POST ao
  /// endpoint B2B. Só esvazia a fila local após confirmação de sucesso
  /// (HTTP 200) — uma falha de rede preserva os snapshots acumulados para a
  /// próxima tentativa, sem perder histórico nem duplicar envio.
  Future<B2BSyncResult> sincronizarLoteNoturno() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const B2BSyncResult(
        success: false,
        totalPontosEnviados: 0,
        errorMessage: 'Usuário não autenticado.',
      );
    }

    final fila = await _lerFila();
    if (fila.isEmpty) {
      return const B2BSyncResult(success: true, totalPontosEnviados: 0);
    }

    final payload = await _construirPayload(userId, fila);
    if (payload == null) {
      return const B2BSyncResult(
        success: false,
        totalPontosEnviados: 0,
        errorMessage: 'Perfil anonimizável não encontrado.',
      );
    }

    try {
      final corpoComprimido = _comprimirPayload(payload);

      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.b2bAnalyticsEndpoint),
            headers: {
              ..._authHeaders(),
              'Content-Type': 'application/json',
              'Content-Encoding': 'gzip',
            },
            body: corpoComprimido,
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        return B2BSyncResult(
          success: false,
          totalPontosEnviados: 0,
          errorMessage: 'Falha ao enviar lote B2B (HTTP ${response.statusCode}).',
        );
      }

      await _limparFila();
      return B2BSyncResult(success: true, totalPontosEnviados: fila.length);
    } on TimeoutException {
      return const B2BSyncResult(
        success: false,
        totalPontosEnviados: 0,
        errorMessage: 'Tempo esgotado ao enviar o lote B2B.',
      );
    } on http.ClientException {
      return const B2BSyncResult(
        success: false,
        totalPontosEnviados: 0,
        errorMessage: 'Erro de conexão ao enviar o lote B2B.',
      );
    }
  }

  /// GZIP sobre o JSON serializado — a compactação em si é o que garante
  /// Custo Zero de banda, junto com o envio ser um lote único por noite em
  /// vez de uma chamada por ponto de dado.
  List<int> _comprimirPayload(B2BAnalyticsPayload payload) {
    final corpoJson = jsonEncode(payload.toJson());
    return gzip.encode(utf8.encode(corpoJson));
  }

  Future<B2BAnalyticsPayload?> _construirPayload(
    String userId,
    List<HealthScoreResult> fila,
  ) async {
    final perfil = await _buscarPerfilAnonimizavel(userId);
    if (perfil == null) return null;

    final historicoClinico = await _healthScoreEngine.buscarHistoricoClinico(
      userId,
      dias: _diasHistoricoClinico,
    );

    return B2BAnalyticsPayload.anonimizar(
      usuarioIdAnonimo: userId,
      dataNascimento: perfil.dataNascimento,
      geoRankingId: perfil.geoRankingId,
      historicoScores: fila,
      historicoClinico: historicoClinico,
    );
  }

  /// Lê só as duas colunas necessárias para a blindagem LGPD do payload —
  /// nunca `nome`/`telefone`/`email`/`cep` de `perfis_usuarios`, mesmo que
  /// estejam disponíveis na mesma linha.
  Future<_PerfilAnonimizavel?> _buscarPerfilAnonimizavel(String userId) async {
    try {
      final response = await _client
          .from('perfis_usuarios')
          .select('data_nascimento, geo_ranking_id')
          .eq('id', userId)
          .maybeSingle();
      if (response == null) return null;
      return _PerfilAnonimizavel.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('Erro ao buscar perfil anonimizável: ${e.message}');
      return null;
    }
  }

  Future<List<HealthScoreResult>> _lerFila() async {
    final raw = await _secureStorage.read(key: _filaSnapshotsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .cast<Map<String, dynamic>>()
          .map(HealthScoreResult.fromJson)
          .toList();
    } catch (e) {
      debugPrint('Fila de snapshots B2B corrompida, descartando: $e');
      return [];
    }
  }

  Future<void> _salvarFila(List<HealthScoreResult> fila) async {
    await _secureStorage.write(
      key: _filaSnapshotsKey,
      value: jsonEncode(fila.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> _limparFila() => _secureStorage.delete(key: _filaSnapshotsKey);

  Map<String, String> _authHeaders() {
    final session = _client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }
}

class _PerfilAnonimizavel {
  final DateTime? dataNascimento;
  final String? geoRankingId;

  const _PerfilAnonimizavel({this.dataNascimento, this.geoRankingId});

  factory _PerfilAnonimizavel.fromJson(Map<String, dynamic> json) {
    final dataNascimentoRaw = json['data_nascimento'] as String?;
    return _PerfilAnonimizavel(
      dataNascimento:
          dataNascimentoRaw != null ? DateTime.parse(dataNascimentoRaw) : null,
      geoRankingId: json['geo_ranking_id'] as String?,
    );
  }
}

/// Outcome of [B2BSyncRepository.sincronizarLoteNoturno].
@immutable
class B2BSyncResult {
  final bool success;
  final int totalPontosEnviados;
  final String? errorMessage;

  const B2BSyncResult({
    required this.success,
    required this.totalPontosEnviados,
    this.errorMessage,
  });
}
