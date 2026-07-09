import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../models/medicamento_model.dart';
import '../models/resultado_exame_model.dart';

/// Data access for [SeniorDashboardPage]: the Pasta Digital de Exames
/// timeline (`resultados_exames`) and the "Medicamentos do Dia" module
/// (`medicamentos_usuario`). Both tables are RLS-scoped to
/// `auth.uid() = usuario_id_anonimo`, so every query here implicitly reads
/// only the signed-in user's own records — no explicit filtering needed
/// beyond the `.eq` calls already required by Postgrest.
class SeniorDashboardService {
  SeniorDashboardService({SupabaseClient? client})
      : _client = client ?? supabaseManager.client;

  final SupabaseClient _client;

  /// Linha do tempo cronológica de exames — mais recentes primeiro.
  Future<List<ResultadoExameModel>> carregarExames() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final response = await _client
          .from('resultados_exames')
          .select()
          .eq('usuario_id_anonimo', userId)
          .order('data_exame', ascending: false);

      return (response as List)
          .cast<Map<String, dynamic>>()
          .map(ResultadoExameModel.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Erro ao carregar resultados_exames: ${e.message}');
      return const [];
    }
  }

  /// Medicamentos ativos, ordenados pelo horário da dose.
  Future<List<MedicamentoModel>> carregarMedicamentos() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final response = await _client
          .from('medicamentos_usuario')
          .select()
          .eq('usuario_id_anonimo', userId)
          .eq('ativo', true)
          .order('horario');

      return (response as List)
          .cast<Map<String, dynamic>>()
          .map(MedicamentoModel.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Erro ao carregar medicamentos_usuario: ${e.message}');
      return const [];
    }
  }

  /// Confirma a dose de hoje — grava o instante atual em
  /// `ultima_dose_tomada_em`, o que faz [MedicamentoModel.tomadaHoje] virar
  /// `true` até a virada do dia.
  Future<bool> confirmarDoseTomada(String medicamentoId) async {
    try {
      await _client.from('medicamentos_usuario').update({
        'ultima_dose_tomada_em': DateTime.now().toIso8601String(),
      }).eq('id', medicamentoId);
      return true;
    } on PostgrestException catch (e) {
      debugPrint('Erro ao confirmar dose de medicamento: ${e.message}');
      return false;
    }
  }
}
