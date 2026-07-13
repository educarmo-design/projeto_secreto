import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../models/medicamento_model.dart';
import '../models/resultado_exame_model.dart';

/// Data access for [SeniorDashboardPage]: the Pasta Digital de Exames
/// timeline (`resultados_exames`) and the "Medicamentos do Dia" module
/// (`medicamentos_usuario`). Ambas as tabelas são RLS-scoped ao dono do dado
/// (`auth.uid() = usuario_id` em exames, `= usuario_id_anonimo` em
/// medicamentos), então toda query aqui lê implicitamente só os registros do
/// usuário logado — nenhum filtro além dos `.eq` que o Postgrest já exige.
class SeniorDashboardService {
  SeniorDashboardService({SupabaseClient? client})
      : _client = client ?? supabaseManager.client;

  final SupabaseClient _client;

  /// Linha do tempo cronológica de exames — mais recentes primeiro.
  Future<List<ResultadoExameModel>> carregarExames() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      // O embed traz o dicionário (`marcadores_referencia`) junto: é dele que
      // saem o nome traduzido e a faixa de referência de fallback do marcador.
      // Vem nulo quando o exame não é reconhecido — ver ResultadoExameModel.
      final response = await _client
          .from('resultados_exames')
          .select(
            '*, marcadores_referencia(nome_exibicao_pt, unidade_padrao, '
            'faixa_referencia_min, faixa_referencia_max)',
          )
          .eq('usuario_id', userId)
          .order('data_coleta', ascending: false);

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
