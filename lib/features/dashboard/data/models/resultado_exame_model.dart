/// A single row read from `resultados_exames` — one lab result, used to
/// build the Pasta Digital de Exames chronological timeline on
/// [SeniorDashboardPage]. Field-for-field mirror of the table; no JSONB.
class ResultadoExameModel {
  final int id;
  final String tipoExame;
  final double? valorResultado;
  final String? unidadeMedida;
  final double? valorReferenciaMin;
  final double? valorReferenciaMax;
  final String? laboratorio;
  final DateTime dataExame;
  final String? observacoes;

  const ResultadoExameModel({
    required this.id,
    required this.tipoExame,
    this.valorResultado,
    this.unidadeMedida,
    this.valorReferenciaMin,
    this.valorReferenciaMax,
    this.laboratorio,
    required this.dataExame,
    this.observacoes,
  });

  factory ResultadoExameModel.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) => (value as num?)?.toDouble();
    return ResultadoExameModel(
      id: json['id'] as int,
      tipoExame: json['tipo_exame'] as String,
      valorResultado: asDouble(json['valor_resultado']),
      unidadeMedida: json['unidade_medida'] as String?,
      valorReferenciaMin: asDouble(json['valor_referencia_min']),
      valorReferenciaMax: asDouble(json['valor_referencia_max']),
      laboratorio: json['laboratorio'] as String?,
      dataExame: DateTime.parse(json['data_exame'] as String),
      observacoes: json['observacoes'] as String?,
    );
  }

  /// `true` quando o resultado sai da faixa de referência informada pelo
  /// laboratório — usado para destacar o item na timeline. `false` (nunca
  /// "fora da faixa") quando faltar valor ou referência para comparar.
  bool get foraDaFaixaReferencia {
    if (valorResultado == null) return false;
    if (valorReferenciaMin != null && valorResultado! < valorReferenciaMin!) {
      return true;
    }
    if (valorReferenciaMax != null && valorResultado! > valorReferenciaMax!) {
      return true;
    }
    return false;
  }
}
