// N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada,
// self-service. Modelos leves, espelho tipado das colunas fixas, mesmo
// espírito de `TreinoModel`/`HealthPayloadModel`: sem mapa genérico solto
// pela UI.

/// Um item de catálogo simples id/nome — reusado para `problemas_saude` e
/// `alergias` (que, apesar de ter `nome_exibicao` em vez de `nome` na
/// coluna, representa o mesmo conceito pra esta tela).
class CatalogoItem {
  final String id;
  final String nome;

  const CatalogoItem({required this.id, required this.nome});

  factory CatalogoItem.fromJson(Map<String, dynamic> json, {String campoNome = 'nome'}) {
    return CatalogoItem(id: json['id'] as String, nome: json[campoNome] as String);
  }
}

/// Uma modalidade de `tipos_atividades_fisicas` — `id` é `smallint` no
/// banco (int no Dart, sem perda: smallint cabe inteiro em int nativo).
class TipoAtividadeItem {
  final int id;
  final String nomeExibicao;

  const TipoAtividadeItem({required this.id, required this.nomeExibicao});

  factory TipoAtividadeItem.fromJson(Map<String, dynamic> json) {
    return TipoAtividadeItem(
      id: json['id'] as int,
      nomeExibicao: json['nome_exibicao'] as String,
    );
  }
}

/// Uma atividade escolhida na Rotina de Atividades da anamnese, já
/// amarrada a um dia da semana específico — grava em
/// `anamneses_atividades_dias` (RELATÓRIO 20260915_0002/20260915_0003),
/// não mais na `anamneses_atividades` uniforme antiga (ver o comentário de
/// [AnamneseRepository.salvarAnamnese]). `diaSemana` segue a convenção do
/// Postgres (`extract(dow from date)`): 0 = domingo, 6 = sábado — mesma da
/// coluna `anamneses_atividades_dias.dia_semana`. `nomeExibicao` vem junto
/// só para a UI não precisar re-consultar o catálogo pra mostrar a linha.
class AtividadeSelecionada {
  final int atividadeId;
  final String nomeExibicao;
  final int minutos;
  final int diaSemana;

  const AtividadeSelecionada({
    required this.atividadeId,
    required this.nomeExibicao,
    required this.minutos,
    required this.diaSemana,
  });

  /// Igualdade por valor — necessária para a comparação de "já adicionada"
  /// em [AnamneseSelfServicePage] (a MESMA atividade pode se repetir em
  /// dias diferentes, então a igualdade inclui `diaSemana`) e para
  /// `verify()` de testes comparar listas por conteúdo, não por identidade
  /// de instância.
  @override
  bool operator ==(Object other) =>
      other is AtividadeSelecionada &&
      other.atividadeId == atividadeId &&
      other.nomeExibicao == nomeExibicao &&
      other.minutos == minutos &&
      other.diaSemana == diaSemana;

  @override
  int get hashCode => Object.hash(atividadeId, nomeExibicao, minutos, diaSemana);
}

/// A anamnese `status_vigencia = 'ativo'` do usuário logado, já com as
/// relações N:N resolvidas — usada para PRÉ-PREENCHER a tela quando o
/// usuário volta para atualizar (o app nunca faz UPDATE nela; salvar de
/// novo cria uma linha nova e o trigger do banco versiona a antiga para
/// "historico" automaticamente, ver [AnamneseRepository.salvarAnamnese]).
/// `alturaCm`/`sexoBiologico`/`pesoKg` vêm de fora da tabela `anamneses`
/// (de `perfis_usuarios`/`metricas_saude_diarias`, ver
/// [AnamneseRepository.buscarDadosFisicosAtuais]) — agrupados aqui só para
/// a tela pré-preencher tudo de uma vez com um único objeto.
class AnamneseAtiva {
  final String objetivoCodigo;
  final DateTime dataPreenchimento;
  final List<String> problemasSaudeIds;
  final List<String> alergiaIds;
  final List<AtividadeSelecionada> atividades;

  const AnamneseAtiva({
    required this.objetivoCodigo,
    required this.dataPreenchimento,
    required this.problemasSaudeIds,
    required this.alergiaIds,
    required this.atividades,
  });
}

/// Altura/peso/sexo atuais do usuário — RELATÓRIO 20260916_0001 (SSOT):
/// altura/peso vêm da ÚLTIMA ANAMNESE com os dois campos preenchidos (não
/// mais de `perfis_usuarios`/`metricas_saude_diarias` diretamente), sexo
/// continua de `perfis_usuarios`. Usado só para PRÉ-PREENCHER a seção de
/// dados físicos da anamnese como sugestão editável — `null` em qualquer
/// campo é "ainda não informado", não erro.
class DadosFisicosAtuais {
  final double? alturaCm;
  final String? sexoBiologico;
  final double? pesoKg;

  const DadosFisicosAtuais({this.alturaCm, this.sexoBiologico, this.pesoKg});
}

/// RELATÓRIO 20260917 (item 1 — "Captura Inteligente") — leitura mais
/// recente de `metricas_saude_diarias` (balança/wearable), mostrada como
/// SUGESTÃO distinta do valor que vai compor o snapshot oficial da
/// Anamnese (docs/motor_metabolico.txt, Seção 1: "a leitura da balança
/// continua existindo como dado de origem, mas só passa a ser dado
/// antropométrico oficial após confirmação"). `null` em qualquer campo =
/// aquele dado não foi sincronizado ainda, não erro.
class SugestaoBalanca {
  final double? pesoKg;
  final double? percentualGordura;
  final DateTime? dataReferencia;

  const SugestaoBalanca({this.pesoKg, this.percentualGordura, this.dataReferencia});

  bool get temAlgumDado => pesoKg != null || percentualGordura != null;
}

/// RELATÓRIO 20260917 (item 3 — "Histórico de Avaliações") — uma linha do
/// histórico de anamneses do usuário (qualquer `status_vigencia`), mais
/// recente primeiro. Só os campos que a tela de histórico mostra — peso e
/// altura já vêm da própria anamnese (SSOT), sem precisar de outra tabela.
class AnamneseHistoricoItem {
  final String id;
  final DateTime dataPreenchimento;
  final String objetivoCodigo;
  final double? pesoKg;
  final double? alturaCm;
  final String statusVigencia;

  const AnamneseHistoricoItem({
    required this.id,
    required this.dataPreenchimento,
    required this.objetivoCodigo,
    required this.statusVigencia,
    this.pesoKg,
    this.alturaCm,
  });

  factory AnamneseHistoricoItem.fromJson(Map<String, dynamic> json) {
    return AnamneseHistoricoItem(
      id: json['id'] as String,
      dataPreenchimento: DateTime.parse(json['data_preenchimento'] as String),
      objetivoCodigo: json['objetivo_codigo'] as String,
      statusVigencia: json['status_vigencia'] as String,
      pesoKg: (json['peso_kg'] as num?)?.toDouble(),
      alturaCm: (json['altura_cm'] as num?)?.toDouble(),
    );
  }
}
