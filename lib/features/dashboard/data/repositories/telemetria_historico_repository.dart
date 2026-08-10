import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/health_payload_model.dart';

/// N19 (Tela de Histórico) — lê `metricas_saude_diarias` DIRETO do
/// Supabase, nunca de cache local do celular.
///
/// Isso é deliberado, não só "não tinha cache pronto": a Restrição de
/// Minimização/Prova de Persistência desta tarefa pede explicitamente que
/// esta tela prove que a gravação do N17/N18 chegou ao BANCO — ler de um
/// cache local (Secure Storage, SharedPreferences, o que for) só provaria
/// que o aparelho "lembra" de algo local, nunca que o servidor realmente
/// tem o dado. Por isso nenhum método aqui toca em
/// FlutterSecureStorage/SharedPreferences — é sempre um SELECT novo.
class TelemetriaHistoricoRepository {
  TelemetriaHistoricoRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Últimos [dias] dias (padrão 30) de `metricas_saude_diarias` do usuário
  /// logado, mais recente primeiro. SELECT simples, sem RPC/JOIN — a RLS
  /// `metricas_saude_diarias_select_own` (20260708174650) já garante que só
  /// o dono da linha consegue lê-la; não precisa filtrar por usuário aqui
  /// por segurança (o banco já recusaria a linha de outra pessoa), só por
  /// não pedir dado que não vai usar.
  ///
  /// Lista vazia (não erro) quando ninguém está logado — mesma convenção
  /// de `HealthSyncService._lerEGravar`.
  Future<List<HealthPayloadModel>> buscarUltimosDias({int dias = 30}) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return const [];

    final desde = DateTime.now().subtract(Duration(days: dias));
    final desdeData = desde.toIso8601String().split('T').first;

    final linhas = await _supabase
        .from('metricas_saude_diarias')
        .select()
        .eq('usuario_id_anonimo', usuarioId)
        .gte('data_referencia', desdeData)
        .order('data_referencia', ascending: false);

    return (linhas as List)
        .cast<Map<String, dynamic>>()
        .map(HealthPayloadModel.fromJson)
        .toList();
  }
}
