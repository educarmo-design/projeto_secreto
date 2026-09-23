import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo de uma meta (`objetivos_alimentares`) — só os campos que a tela
/// de Bem-Estar precisa mostrar, mesmo espírito enxuto de `TreinoModel`.
class MetaResumo {
  final int caloriasAlvo;
  final int? proteinaG;
  final int? carboG;
  final int? gorduraG;
  final DateTime dataCriacao;

  /// `'ativo'` ou `'historico'` — `null` quando a query de origem não
  /// selecionou esta coluna (ex.: [MetaBemEstarRepository.buscarMinhaUltimaMetaPropria]/
  /// `buscarMetaAtivaDoProfissional`, que já filtram por status na própria
  /// query e não precisam expor o valor). Só preenchido por
  /// [MetaBemEstarRepository.buscarHistoricoMetas] (RELATÓRIO 20260915_0003),
  /// pra Tela de Metas rotular cada item da lista.
  final String? statusVigencia;

  const MetaResumo({
    required this.caloriasAlvo,
    required this.dataCriacao,
    this.proteinaG,
    this.carboG,
    this.gorduraG,
    this.statusVigencia,
  });

  factory MetaResumo.fromJson(Map<String, dynamic> json) {
    return MetaResumo(
      caloriasAlvo: json['calorias_alvo'] as int,
      proteinaG: json['proteina_g'] as int?,
      carboG: json['carbo_g'] as int?,
      gorduraG: json['gordura_g'] as int?,
      dataCriacao: DateTime.parse(json['data_criacao'] as String),
      statusVigencia: json['status_vigencia'] as String?,
    );
  }
}

/// Resultado da RPC `gerar_sugestao_meta` (RELATÓRIO 20260915_0002/0003) —
/// TDEE médio da semana + detalhe por dia, exibidos na Tela de Resultado
/// do Motor Metabólico logo após o envio da Anamnese. Só os campos que a
/// tela precisa mostrar (TMB informativo + a "média" pedida pelo
/// fundador + o detalhe por dia) — o `motor_resultado`/`avisos` brutos da
/// RPC ficam disponíveis em [avisos] sem precisar expor o jsonb inteiro.
class SugestaoMetaResultado {
  final double? tmb;
  final double? tdeeMedio;

  /// TDEE de cada dia (0=domingo..6=sábado) — `null` no valor quando o
  /// motor não teve dado suficiente naquele dia (mesma convenção do resto
  /// do app: ausência de dado não é erro).
  final Map<int, double?> tdeePorDia;
  final String formulaUsada;
  final List<String> avisos;

  const SugestaoMetaResultado({
    required this.tmb,
    required this.tdeeMedio,
    required this.tdeePorDia,
    required this.formulaUsada,
    required this.avisos,
  });

