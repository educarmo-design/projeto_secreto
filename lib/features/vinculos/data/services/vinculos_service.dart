import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../models/convite_vinculo_model.dart';
import '../models/vinculo_ativo_model.dart';

/// Leitura de `vinculos_profissional_paciente` do lado do PACIENTE — Etapa de
/// UI de Consentimento (Adendo v4, F.3).
///
/// Duas consultas em vez de um embed do PostgREST: `perfis_profissionais_
/// vinculados` (20260713190000) é uma VIEW, não uma tabela com FK direta para
/// `vinculos_profissional_paciente`, e o PostgREST só embeda relações que
/// detecta via foreign key — não teria como inferir esse join sozinho. O
/// merge de perfil por `profissional_id` é feito aqui, em memória.
class VinculosService {
  VinculosService({SupabaseClient? client}) : _client = client ?? supabaseManager.client;

  final SupabaseClient _client;

  /// Convites com `status = 'pendente'` do usuário logado, mais recentes
  /// primeiro. Mesmo padrão de erro de `SeniorDashboardService`: nunca deixa
  /// a exceção subir — RLS/rede indisponível vira lista vazia (o app mostra o
  /// empty state, não uma tela quebrada) e o detalhe vai só para o log.
  Future<List<ConviteVinculoModel>> carregarConvitesPendentes() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final vinculosResponse = await _client
          .from('vinculos_profissional_paciente')
          .select('id, profissional_id, tipo_produto, criado_em')
          .eq('paciente_id', userId)
          .eq('status', 'pendente')
          .order('criado_em', ascending: false);

      final vinculos = (vinculosResponse as List).cast<Map<String, dynamic>>();
      if (vinculos.isEmpty) return const [];

      final perfisResponse = await _client
          .from('perfis_profissionais_vinculados')
          .select('id, nickname, tipo_profissional');
      final perfisPorId = <String, Map<String, dynamic>>{
        for (final perfil in (perfisResponse as List).cast<Map<String, dynamic>>())
          perfil['id'] as String: perfil,
      };

      return vinculos
          .map(
            (vinculo) => ConviteVinculoModel.fromRows(
              vinculo: vinculo,
              perfilProfissional: perfisPorId[vinculo['profissional_id'] as String],
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Erro ao carregar convites pendentes: ${e.message}');
      return const [];
    }
  }

  /// Vínculos com `status = 'ativo'` do usuário logado — "quais
  /// profissionais de saúde acompanham este usuário agora" (RELATÓRIO
  /// 20261016_0005, Tela de Perfil). `status = 'ativo'` e não `<>
  /// 'encerrado'` é deliberado, mesma regra das RLS de leitura cruzada
  /// (`20260713100000_estruturas_b2b_v4.sql`): `em_carencia` não é mais
  /// acompanhamento de verdade. Mesmo padrão de erro "nunca deixa a
  /// exceção subir" de [carregarConvitesPendentes].
  Future<List<VinculoAtivoModel>> carregarVinculosAtivos() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final vinculosResponse = await _client
          .from('vinculos_profissional_paciente')
          .select('id, profissional_id')
          .eq('paciente_id', userId)
          .eq('status', 'ativo')
          .order('criado_em', ascending: false);

      final vinculos = (vinculosResponse as List).cast<Map<String, dynamic>>();
      if (vinculos.isEmpty) return const [];

      final perfisResponse = await _client
          .from('perfis_profissionais_vinculados')
          .select('id, nickname, tipo_profissional');
      final perfisPorId = <String, Map<String, dynamic>>{
        for (final perfil in (perfisResponse as List).cast<Map<String, dynamic>>())
          perfil['id'] as String: perfil,
      };

      return vinculos
          .map(
            (vinculo) => VinculoAtivoModel.fromRows(
              vinculo: vinculo,
              perfilProfissional: perfisPorId[vinculo['profissional_id'] as String],
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Erro ao carregar vínculos ativos: ${e.message}');
      return const [];
    }
  }
}
