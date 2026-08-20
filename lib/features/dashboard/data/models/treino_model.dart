/// Um treino (`atividades_fisicas_treinos`) — RELATÓRIO 20260811_0002,
/// decisão do fundador. Espelho tipado das colunas fixas da tabela, mesmo
/// espírito de [HealthPayloadModel] pra `metricas_saude_diarias`: sem mapa
/// genérico solto pela UI.
class TreinoModel {
  final String id;
  final String tipoAtividadeCodigo;

  /// Nome amigável de `tipos_atividades_fisicas.nome_exibicao` — vem do
  /// embed do PostgREST (`select('*, tipos_atividades_fisicas(nome_exibicao)')`
  /// em [TreinosHistoricoRepository]), não de uma segunda consulta. `null`
  /// só seria possível se o dicionário não tivesse a modalidade (não
  /// deveria acontecer — a FK em `atividades_fisicas_treinos.
  /// tipo_atividade_codigo` já impede gravar um código que não exista lá).
  final String? tipoAtividadeNomeExibicao;
  final DateTime inicioAtividade;
  final DateTime fimAtividade;
  final double? energiaQueimadaKcal;
  final double? distanciaMetros;
  final int? passosTotais;
  final int? fcMedia;
  final int? fcMaxima;
  final int? fcMinima;
  // RELATÓRIO 20260819_0020, pedido do fundador — m/s (HealthDataType.SPEED,
  // filtrada ao intervalo do treino em HealthSyncService._processarTreinos,
  // mesmo tratamento de fcMedia/fcMaxima).
  final double? velocidadeMediaMs;
  final double? velocidadeMaximaMs;
  final String? origem;

  const TreinoModel({
    required this.id,
    required this.tipoAtividadeCodigo,
    required this.inicioAtividade,
    required this.fimAtividade,
    this.tipoAtividadeNomeExibicao,
    this.energiaQueimadaKcal,
    this.distanciaMetros,
    this.passosTotais,
    this.fcMedia,
    this.fcMaxima,
    this.fcMinima,
    this.velocidadeMediaMs,
    this.velocidadeMaximaMs,
    this.origem,
  });

  Duration get duracao => fimAtividade.difference(inicioAtividade);

  /// Nome pra exibir na tela — o amigável quando o embed trouxe, senão o
  /// código cru (ex.: "RUNNING") como fallback, nunca uma tela em branco.
  String get nomeExibicao => tipoAtividadeNomeExibicao ?? tipoAtividadeCodigo;

  factory TreinoModel.fromJson(Map<String, dynamic> json) {
    final tipoAtividade = json['tipos_atividades_fisicas'];
    return TreinoModel(
      id: json['id'] as String,
      tipoAtividadeCodigo: json['tipo_atividade_codigo'] as String,
      tipoAtividadeNomeExibicao: tipoAtividade is Map
          ? tipoAtividade['nome_exibicao'] as String?
          : null,
      inicioAtividade: DateTime.parse(json['inicio_atividade'] as String),
      fimAtividade: DateTime.parse(json['fim_atividade'] as String),
      energiaQueimadaKcal: (json['energia_queimada_kcal'] as num?)?.toDouble(),
      distanciaMetros: (json['distancia_metros'] as num?)?.toDouble(),
      passosTotais: (json['passos_totais'] as num?)?.toInt(),
      fcMedia: (json['fc_media'] as num?)?.toInt(),
      fcMaxima: (json['fc_maxima'] as num?)?.toInt(),
      fcMinima: (json['fc_minima'] as num?)?.toInt(),
      velocidadeMediaMs: (json['velocidade_media_ms'] as num?)?.toDouble(),
      velocidadeMaximaMs: (json['velocidade_maxima_ms'] as num?)?.toDouble(),
      origem: json['origem'] as String?,
    );
  }
}