  factory SugestaoMetaResultado.fromJson(Map<String, dynamic> json) {
    final motor = json['motor_resultado'] as Map<String, dynamic>? ?? const {};
    final detalhe = json['detalhe_por_dia'] as Map<String, dynamic>? ?? const {};

    return SugestaoMetaResultado(
      tmb: (motor['tmb'] as num?)?.toDouble(),
      tdeeMedio: (json['tdee_medio'] as num?)?.toDouble(),
      tdeePorDia: {
        for (var dia = 0; dia <= 6; dia++)
          dia: ((detalhe['$dia'] as Map<String, dynamic>?)?['tdee'] as num?)?.toDouble(),
      },
      formulaUsada: json['formula_usada'] as String? ?? 'dados_insuficientes',
      avisos: (json['avisos'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// Bloco 15/Regra 25 (RELATÓRIO 20260919_0001) — score de qualidade dos
/// dados usados pelo motor (`'alta'|'media'|'baixa'`) + os motivos
/// (códigos estáveis, traduzidos pela tela via i18n).
class QualidadeMotorResultado {
  final String score;
  final List<String> motivos;

  const QualidadeMotorResultado({required this.score, required this.motivos});

  factory QualidadeMotorResultado.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const QualidadeMotorResultado(score: 'baixa', motivos: []);
    return QualidadeMotorResultado(
      score: json['score'] as String? ?? 'baixa',
      motivos: (json['motivos'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// "Motor Metabólico — Definição da Meta Energética V1.0" (RELATÓRIO
/// 20260919_0001, tabela multicritério em 20260920_0001) — a
/// RECOMENDAÇÃO DO SISTEMA (nunca a meta salva — ME-005/ME-006): TDEE puro
/// pra manutenção, ou TDEE − déficit multicritério parametrizado
/// (DEFICIT-002-multicriterio-v1) pra perda de peso/redução de gordura.
/// `null` quando o motor não tem objetivo/TDEE suficiente pra recomendar.
class EnergiaRecomendacaoResultado {
  final String estrategia;
  final double? deficitPercentual;
  final String? deficitVersao;
  final double recomendacaoMediaDiaria;

  const EnergiaRecomendacaoResultado({
    required this.estrategia,
    required this.deficitPercentual,
    required this.deficitVersao,
    required this.recomendacaoMediaDiaria,
  });

  factory EnergiaRecomendacaoResultado.fromJson(Map<String, dynamic> json) {
    return EnergiaRecomendacaoResultado(
      estrategia: json['estrategia'] as String? ?? '—',
      deficitPercentual: (json['deficit_percentual'] as num?)?.toDouble(),
      deficitVersao: json['deficit_versao'] as String?,
      recomendacaoMediaDiaria: (json['recomendacao_media_diaria'] as num).toDouble(),
    );
  }
}

/// Um protocolo de macronutrientes (MACRO-001/002/003 — "Motor Metabólico
/// — Protocolos de Macronutrientes V1.0"). `parametros` fica cru (o Dart
/// nunca reinventa os percentuais/g-por-kg — usa exatamente os que o
/// backend devolveu, versionados) pra recalcular os gramas na tela quando
/// o usuário mudar o campo Calorias com o protocolo já selecionado.
class MacroProtocoloResultado {
  final String versao;
  final bool disponivel;
  final Map<String, dynamic> parametros;
  final double? proteinaG;
  final double? carboidratoG;
  final double? gorduraG;
  final bool validacaoSomaOk;

  const MacroProtocoloResultado({
    required this.versao,
    required this.disponivel,
    required this.parametros,
    required this.proteinaG,
    required this.carboidratoG,
    required this.gorduraG,
    required this.validacaoSomaOk,
  });

  factory MacroProtocoloResultado.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const MacroProtocoloResultado(
        versao: '—',
        disponivel: false,
        parametros: {},
        proteinaG: null,
        carboidratoG: null,
        gorduraG: null,
        validacaoSomaOk: false,
      );
    }
    return MacroProtocoloResultado(
      versao: json['versao'] as String? ?? '—',
      disponivel: json['disponivel'] as bool? ?? true,
      parametros: (json['parametros'] as Map<String, dynamic>?) ?? const {},
      proteinaG: (json['proteina_g'] as num?)?.toDouble(),
      carboidratoG: (json['carboidrato_g'] as num?)?.toDouble(),
      gorduraG: (json['gordura_g'] as num?)?.toDouble(),
      validacaoSomaOk: json['validacao_soma_ok'] as bool? ?? false,
    );
  }
}

/// `macros_recomendados` inteiro — `null` quando o motor não tem energia-alvo
/// (nenhuma recomendação energética) ou peso suficiente pra calcular.
class MacrosRecomendadosResultado {
  final double energiaAlvo;
  final MacroProtocoloResultado macro001;
  final MacroProtocoloResultado macro002;
  final MacroProtocoloResultado macro003;

  const MacrosRecomendadosResultado({
    required this.energiaAlvo,
    required this.macro001,
    required this.macro002,
    required this.macro003,
  });

  factory MacrosRecomendadosResultado.fromJson(Map<String, dynamic> json) {
    return MacrosRecomendadosResultado(
      energiaAlvo: (json['energia_alvo'] as num).toDouble(),
      macro001: MacroProtocoloResultado.fromJson(json['macro_001'] as Map<String, dynamic>?),
      macro002: MacroProtocoloResultado.fromJson(json['macro_002'] as Map<String, dynamic>?),
      macro003: MacroProtocoloResultado.fromJson(json['macro_003'] as Map<String, dynamic>?),
    );
  }
}

/// RELATÓRIO 20260917 — resultado de `calcular_motor_metabolico_v1`
/// (RELATÓRIO 20260916_0001, docs/motor_metabolico.txt): Motor Metabólico
/// Centralizado V1, função PURA (nunca escreve nada — ME-005/ME-006).
/// Ampliado em 20260919_0001/20260920_0001 com [qualidade],
/// [energiaRecomendacao] e [macrosRecomendados] — todos informativos,
/// nunca a meta salva.
class MotorMetabolicoV1Resultado {
  final double? tmb;
  final double? tdeeMedio;
  final String formulaCodigo;
  final String estrategiaTdee;
  final List<String> avisos;
  final QualidadeMotorResultado qualidade;
  final EnergiaRecomendacaoResultado? energiaRecomendacao;
  final MacrosRecomendadosResultado? macrosRecomendados;
  final double? pesoKg;
  final double? massaMagraKg;

  const MotorMetabolicoV1Resultado({
    required this.tmb,
    required this.tdeeMedio,
    required this.formulaCodigo,
    required this.estrategiaTdee,
    required this.avisos,
    required this.qualidade,
    required this.energiaRecomendacao,
    required this.macrosRecomendados,
    required this.pesoKg,
    required this.massaMagraKg,
  });

  factory MotorMetabolicoV1Resultado.fromJson(Map<String, dynamic> json) {
    final formula = json['formula_tmb'] as Map<String, dynamic>? ?? const {};
    final insumos = json['insumos'] as Map<String, dynamic>? ?? const {};
    final energiaRecomendacaoJson = json['energia_recomendacao'] as Map<String, dynamic>?;
    final macrosJson = json['macros_recomendados'] as Map<String, dynamic>?;
    return MotorMetabolicoV1Resultado(
      tmb: (json['tmb'] as num?)?.toDouble(),
      tdeeMedio: (json['tdee_medio'] as num?)?.toDouble(),
      formulaCodigo: formula['codigo'] as String? ?? '—',
      estrategiaTdee: json['estrategia_tdee'] as String? ?? '—',
      avisos: (json['avisos'] as List?)?.cast<String>() ?? const [],
      qualidade: QualidadeMotorResultado.fromJson(json['qualidade'] as Map<String, dynamic>?),
      energiaRecomendacao:
          energiaRecomendacaoJson == null ? null : EnergiaRecomendacaoResultado.fromJson(energiaRecomendacaoJson),
      macrosRecomendados: macrosJson == null ? null : MacrosRecomendadosResultado.fromJson(macrosJson),
      pesoKg: (insumos['peso_kg'] as num?)?.toDouble(),
      massaMagraKg: (insumos['massa_magra_kg'] as num?)?.toDouble(),
    );
  }
}

/// Sinaliza qual das 3 travas de `validar_e_salvar_meta` (N08) recusou o
/// salvamento — a tela usa isso pra escolher o texto certo do modal.
enum MotivoBloqueioN08 { travaClinica, prioridadeProfissional, carenciaMensal, outro }

MotivoBloqueioN08 _motivoDoErro(String mensagem) {
  if (mensagem.contains('N08_TRAVA_CLINICA')) return MotivoBloqueioN08.travaClinica;
  if (mensagem.contains('N08_PRIORIDADE_PROFISSIONAL')) return MotivoBloqueioN08.prioridadeProfissional;
  if (mensagem.contains('N08_CARENCIA_MENSAL')) return MotivoBloqueioN08.carenciaMensal;
  return MotivoBloqueioN08.outro;
}

/// Lançada quando `validar_e_salvar_meta` recusa a gravação — encapsula o
/// [PostgrestException] cru num tipo que a tela sabe tratar sem precisar
/// fazer `.contains()` ela mesma.
class MetaBloqueadaException implements Exception {
  MetaBloqueadaException(this.motivo, this.mensagemOriginal);

  final MotivoBloqueioN08 motivo;
  final String mensagemOriginal;
}

/// N11 (RELATÓRIO 20260812_0010) — Meta de Bem-Estar self-service. Toda
/// gravação passa por `validar_e_salvar_meta` (Motor de Exceções N08,
/// `p_is_profissional: false`) — nunca um `.insert()` direto (a tabela
/// `objetivos_alimentares` não tem policy de escrita para `authenticated`).
///
/// Esta tela sempre opera em `tipo_dia = 'PADRAO'` — diferente da
/// Prescrição Profissional (`PrescricaoView.tsx`, N10), que pode ter várias
/// metas por tipo de dia, "Bem-Estar" no app é UMA meta geral só.
class MetaBemEstarRepository {
  MetaBemEstarRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const _tipoDia = 'PADRAO';

  /// RELATÓRIO 20260922_0002 (Item 5, Widget de Validade) — `data_validade`
  /// da anamnese vigente (`status_vigencia = 'ativo'`), pra
  /// [AnamneseValidadeBanner]/o bloqueio de 40 dias desta própria tela.
  /// Duplica uma consulta simples que também existe em `AnamneseRepository`
  /// de propósito — mesmo espírito de baixo acoplamento já usado no resto
  /// do app (evitar uma 2ª dependência de repositório só por um SELECT).
  /// `null` = sem anamnese vigente OU sem `data_validade` calculada.
  Future<DateTime?> buscarDataValidadeAnamnese() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('anamneses')
        .select('data_validade')
        .eq('usuario_id', usuarioId)
        .eq('status_vigencia', 'ativo')
        .maybeSingle();

    final bruto = linha?['data_validade'] as String?;
    return bruto == null ? null : DateTime.parse(bruto);
  }

  /// A meta AUTO-criada (`profissional_id is null`) mais recente do
  /// usuário, de QUALQUER status_vigencia — a carência de 30 dias no banco
  /// (`validar_e_salvar_meta`) conta a partir de `data_criacao`, não do
  /// status (uma meta própria pode virar "historico" cedo se um
  /// profissional prescrever por cima, mas ainda assim consumiu a cota do
  /// mês). `null` = nunca criou uma, ou ninguém logado.
  Future<MetaResumo?> buscarMinhaUltimaMetaPropria() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('objetivos_alimentares')
        .select('calorias_alvo, proteina_g, carbo_g, gordura_g, data_criacao')
        .eq('usuario_id', usuarioId)
        .eq('tipo_dia', _tipoDia)
        .isFilter('profissional_id', null)
        .order('data_criacao', ascending: false)
        .limit(1)
        .maybeSingle();

    return linha == null ? null : MetaResumo.fromJson(linha);
  }

  /// A meta ATIVA prescrita por um profissional, se existir — Restrição
  /// B2B (RELATÓRIO 20260812_0010): se isto não for `null`, o atleta não
  /// pode salvar uma meta própria (o banco recusa via
  /// `N08_PRIORIDADE_PROFISSIONAL`); a tela usa isto pra avisar ANTES de
  /// deixar o usuário preencher o formulário à toa.
  Future<MetaResumo?> buscarMetaAtivaDoProfissional() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('objetivos_alimentares')
        .select('calorias_alvo, proteina_g, carbo_g, gordura_g, data_criacao')
        .eq('usuario_id', usuarioId)
        .eq('tipo_dia', _tipoDia)
        .eq('status_vigencia', 'ativo')
        .not('profissional_id', 'is', null)
        .maybeSingle();

    return linha == null ? null : MetaResumo.fromJson(linha);
  }

  /// RELATÓRIO 20260820 — meta EFETIVAMENTE ativa agora, pro card
  /// "consumo × meta": mesma resolução de precedência que
  /// [MetaBemEstarPage._carregar] já faz (profissional sempre vence se
  /// tiver uma ativa; senão a última meta própria) — extraída aqui pra não
  /// duplicar a regra numa segunda tela. `null` = usuário nunca definiu
  /// meta nenhuma (nem próprio nem profissional) — o card mostra "defina
  /// sua meta", não erro.
  Future<MetaResumo?> buscarMetaEfetivaAtual() async {
    final metaProfissional = await buscarMetaAtivaDoProfissional();
    if (metaProfissional != null) return metaProfissional;
    return buscarMinhaUltimaMetaPropria();
  }

  /// Todas as metas AUTO-criadas do usuário (`profissional_id is null`),
  /// de QUALQUER status_vigencia, mais recentes primeiro — "Histórico de
  /// Metas" da Tela de Metas (RELATÓRIO 20260915_0003, item 4). Lista
  /// vazia (não erro) quando o usuário nunca criou nenhuma.
  Future<List<MetaResumo>> buscarHistoricoMetas() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return const [];

    final linhas = await _supabase
        .from('objetivos_alimentares')
        .select('calorias_alvo, proteina_g, carbo_g, gordura_g, data_criacao, status_vigencia')
        .eq('usuario_id', usuarioId)
        .eq('tipo_dia', _tipoDia)
        .isFilter('profissional_id', null)
        .order('data_criacao', ascending: false);

    return (linhas as List).cast<Map<String, dynamic>>().map(MetaResumo.fromJson).toList();
  }

  /// Roda o Motor Metabólico e PERSISTE a sugestão (RPC `gerar_sugestao_meta`,
  /// RELATÓRIO 20260915_0002/0003) — diferente de [buscarSugestaoCalorias]
  /// (só lê `gasto_sedentario` ao vivo, sem gravar nada, usada pelo botão
  /// "Usar sugestão" do formulário de meta): esta é chamada pela Tela de
  /// Resultado do Motor Metabólico logo após salvar a Anamnese, e grava um
  /// rastro em `sugestao_meta`. NUNCA escreve em `objetivos_alimentares` —
  /// a RPC em si já garante isso (ver o comentário da migration). Lança
  /// [StateError] se ninguém estiver logado.
  Future<SugestaoMetaResultado> gerarSugestaoMeta() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    final resultado = await _supabase.rpc(
      'gerar_sugestao_meta',
      params: {'p_usuario_id': usuarioId},
    ) as Map<String, dynamic>;

    return SugestaoMetaResultado.fromJson(resultado);
  }

  /// RELATÓRIO 20260917 (item 2 — "Tela Final: Separação de Cálculo vs
  /// Meta") — chama o Motor Metabólico Centralizado V1
  /// (`calcular_motor_metabolico_v1`, RELATÓRIO 20260916_0001), a RPC que
  /// a Tela de Resultado da Anamnese passa a usar em vez de
  /// `gerar_sugestao_meta` (mantida no banco por compatibilidade, mas sem
  /// nenhuma tela chamando-a a partir desta tarefa). Função PURA no banco —
  /// nunca escreve em `objetivos_alimentares`/`sugestao_meta`/`anamneses`
  /// (ME-005/ME-006); só calcula e devolve. Lança [StateError] se ninguém
  /// estiver logado.
  Future<MotorMetabolicoV1Resultado> calcularMotorMetabolicoV1() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    final resultado = await _supabase.rpc(
      'calcular_motor_metabolico_v1',
      params: {'p_usuario_id': usuarioId},
    ) as Map<String, dynamic>;

    return MotorMetabolicoV1Resultado.fromJson(resultado);
  }

  /// Sugestão de calorias "baseada no TMB" — usa `gasto_sedentario`
  /// (TMB × 1.2) do Motor N07, não a TMB crua (que é só o gasto em
  /// repouso absoluto, baixo demais pra sugerir como meta diária). `null`
  /// se o motor não tiver dado o suficiente pra calcular (perfil
  /// incompleto) — a tela trata como "sem sugestão", não erro.
  Future<double?> buscarSugestaoCalorias() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final resultado = await _supabase.rpc(
      'calcular_motor_metabolico',
      params: {'p_usuario_id': usuarioId},
    ) as Map<String, dynamic>;

    return (resultado['gasto_sedentario'] as num?)?.toDouble();
  }

  /// Grava via o Motor de Exceções (N08). Lança [StateError] se ninguém
  /// estiver logado, ou [MetaBloqueadaException] se a RPC recusar (trava
  /// clínica, prioridade profissional, ou carência mensal) — o
  /// [PostgrestException] original vai dentro, mas a tela nunca precisa
  /// fazer `.contains()` nela mesma.
  Future<void> salvarMeta({
    required int caloriasAlvo,
    int? proteinaG,
    int? carboG,
    int? gorduraG,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    try {
      await _supabase.rpc('validar_e_salvar_meta', params: {
        'p_payload': {
          'tipo_dia': _tipoDia,
          'calorias_alvo': caloriasAlvo,
          if (proteinaG != null) 'proteina_g': proteinaG,
          if (carboG != null) 'carbo_g': carboG,
          if (gorduraG != null) 'gordura_g': gorduraG,
        },
        'p_is_profissional': false,
      });
    } on PostgrestException catch (erro) {
      throw MetaBloqueadaException(_motivoDoErro(erro.message), erro.message);
    }
  }
}
