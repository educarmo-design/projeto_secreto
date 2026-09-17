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

  /// Bloco 6 (docs/motor_metabolico.txt) — "leve" | "moderada" | "alta".
  /// Obrigatório por pedido explícito do fundador (RELATÓRIO 20260918_0001)
  /// — mesmo CHECK constraint em `anamneses_atividades_dias.intensidade`.
  final String intensidade;

  const AtividadeSelecionada({
    required this.atividadeId,
    required this.nomeExibicao,
    required this.minutos,
    required this.diaSemana,
    required this.intensidade,
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
      other.diaSemana == diaSemana &&
      other.intensidade == intensidade;

  @override
  int get hashCode => Object.hash(atividadeId, nomeExibicao, minutos, diaSemana, intensidade);
}

/// Bloco 9/10/11 (docs/motor_metabolico.txt) — item repetível de
/// Medicamento/Suplemento/Exame. Os 3 blocos compartilham a mesma forma
/// "lista de cartões com nome + poucos campos opcionais", então usam o
/// MESMO modelo genérico em vez de 3 classes quase idênticas — `campos`
/// guarda só o que aquele bloco específico preenche (chaves diferentes por
/// bloco, ver [AnamneseRepository.salvarAnamnese]).
class ItemRepetivel {
  final String nome;
  final Map<String, String> campos;

  const ItemRepetivel({required this.nome, this.campos = const {}});

  @override
  bool operator ==(Object other) =>
      other is ItemRepetivel &&
      other.nome == nome &&
      _mapasIguais(other.campos, campos);

  static bool _mapasIguais(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final chave in a.keys) {
      if (a[chave] != b[chave]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(nome, Object.hashAllUnordered(campos.entries.map((e) => Object.hash(e.key, e.value))));
}

/// Bloco 4 (docs/motor_metabolico.txt) — resultado da RPC
/// `anamnese_historico_peso`, só leitura, nunca editável pela tela ("esses
/// dados são históricos e não devem ser confundidos com o peso oficial da
/// nova Anamnese").
class HistoricoPeso {
  final double? pesoAtual;
  final double? pesoAnterior;
  final double? peso30Dias;
  final double? peso3Meses;
  final double? peso6Meses;
  final double? peso12Meses;
  final double? maiorPeso;
  final double? menorPeso;
  final double? variacaoPercentual;

  const HistoricoPeso({
    this.pesoAtual,
    this.pesoAnterior,
    this.peso30Dias,
    this.peso3Meses,
    this.peso6Meses,
    this.peso12Meses,
    this.maiorPeso,
    this.menorPeso,
    this.variacaoPercentual,
  });

  factory HistoricoPeso.fromJson(Map<String, dynamic> json) {
    double? numOu(String chave) => (json[chave] as num?)?.toDouble();
    return HistoricoPeso(
      pesoAtual: numOu('peso_atual'),
      pesoAnterior: numOu('peso_anterior'),
      peso30Dias: numOu('peso_30_dias'),
      peso3Meses: numOu('peso_3_meses'),
      peso6Meses: numOu('peso_6_meses'),
      peso12Meses: numOu('peso_12_meses'),
      maiorPeso: numOu('maior_peso'),
      menorPeso: numOu('menor_peso'),
      variacaoPercentual: numOu('variacao_percentual'),
    );
  }

  bool get temAlgumDado => pesoAtual != null || pesoAnterior != null;
}

/// Todos os campos novos da Anamnese (RELATÓRIO 20260918_0001, compliance
/// total com docs/motor_metabolico.txt Blocos 1-16) que não existiam antes
/// desta tarefa — agrupados num objeto só pra não estourar a assinatura de
/// [AnamneseRepository.salvarAnamnese] com 30+ parâmetros nomeados soltos.
/// Todo campo é opcional (`null`/lista vazia = não preenchido) — nenhum
/// bloco condicional é obrigatório para todo mundo (Seção 15/9, "adaptativa").
class DadosComplementaresAnamnese {
  // Bloco 1 — Contexto da avaliação
  final String? motivoAvaliacao;
  final String? motivoAvaliacaoOutro;

  // Bloco 2 — Objetivos
  final String? objetivoOutro;
  final List<String> objetivosSecundarios;
  final double? metaPesoDesejadoKg;
  final double? metaPercentualGorduraDesejado;
  final double? metaMassaDesejadaKg;
  final DateTime? metaPrazo;
  final String? metaOutroIndicador;

  // Bloco 3 — Antropometria (composição corporal)
  final double? percentualGordura;
  final double? massaGordaKg;
  final double? massaMagraKg;
  final double? massaMuscularKg;
  final double? circunferenciaCinturaCm;
  final double? circunferenciaAbdominalCm;
  final String? metodoAvaliacaoComposicao;
  final String? fonteComposicaoCorporal;

  // Bloco 4 — Histórico de peso (pergunta, não o histórico em si)
  final String? houveAlteracaoPesoNaoPlanejada;

  // Bloco 5 — Alimentação
  final int? numeroRefeicoesDia;
  final String? horariosRefeicoesHabituais;
  final String? regularidadeAlimentar;
  final String? refeicoesForaDeCasa;
  final String? consumoUltraprocessados;
  final String? preferenciasAlimentares;
  final String? alimentosEvitados;
  final List<String> restricoesAlimentares;
  final List<String> intolerancias;
  final String? padraoAlimentarHabitual;

  // Seção 5 + Bloco 6 (atividade não estruturada)
  final String? rotinaDiaria;
  final String? atividadeOcupacional;

  // Bloco 7 — Sono
  final double? horasSonoMedias;
  final String? horarioDormirHabitual; // "HH:mm"
  final String? horarioAcordarHabitual; // "HH:mm"
  final String? qualidadeSonoPercebida;
  final int? despertaresNoturnos;
  final String? sonoObservacoes;

  // Bloco 8 — Condições de saúde
  final bool? possuiCondicaoSaude;

  // Bloco 12 — Blocos condicionais
  final Map<String, dynamic>? blocoIdoso;
  final Map<String, dynamic>? blocoAtleta;
  final Map<String, dynamic>? blocoRecomposicao;
  final Map<String, dynamic>? blocoDiabetes;
  final Map<String, dynamic>? blocoDoencaRenal;

  // Blocos 9/10/11 — Medicamentos, Suplementos, Exames
  final List<ItemRepetivel> medicamentos;
  final List<ItemRepetivel> suplementos;
  final List<ItemRepetivel> exames;

  const DadosComplementaresAnamnese({
    this.motivoAvaliacao,
    this.motivoAvaliacaoOutro,
    this.objetivoOutro,
    this.objetivosSecundarios = const [],
    this.metaPesoDesejadoKg,
    this.metaPercentualGorduraDesejado,
    this.metaMassaDesejadaKg,
    this.metaPrazo,
    this.metaOutroIndicador,
    this.percentualGordura,
    this.massaGordaKg,
    this.massaMagraKg,
    this.massaMuscularKg,
    this.circunferenciaCinturaCm,
    this.circunferenciaAbdominalCm,
    this.metodoAvaliacaoComposicao,
    this.fonteComposicaoCorporal,
    this.houveAlteracaoPesoNaoPlanejada,
    this.numeroRefeicoesDia,
    this.horariosRefeicoesHabituais,
    this.regularidadeAlimentar,
    this.refeicoesForaDeCasa,
    this.consumoUltraprocessados,
    this.preferenciasAlimentares,
    this.alimentosEvitados,
    this.restricoesAlimentares = const [],
    this.intolerancias = const [],
    this.padraoAlimentarHabitual,
    this.rotinaDiaria,
    this.atividadeOcupacional,
    this.horasSonoMedias,
    this.horarioDormirHabitual,
    this.horarioAcordarHabitual,
    this.qualidadeSonoPercebida,
    this.despertaresNoturnos,
    this.sonoObservacoes,
    this.possuiCondicaoSaude,
    this.blocoIdoso,
    this.blocoAtleta,
    this.blocoRecomposicao,
    this.blocoDiabetes,
    this.blocoDoencaRenal,
    this.medicamentos = const [],
    this.suplementos = const [],
    this.exames = const [],
  });
}

/// Seção 11 (docs/motor_metabolico.txt) — "Confirme seus dados": tudo que
/// [AnamneseSelfServicePage] coletou, ainda não enviado, a caminho de
/// [ConfirmarAnamnesePage]. Só um carregador de dados entre as duas telas —
/// a gravação de verdade só acontece quando o usuário toca "Confirmar e
/// Enviar" lá (nunca antes).
class AnamneseRascunho {
  final String objetivoCodigo;
  final double alturaCm;
  final String sexoBiologico;
  final double pesoKg;
  final int? idade;
  final List<CatalogoItem> problemasSaudeSelecionados;
  final List<CatalogoItem> alergiasSelecionadas;
  final List<AtividadeSelecionada> atividades;
  final DadosComplementaresAnamnese complementares;

  const AnamneseRascunho({
    required this.objetivoCodigo,
    required this.alturaCm,
    required this.sexoBiologico,
    required this.pesoKg,
    required this.problemasSaudeSelecionados,
    required this.alergiasSelecionadas,
    required this.atividades,
    required this.complementares,
    this.idade,
  });
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

  /// RELATÓRIO 20260918_0001 — usada só pra decidir se o Bloco 12.1 (Idoso)
  /// deve ser oferecido (idade >= 60) e pra exibir "Idade" na tela de
  /// confirmação; nunca perguntada de novo aqui (já existe em
  /// `perfis_usuarios.data_nascimento`, coletada no cadastro).
  final DateTime? dataNascimento;

  const DadosFisicosAtuais({this.alturaCm, this.sexoBiologico, this.pesoKg, this.dataNascimento});

  int? get idade {
    final nascimento = dataNascimento;
    if (nascimento == null) return null;
    final hoje = DateTime.now();
    var anos = hoje.year - nascimento.year;
    if (hoje.month < nascimento.month || (hoje.month == nascimento.month && hoje.day < nascimento.day)) {
      anos--;
    }
    return anos;
  }
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
