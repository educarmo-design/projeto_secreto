import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../dashboard/data/models/health_payload_model.dart';

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

/// Um dia de hidratação já somado — [RegistroHidratacaoPage]/o widget de
/// dashboard usam isto, nunca as linhas cruas de `coleta_diaria`.
class HidratacaoDia {
  const HidratacaoDia({required this.data, required this.totalMl});

  final DateTime data;
  final int totalMl;
}

/// Totais de consumo já registrados num dia — soma de todos os `totais` de
/// [ColetaDiariaRepository.gravarRefeicao] gravados naquele dia. Usado pelo
/// card "consumo × meta" pra comparar contra [MetaResumo]
/// (`meta_bem_estar_repository.dart`), nunca lido direto por outra tela.
class ConsumoDia {
  const ConsumoDia({
    required this.calorias,
    required this.proteinasG,
    required this.carboidratosG,
    required this.gordurasG,
  });

  final double calorias;
  final double proteinasG;
  final double carboidratosG;
  final double gordurasG;

  static const zero = ConsumoDia(calorias: 0, proteinasG: 0, carboidratosG: 0, gordurasG: 0);
}

/// Gravador de `coleta_diaria` (F34, Documento Mestre §3.5 G.2) — EAV
/// genérico para leituras frequentes de device/OCR/manual. Grava refeições
/// confirmadas ([gravarRefeicao]), hidratação (N16 — RELATÓRIO 20260819,
/// [gravarAgua]/[buscarTotalAguaDoDia]/[buscarHistoricoAgua]) e, desde N15
/// (RELATÓRIO 20260820), leituras de aparelho por foto
/// ([gravarLeituraAparelho] — balança/pressão/glicosímetro).
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

  static const String _atributoAgua = 'agua_ml';
  static const String _origemManual = 'manual';

  /// N16 — grava UM registro de água (um toque de "+1 copo" ou uma
  /// quantidade avulsa digitada) em ml. Sempre `origem = 'manual'`: não
  /// existe OCR/wearable de hidratação, o usuário sempre confirma a
  /// quantidade. [confianca] fica de fora de propósito (a coluna é
  /// `NULL` — CHECK da migration já permite, ver comentário de cabeçalho
  /// da migration F34: "NULL é válido só para origem='manual'").
  Future<ColetaDiariaResult> gravarAgua({
    required int mililitros,
    DateTime? dataColeta,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return const ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail: 'ColetaDiariaRepository.gravarAgua: currentUser é null.',
      );
    }

    try {
      await _supabase.from('coleta_diaria').insert({
        'usuario_id': usuarioId,
        'atributo': _atributoAgua,
        'valor_numerico': mililitros,
        'unidade': 'ml',
        'origem': _origemManual,
        'data_coleta': _dateOnly(dataColeta ?? DateTime.now()),
      });
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint('ColetaDiariaRepository.gravarAgua: ${e.code} — ${e.message}');
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar o registro de água agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('ColetaDiariaRepository.gravarAgua: ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao salvar o registro de água.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }

  /// N16 — soma de todos os registros de água do dia [data] (hoje, por
  /// padrão). `0` tanto para "ninguém logado" quanto para "nenhum registro
  /// ainda" — mesma convenção de ausência benigna do resto do app (ver
  /// [PerfilUsuarioRepository]), só que aqui o valor natural de "nada
  /// ainda" já é 0, não precisa de `null`.
  Future<int> buscarTotalAguaDoDia({DateTime? data}) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return 0;

    final linhas = await _supabase
        .from('coleta_diaria')
        .select('valor_numerico')
        .eq('usuario_id', usuarioId)
        .eq('atributo', _atributoAgua)
        .eq('data_coleta', _dateOnly(data ?? DateTime.now()));

    return (linhas as List)
        .cast<Map<String, dynamic>>()
        .fold<int>(0, (soma, linha) => soma + ((linha['valor_numerico'] as num?)?.round() ?? 0));
  }

  /// N16 — histórico somado por dia, mais recente primeiro, para os
  /// últimos [dias]. Agrupamento feito em Dart (não GROUP BY no
  /// PostgREST): `coleta_diaria` tem várias linhas por dia (um registro
  /// por toque de "+1 copo"), mesmo espírito do agrupamento por dia já
  /// feito em `HealthSyncService._mesclarPorDia` — volume baixo o
  /// suficiente (poucos registros/dia, poucos dias) pra não justificar uma
  /// RPC só pra isso. Lista vazia (não erro) quando ninguém está logado.
  Future<List<HidratacaoDia>> buscarHistoricoAgua({int dias = 7}) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return const [];

    final desde = DateTime.now().subtract(Duration(days: dias - 1));
    final linhas = await _supabase
        .from('coleta_diaria')
        .select('valor_numerico, data_coleta')
        .eq('usuario_id', usuarioId)
        .eq('atributo', _atributoAgua)
        .gte('data_coleta', _dateOnly(desde))
        .order('data_coleta', ascending: false);

    final totalPorDia = <String, int>{};
    for (final linha in (linhas as List).cast<Map<String, dynamic>>()) {
      final dataStr = linha['data_coleta'] as String;
      final ml = (linha['valor_numerico'] as num?)?.round() ?? 0;
      totalPorDia[dataStr] = (totalPorDia[dataStr] ?? 0) + ml;
    }

    final datasOrdenadas = totalPorDia.keys.toList()..sort((a, b) => b.compareTo(a));
    return datasOrdenadas
        .map((d) => HidratacaoDia(data: DateTime.parse(d), totalMl: totalPorDia[d]!))
        .toList();
  }

  /// N15 (RELATÓRIO 20260820) — grava UMA leitura de aparelho por foto
  /// (balança/pressão arterial/glicosímetro) em `coleta_diaria`. Até esta
  /// tarefa, [showExtractedDataDialog] só EXIBIA o resultado extraído —
  /// nada persistia, o dado se perdia ao fechar o diálogo (achado real,
  /// não suposição: `HealthPayloadDialog`'s "Confirmar" só dava
  /// `Navigator.pop()`, sem chamada nenhuma ao Supabase).
  ///
  /// [atributo] é o mesmo nome de [TipoAparelho] em texto livre
  /// (`'balanca'`/`'pressao_arterial'`/`'glicosimetro'` — resolvido pelo
  /// chamador, esta classe não depende do enum de `dashboard`, só do
  /// [HealthPayloadModel] que ele já produz). `valor_jsonb` = o
  /// [HealthPayloadModel.toJson()] inteiro, mesmo padrão de
  /// `gravarRefeicao`: nenhum EAV puro pra um payload que já é uma leitura
  /// atômica.
  Future<ColetaDiariaResult> gravarLeituraAparelho({
    required HealthPayloadModel payload,
    required String atributo,
    DateTime? dataColeta,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Sessão expirada — faça login novamente.',
        debugDetail:
            'ColetaDiariaRepository.gravarLeituraAparelho($atributo): currentUser é null.',
      );
    }

    try {
      await _supabase.from('coleta_diaria').insert({
        'usuario_id': usuarioId,
        'atributo': atributo,
        'valor_jsonb': payload.toJson(),
        'origem': 'ocr_$atributo',
        'data_coleta': _dateOnly(dataColeta ?? DateTime.now()),
      });
      return const ColetaDiariaResult(success: true);
    } on PostgrestException catch (e) {
      debugPrint(
        'ColetaDiariaRepository.gravarLeituraAparelho($atributo): ${e.code} — ${e.message}',
      );
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar a leitura agora. Tente novamente.',
        debugDetail: 'PostgrestException ${e.code}: ${e.message}',
      );
    } catch (e, stackTrace) {
      debugPrint('ColetaDiariaRepository.gravarLeituraAparelho($atributo): ${e.runtimeType} — $e');
      debugPrint(stackTrace.toString());
      return ColetaDiariaResult(
        success: false,
        errorMessage: 'Erro inesperado ao salvar a leitura.',
        debugDetail: '${e.runtimeType}: $e',
      );
    }
  }

  /// RELATÓRIO 20260820 — soma de todas as refeições confirmadas HOJE, pro
  /// card "consumo × meta". Lê `valor_jsonb->totais` (gravado por
  /// [gravarRefeicao]) de cada linha e soma em Dart — mesmo padrão de
  /// [buscarHistoricoAgua] (poucas linhas/dia, não justifica RPC). Nunca
  /// lança: erro de rede/parsing devolve [ConsumoDia.zero] (mesma convenção
  /// "ausência benigna" do resto da classe) — o card mostra "sem dados
  /// ainda", nunca quebra a tela.
  Future<ConsumoDia> buscarConsumoHoje() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return ConsumoDia.zero;

    try {
      final linhas = await _supabase
          .from('coleta_diaria')
          .select('valor_jsonb')
          .eq('usuario_id', usuarioId)
          .eq('atributo', _atributoRefeicao)
          .eq('data_coleta', _dateOnly(DateTime.now()));

      var calorias = 0.0;
      var proteinas = 0.0;
      var carboidratos = 0.0;
      var gorduras = 0.0;
      for (final linha in (linhas as List).cast<Map<String, dynamic>>()) {
        final totais = (linha['valor_jsonb'] as Map<String, dynamic>?)?['totais']
            as Map<String, dynamic>?;
        if (totais == null) continue;
        calorias += (totais['calorias'] as num?)?.toDouble() ?? 0;
        proteinas += (totais['proteinas_g'] as num?)?.toDouble() ?? 0;
        carboidratos += (totais['carboidratos_g'] as num?)?.toDouble() ?? 0;
        gorduras += (totais['gorduras_g'] as num?)?.toDouble() ?? 0;
      }
      return ConsumoDia(
        calorias: calorias,
        proteinasG: proteinas,
        carboidratosG: carboidratos,
        gordurasG: gorduras,
      );
    } catch (e) {
      debugPrint('ColetaDiariaRepository.buscarConsumoHoje: ${e.runtimeType} — $e');
      return ConsumoDia.zero;
    }
  }

  static String _dateOnly(DateTime date) => date.toIso8601String().split('T').first;
}
