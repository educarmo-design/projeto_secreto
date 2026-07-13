/// A single row read from `resultados_exames` — one lab measurement, used to
/// build the Pasta Digital de Exames chronological timeline on
/// [SeniorDashboardPage].
///
/// A tabela é EAV desde 20260713100000_estruturas_b2b_v4.sql (Adendo v4, G.1):
/// uma linha por medição, identificada por `marcador_codigo`. O nome legível e
/// a faixa de referência genérica vivem na tabela-dicionário
/// `marcadores_referencia` (C.4) e chegam aqui pelo embed do PostgREST — por
/// isso [nomeExibicao] e os fallbacks de faixa/unidade.
class ResultadoExameModel {
  final int id;

  /// Código normalizado do dicionário (ex. `ldl`). Nulo quando o OCR leu um
  /// exame fora do núcleo reconhecido — nesse caso só [rotuloOriginal] existe.
  final String? marcadorCodigo;

  /// O rótulo exatamente como saiu do laudo, sempre preservado.
  final String? rotuloOriginal;

  /// `nome_exibicao_pt` do dicionário; nulo quando o marcador não é reconhecido.
  final String? nomeExibicao;

  final double? valorNumerico;

  /// Resultados não-numéricos ("não reagente", "negativo").
  final String? valorTexto;

  final String? unidade;
  final double? valorReferenciaMin;
  final double? valorReferenciaMax;
  final String? laboratorio;
  final DateTime dataColeta;
  final String? observacoes;

  const ResultadoExameModel({
    required this.id,
    this.marcadorCodigo,
    this.rotuloOriginal,
    this.nomeExibicao,
    this.valorNumerico,
    this.valorTexto,
    this.unidade,
    this.valorReferenciaMin,
    this.valorReferenciaMax,
    this.laboratorio,
    required this.dataColeta,
    this.observacoes,
  });

  factory ResultadoExameModel.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) => (value as num?)?.toDouble();
    final dicionario = json['marcadores_referencia'] as Map<String, dynamic>?;

    return ResultadoExameModel(
      id: json['id'] as int,
      marcadorCodigo: json['marcador_codigo'] as String?,
      rotuloOriginal: json['rotulo_original'] as String?,
      nomeExibicao: dicionario?['nome_exibicao_pt'] as String?,
      valorNumerico: asDouble(json['valor_numerico']),
      valorTexto: json['valor_texto'] as String?,
      unidade: json['unidade'] as String? ??
          dicionario?['unidade_padrao'] as String?,
      // A faixa do próprio laudo tem precedência sobre a do dicionário: ela
      // veio do método e da população daquele laboratório. A do dicionário é
      // fallback para quando o PDF não trouxe faixa nenhuma.
      valorReferenciaMin: asDouble(json['valor_referencia_min']) ??
          asDouble(dicionario?['faixa_referencia_min']),
      valorReferenciaMax: asDouble(json['valor_referencia_max']) ??
          asDouble(dicionario?['faixa_referencia_max']),
      laboratorio: json['laboratorio'] as String?,
      dataColeta: DateTime.parse(json['data_coleta'] as String),
      observacoes: json['observacoes'] as String?,
    );
  }

  /// O que a timeline mostra como nome do exame: o nome traduzido do
  /// dicionário quando o marcador é reconhecido; senão o rótulo bruto do laudo.
  String get titulo => nomeExibicao ?? rotuloOriginal ?? marcadorCodigo ?? '—';

  /// Valor formatado para a timeline — numérico com unidade, ou o texto do
  /// laudo quando o resultado não é numérico. Nulo quando não há valor.
  String? get valorExibicao {
    if (valorNumerico != null) {
      return unidade != null ? '$valorNumerico $unidade' : '$valorNumerico';
    }
    return valorTexto;
  }

  /// `true` quando o resultado sai da faixa de referência conhecida — usado
  /// para destacar o item na timeline. `false` (nunca "fora da faixa") quando
  /// faltar valor ou referência para comparar.
  bool get foraDaFaixaReferencia {
    if (valorNumerico == null) return false;
    if (valorReferenciaMin != null && valorNumerico! < valorReferenciaMin!) {
      return true;
    }
    if (valorReferenciaMax != null && valorNumerico! > valorReferenciaMax!) {
      return true;
    }
    return false;
  }
}
