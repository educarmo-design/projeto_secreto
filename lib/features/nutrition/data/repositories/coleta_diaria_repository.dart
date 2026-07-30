import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ColetaDiariaResult {
  final bool success;
  final String? errorMessage;

  /// Classe/mensagem técnica real — sempre preenchida na falha, nunca
  /// decidida aqui se deve aparecer na tela (isso é decisão de
  /// apresentação; ver `_podeExibirDetalheTecnico` em
  /// [ConfirmacaoPratoController]). Regra 0.15: nunca engolir a exceção.
  final String? debugDetail;

  const ColetaDiariaResult({
    required this.success,
    this.errorMessage,
    this.debugDetail,
  });
}

/// Gravador de `coleta_diaria` (F34, Documento Mestre §3.5 G.2) — EAV
/// genérico para leituras frequentes de device/OCR/manual. Hoje só grava
/// refeições confirmadas ([gravarRefeicao]); os demais atributos (peso,
/// pressão, glicose de dedo via aparelho) seguem sem um gravador próprio —
/// fora do escopo do F34 (ver RELATÓRIO DE FIM DE TAREFA).
class ColetaDiariaRepository {
  ColetaDiariaRepository({SupabaseClient? supabaseClient})
      : _supabaseOverride = supabaseClient;

  /// Só resolvido no primeiro uso real (dentro de [gravarRefeicao]), nunca
  /// no construtor: `Supabase.instance` lança se `Supabase.initialize` nunca
  /// rodou (todo teste de widget/controller que constrói
  /// `ConfirmacaoPratoController` sem injetar um repositório fake bateria
  /// nisso na hora — mesma categoria de bug já corrigido uma vez neste
  /// projeto, ver `obterChamarEmbedding`/`obterBuscaSemantica` em
  /// extract-metric-photo/index.ts).
  final SupabaseClient? _supabaseOverride;
  SupabaseClient get _supabase => _supabaseOverride ?? Supabase.instance.client;

  static const String _atributoRefeicao = 'refeicao';
  static const String _origemOcrRefeicao = 'ocr_refeicao';

  /// Grava UMA linha para a refeição inteira já confirmada pelo usuário —
  /// [payloadRevisado] (itens + totais, já com as quantidades editadas) vai
  /// inteiro em `valor_jsonb` (ver comentário de cabeçalho da migration:
  /// EAV puro fragmentaria uma leitura atômica em dezenas de linhas sem
  /// ganho nenhum). [confianca] é o score agregado que
  /// [ConfirmacaoPratoController] já calculou (mínimo entre os itens
  /// confirmados).
  Future<ColetaDiariaResult> gravarRefeicao({
    required Map<String, dynamic> payloadRevisado,
    required double? confianca,
    DateTime? dataColeta,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return const ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail: 'ColetaDiariaRepository.gravarRefeicao: currentUser é null.',
      );
    }

    try {
      await _supabase.from('coleta_diaria').insert({
        'usuario_id': usuarioId,
        'atributo': _atributoRefeicao,
        'valor_jsonb': payloadRevisado,
        'origem': _origemOcrRefeicao,
        if (confianca != null) 'confianca': confianca,
        'data_coleta': _dateOnly(dataColeta ?? DateTime.now()),
      });
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint('ColetaDiariaRepository.gravarRefeicao: ${e.code} — ${e.message}');
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar a refeição agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      // Qualquer falha não prevista (timeout de rede, etc.) — nunca some
      // sem rastro (mesma filosofia de CameraCaptureController._estadoDeErro).
      debugPrint('ColetaDiariaRepository.gravarRefeicao: ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao salvar a refeição.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }

  static String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;
}
