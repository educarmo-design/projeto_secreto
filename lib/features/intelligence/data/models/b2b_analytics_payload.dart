import 'package:flutter/foundation.dart';

import '../../../dashboard/data/models/health_payload_model.dart';
import '../services/health_score_engine.dart';

/// Um ponto da curva de evolução do HealthScore — usado pelo Painel Web
/// B2B, que (diferente do app do usuário final) pode legitimamente exibir
/// a nota bruta em contexto profissional/clínico.
@immutable
class HealthScorePonto {
  final DateTime data;
  final int pontuacao;

  const HealthScorePonto({required this.data, required this.pontuacao});

  factory HealthScorePonto.fromResult(HealthScoreResult resultado) =>
      HealthScorePonto(data: resultado.calculadoEm, pontuacao: resultado.pontuacao);

  Map<String, dynamic> toJson() => {
        'data': _dataOnlyIso(data),
        'pontuacao': pontuacao,
      };
}

/// Um ponto da curva bruta de parâmetros clínicos — espelho reduzido de
/// `metricas_saude_diarias`: só os sinais vitais relevantes para
/// seguradoras/médicos, nunca origem/dispositivo ou qualquer coluna que não
/// seja um valor clínico em si.
@immutable
class ParametroClinicoPonto {
  final DateTime data;
  final int? fcRepouso;
  final double? pesoKg;
  final int? minutosSono;
  final int? pressaoSistolica;
  final int? pressaoDiastolica;
  final double? glicoseJejum;
  final double? saturacaoOxigenio;

  const ParametroClinicoPonto({
    required this.data,
    this.fcRepouso,
    this.pesoKg,
    this.minutosSono,
    this.pressaoSistolica,
    this.pressaoDiastolica,
    this.glicoseJejum,
    this.saturacaoOxigenio,
  });

  factory ParametroClinicoPonto.fromHealthPayload(HealthPayloadModel dia) =>
      ParametroClinicoPonto(
        data: dia.dateFrom,
        fcRepouso: dia.fcRepouso,
        pesoKg: dia.pesoKg,
        minutosSono: dia.minutosSono,
        pressaoSistolica: dia.pressaoSistolica,
        pressaoDiastolica: dia.pressaoDiastolica,
        glicoseJejum: dia.glicoseJejum,
        saturacaoOxigenio: dia.saturacaoOxigenio,
      );

  Map<String, dynamic> toJson() => {
        'data': _dataOnlyIso(data),
        if (fcRepouso != null) 'fc_repouso': fcRepouso,
        if (pesoKg != null) 'peso_kg': pesoKg,
        if (minutosSono != null) 'minutos_sono': minutosSono,
        if (pressaoSistolica != null) 'pressao_sistolica': pressaoSistolica,
        if (pressaoDiastolica != null) 'pressao_diastolica': pressaoDiastolica,
        if (glicoseJejum != null) 'glicose_jejum': glicoseJejum,
        if (saturacaoOxigenio != null) 'saturacao_oxigenio': saturacaoOxigenio,
      };
}

/// Contrato de exportação B2B (ONDA 3 — Painel Web das Seguradoras/Médicos).
///
/// Regra de Blindagem LGPD, aplicada estruturalmente, não por filtragem em
/// runtime: repare que não existe (e nunca deve existir) um campo `nome`,
/// `telefone`, `email`, `nickname` ou `cep` bruto nesta classe. A única via
/// de construção é [B2BAnalyticsPayload.anonimizar], cuja lista de
/// parâmetros também não aceita PII — um mantenedor futuro não consegue
/// "vazar" um dado nominal para este payload sem alterar este arquivo, o
/// que fica visível em qualquer revisão de código. Isso é uma garantia bem
/// mais forte do que "remover campos sensíveis antes de enviar".
@immutable
class B2BAnalyticsPayload {
  /// O UUID que o Supabase Auth já gera — nunca um identificador
  /// legível/nominal. É a mesma chave usada nas tabelas clínicas via RLS
  /// `auth.uid()`, então já é, por construção, anônima do ponto de vista de
  /// qualquer sistema fora deste projeto.
  final String usuarioIdAnonimo;

  /// Faixa etária macro (ex.: `"25-34"`) — nunca a data de nascimento
  /// exata, que combinada com região já seria suficiente para
  /// reidentificação em populações pequenas.
  final String faixaEtaria;

  /// Bucket regional (`geo_ranking_id`, ex.: `"BR-SP-SAO_PAULO"`) —
  /// reaproveita o mesmo dado já anonimizado usado nas Ligas Geográficas do
  /// cadastro, nunca o CEP/Postal Code bruto.
  final String regiao;

  final List<HealthScorePonto> curvaHealthScore;
  final List<ParametroClinicoPonto> curvaParametrosClinicos;
  final DateTime geradoEm;

  const B2BAnalyticsPayload._({
    required this.usuarioIdAnonimo,
    required this.faixaEtaria,
    required this.regiao,
    required this.curvaHealthScore,
    required this.curvaParametrosClinicos,
    required this.geradoEm,
  });

  /// Único construtor público — força toda montagem do payload a passar
  /// pela blindagem de anonimização abaixo (bucketização de idade, uso do
  /// bucket regional já anônimo). [dataNascimento] e [geoRankingId] entram
  /// como matéria-prima e são imediatamente reduzidos a
  /// [faixaEtaria]/[regiao]; nenhum dos dois valores brutos fica retido na
  /// instância resultante.
  factory B2BAnalyticsPayload.anonimizar({
    required String usuarioIdAnonimo,
    required DateTime? dataNascimento,
    required String? geoRankingId,
    required List<HealthScoreResult> historicoScores,
    required List<HealthPayloadModel> historicoClinico,
  }) {
    return B2BAnalyticsPayload._(
      usuarioIdAnonimo: usuarioIdAnonimo,
      faixaEtaria: _calcularFaixaEtaria(dataNascimento),
      regiao: (geoRankingId == null || geoRankingId.isEmpty)
          ? 'desconhecida'
          : geoRankingId,
      curvaHealthScore:
          historicoScores.map(HealthScorePonto.fromResult).toList(),
      curvaParametrosClinicos: historicoClinico
          .map(ParametroClinicoPonto.fromHealthPayload)
          .toList(),
      geradoEm: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'usuario_id_anonimo': usuarioIdAnonimo,
        'faixa_etaria': faixaEtaria,
        'regiao': regiao,
        'curva_health_score': curvaHealthScore.map((p) => p.toJson()).toList(),
        'curva_parametros_clinicos':
            curvaParametrosClinicos.map((p) => p.toJson()).toList(),
        'gerado_em': geradoEm.toIso8601String(),
      };

  static String _calcularFaixaEtaria(DateTime? dataNascimento) {
    if (dataNascimento == null) return 'desconhecida';

    final hoje = DateTime.now();
    var idade = hoje.year - dataNascimento.year;
    final aindaNaoFezAniversarioEsteAno =
        hoje.month < dataNascimento.month ||
            (hoje.month == dataNascimento.month && hoje.day < dataNascimento.day);
    if (aindaNaoFezAniversarioEsteAno) idade -= 1;

    if (idade < 18) return '<18';
    if (idade < 25) return '18-24';
    if (idade < 35) return '25-34';
    if (idade < 45) return '35-44';
    if (idade < 55) return '45-54';
    if (idade < 65) return '55-64';
    return '65+';
  }
}

String _dataOnlyIso(DateTime data) => data.toIso8601String().split('T').first;
