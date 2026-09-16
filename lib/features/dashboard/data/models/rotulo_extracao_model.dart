/// RELATÓRIO 20260916_0001 — modelo tipado do resultado de
/// `extract-metric-photo` para `X-Tipo-Aparelho: rotulo` (F10 Passo 2,
/// Adendo v5.1 §B). Antes desta tarefa, [CameraCaptureView] só exibia este
/// JSON cru (`SelectableText` com `JsonEncoder.withIndent`) — este modelo é
/// o espelho tipado que a nova UI de card nutricional edita/confirma, mesmo
/// espírito enxuto de `PratoRefeicaoExtracaoModel`.
///
/// Todos os 4 macros são nullable (um rótulo real pode não imprimir todos —
/// `avaliarLeituraRotulo` no servidor só exige que PELO MENOS um venha, ver
/// `extract-metric-photo/index.ts`); a UI trata ausência como campo vazio
/// editável, nunca como erro.
class RotuloExtracaoModel {
  final String? porcaoDescricao;
  final double? caloriasKcal;
  final double? proteinasG;
  final double? carboidratosG;
  final double? gordurasG;
  final List<String> ingredientesPrincipais;
  final bool possivelFotoDeTela;

  const RotuloExtracaoModel({
    this.porcaoDescricao,
    this.caloriasKcal,
    this.proteinasG,
    this.carboidratosG,
    this.gordurasG,
    this.ingredientesPrincipais = const [],
    this.possivelFotoDeTela = false,
  });

  factory RotuloExtracaoModel.fromJson(Map<String, dynamic> json) {
    return RotuloExtracaoModel(
      porcaoDescricao: json['porcao_descricao'] as String?,
      caloriasKcal: (json['calorias_kcal'] as num?)?.toDouble(),
      proteinasG: (json['proteinas_g'] as num?)?.toDouble(),
      carboidratosG: (json['carboidratos_g'] as num?)?.toDouble(),
      gordurasG: (json['gorduras_g'] as num?)?.toDouble(),
      ingredientesPrincipais:
          (json['ingredientes_principais'] as List?)?.cast<String>() ?? const [],
      possivelFotoDeTela: json['possivel_foto_de_tela'] as bool? ?? false,
    );
  }

  /// Payload gravado em `coleta_diaria.valor_jsonb` — já com os valores
  /// EDITADOS pelo usuário na tela de confirmação (não necessariamente os
  /// mesmos que [fromJson] leu do servidor), mesmo espírito de
  /// `ConfirmacaoPratoController` gravar o payload revisado, não a extração
  /// bruta.
  Map<String, dynamic> toJson() => {
        'porcao_descricao': porcaoDescricao,
        'calorias_kcal': caloriasKcal,
        'proteinas_g': proteinasG,
        'carboidratos_g': carboidratosG,
        'gorduras_g': gordurasG,
        'ingredientes_principais': ingredientesPrincipais,
      };
}
