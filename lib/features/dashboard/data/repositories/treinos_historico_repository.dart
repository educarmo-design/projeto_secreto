import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/treino_model.dart';

/// RELATÓRIO 20260811_0002 (decisão do fundador) — lê `atividades_fisicas_treinos`
/// direto do Supabase, mesmo princípio de [TelemetriaHistoricoRepository]:
/// sempre um SELECT novo, nunca cache local.
class TreinosHistoricoRepository {
  TreinosHistoricoRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Últimos [limite] treinos do usuário logado, mais recente primeiro.
  /// `select('*, tipos_atividades_fisicas(nome_exibicao)')` — embed do
  /// PostgREST via a FK `tipo_atividade_codigo -> tipos_atividades_fisicas
  /// (nome_codigo)`, resolve o nome amigável da modalidade num SELECT só,
  /// sem N+1. RLS `atividades_fisicas_treinos_select_own` já garante que só
  /// o dono lê; `.eq('usuario_id', ...)` aqui é só pra não pedir dado que
  /// não vai usar, mesma convenção de [TelemetriaHistoricoRepository].
  ///
  /// Lista vazia (não erro) quando ninguém está logado.
  Future<List<TreinoModel>> buscarUltimosTreinos({int limite = 50}) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return const [];

    final linhas = await _supabase
        .from('atividades_fisicas_treinos')
        .select('*, tipos_atividades_fisicas(nome_exibicao)')
        .eq('usuario_id', usuarioId)
        .order('inicio_atividade', ascending: false)
        .limit(limite);

    return (linhas as List)
        .cast<Map<String, dynamic>>()
        .map(TreinoModel.fromJson)
        .toList();
  }
}
