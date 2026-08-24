import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/favorita_model.dart';
import 'coleta_diaria_repository.dart' show ColetaDiariaResult;

/// N13 (Documento Mestre v7.0, Parte V1.H) — CRUD de `alimentos_favoritos`.
/// Mesmo padrão de resultado/tratamento de erro de [ColetaDiariaRepository]
/// (reaproveita [ColetaDiariaResult] em vez de duplicar a classe): nunca
/// engole exceção (Regra 0.15), sempre mensagem amigável + detalhe técnico
/// pra debug.
class FavoritasRepository {
  FavoritasRepository({SupabaseClient? supabaseClient})
      : _supabaseOverride = supabaseClient;

  final SupabaseClient? _supabaseOverride;
  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  /// Salva [payloadJsonb] (mesmo formato de
  /// `ConfirmacaoPratoController.payloadRevisado()`) como favorita.
  /// [tipoRefeicao] nunca é opcional — a spec exige favoritas SEMPRE
  /// categorizadas por tipo de refeição, "múltiplas" por tipo (sem
  /// unicidade de nome).
  Future<ColetaDiariaResult> salvar({
    required String nome,
    required TipoRefeicao tipoRefeicao,
    required Map<String, dynamic> payloadJsonb,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return const ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail: 'FavoritasRepository.salvar: currentUser é null.',
      );
    }

    try {
      await _supabase.from('alimentos_favoritos').insert({
        'usuario_id': usuarioId,
        'tipo_refeicao': tipoRefeicao.codigo,
        'nome': nome,
        'payload_jsonb': payloadJsonb,
      });
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint('FavoritasRepository.salvar: ${e.code} — ${e.message}');
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar a favorita agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('FavoritasRepository.salvar: ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao salvar a favorita.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }

  /// Lista favoritas do usuário logado, mais recente primeiro.
  /// [tipoRefeicao] filtra por tipo quando informado (tela de "escolher
  /// favorita" abre já filtrada pelo tipo que o usuário está registrando);
  /// `null` traz todas (tela de gestão no perfil). Lista vazia (não erro)
  /// tanto pra "ninguém logado" quanto pra "nenhuma favorita ainda".
  Future<List<FavoritaModel>> listar({TipoRefeicao? tipoRefeicao}) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return const [];

    try {
      var query = _supabase
          .from('alimentos_favoritos')
          .select('id, tipo_refeicao, nome, payload_jsonb, criado_em')
          .eq('usuario_id', usuarioId);
      if (tipoRefeicao != null) {
        query = query.eq('tipo_refeicao', tipoRefeicao.codigo);
      }
      final linhas = await query.order('criado_em', ascending: false);

      return (linhas as List)
          .cast<Map<String, dynamic>>()
          .map(FavoritaModel.fromJson)
          .toList();
    } catch (e) {
      debugPrint('FavoritasRepository.listar: ${e.runtimeType} — $e');
      return const [];
    }
  }

  /// RLS `alimentos_favoritos_delete_own` já garante que só o dono apaga —
  /// sem checagem extra de segurança no cliente.
  Future<ColetaDiariaResult> excluir(String id) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return const ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail: 'FavoritasRepository.excluir: currentUser é null.',
      );
    }

    try {
      await _supabase.from('alimentos_favoritos').delete().eq('id', id);
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint('FavoritasRepository.excluir: ${e.code} — ${e.message}');
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível excluir a favorita agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('FavoritasRepository.excluir: ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao excluir a favorita.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }

  /// "Manutenção no perfil (excluir/trocar tipo)" — a segunda metade da
  /// spec (N13). RLS `alimentos_favoritos_update_own` já garante que só o
  /// dono edita.
  Future<ColetaDiariaResult> atualizarTipo(String id, TipoRefeicao novoTipo) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return const ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail: 'FavoritasRepository.atualizarTipo: currentUser é null.',
      );
    }

    try {
      await _supabase
          .from('alimentos_favoritos')
          .update({'tipo_refeicao': novoTipo.codigo}).eq('id', id);
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint('FavoritasRepository.atualizarTipo: ${e.code} — ${e.message}');
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível atualizar a favorita agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('FavoritasRepository.atualizarTipo: ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao atualizar a favorita.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }

  /// RELATÓRIO 20260823 — 2º gap encontrado pelo fundador testando: editar o
  /// CONTEÚDO (itens/quantidades) de uma favorita já salva nunca tinha sido
  /// implementado, só [atualizarTipo]/[excluir]. Sobrescreve
  /// `payload_jsonb` inteiro — mesmo formato de
  /// `ConfirmacaoPratoController.payloadRevisado()`, chamado por
  /// [ConfirmacaoPratoController.confirmar] quando injetado como
  /// `aoConfirmar` (ver [FavoritaEmEdicao] em `ConfirmacaoPratoPage`). RLS
  /// `alimentos_favoritos_update_own` já garante que só o dono edita.
  Future<ColetaDiariaResult> atualizarPayload(
    String id,
    Map<String, dynamic> payloadJsonb,
  ) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return const ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail: 'FavoritasRepository.atualizarPayload: currentUser é null.',
      );
    }

    try {
      await _supabase
          .from('alimentos_favoritos')
          .update({'payload_jsonb': payloadJsonb}).eq('id', id);
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint('FavoritasRepository.atualizarPayload: ${e.code} — ${e.message}');
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar as alterações agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('FavoritasRepository.atualizarPayload: ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao salvar as alterações.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }
}
