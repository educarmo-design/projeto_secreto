/// Tipo de refeição de uma favorita (N13) — texto livre no banco
/// (`alimentos_favoritos.tipo_refeicao`, CHECK constraint), tipado aqui pro
/// resto do app nunca comparar string solta.
enum TipoRefeicao {
  cafeDaManha('cafe_da_manha'),
  almoco('almoco'),
  lanche('lanche'),
  jantar('jantar');

  const TipoRefeicao(this.codigo);

  /// Valor gravado no banco — exatamente o que a CHECK constraint aceita.
  final String codigo;

  static TipoRefeicao? fromCodigo(String? codigo) {
    if (codigo == null) return null;
    for (final valor in values) {
      if (valor.codigo == codigo) return valor;
    }
    return null;
  }
}

/// Uma refeição salva como favorita (N13, Documento Mestre Parte V1.H) —
/// [payloadJsonb] é o MESMO formato que `ConfirmacaoPratoController.
/// payloadRevisado()` produz (itens + totais), reaproveitado sem
/// recalcular ao "usar" a favorita — ver
/// `ColetaDiariaRepository.gravarRefeicao`.
class FavoritaModel {
  const FavoritaModel({
    required this.id,
    required this.tipoRefeicao,
    required this.nome,
    required this.payloadJsonb,
    required this.criadoEm,
  });

  final String id;
  final TipoRefeicao tipoRefeicao;
  final String nome;
  final Map<String, dynamic> payloadJsonb;
  final DateTime criadoEm;

  /// Total de calorias do prato salvo — lido de `payload_jsonb.totais`,
  /// mesmo formato de `ConfirmacaoPratoController.payloadRevisado()`.
  /// `null` só seria possível se o payload estivesse malformado (não
  /// deveria acontecer — sempre escrito por [gravarRefeicao]/
  /// `salvarFavorita`, nunca digitado à mão).
  double? get caloriasTotais {
    final totais = payloadJsonb['totais'] as Map<String, dynamic>?;
    return (totais?['calorias'] as num?)?.toDouble();
  }

  /// Quantos itens o prato salvo tem — pra exibir "3 itens" na lista sem
  /// a tela precisar conhecer o formato interno do JSON.
  int get quantidadeItens => (payloadJsonb['itens'] as List?)?.length ?? 0;

  factory FavoritaModel.fromJson(Map<String, dynamic> json) {
    final tipo = TipoRefeicao.fromCodigo(json['tipo_refeicao'] as String?);
    if (tipo == null) {
      throw FormatException(
        'tipo_refeicao desconhecido na favorita: ${json['tipo_refeicao']}',
      );
    }
    return FavoritaModel(
      id: json['id'] as String,
      tipoRefeicao: tipo,
      nome: json['nome'] as String,
      payloadJsonb: (json['payload_jsonb'] as Map).cast<String, dynamic>(),
      criadoEm: DateTime.parse(json['criado_em'] as String),
    );
  }
}
