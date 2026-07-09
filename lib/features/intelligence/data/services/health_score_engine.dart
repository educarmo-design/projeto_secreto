import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../dashboard/data/models/health_payload_model.dart';
import '../../../gamification/models/gamification_models.dart' show LeagueType;

/// ONDA 3 — Blindagem ANVISA (PRD Mestre §3/§5): [HealthScoreResult] is a
/// **gamification score**, never a clinical instrument. This file computes
/// it from real biomarkers, but nothing in its public surface exposes a
/// diagnosis, a risk level, or any wording a regulator could read as
/// software-as-a-medical-device (SaMD) framing.
///
/// The only vocabulary [HealthScoreResult] hands to the UI is game
/// vocabulary — [HealthScoreResult.faixaGamificada] reuses the exact same
/// [LeagueType] the competitive/gamification feature already shows for
/// leagues/streaks, and [HealthScoreResult.chaveTituloGamificado] resolves
/// to an i18n key under the `healthscore.*` namespace whose copy is always
/// "points, rules, goals" — never "score", "risco", or "diagnóstico". Do
/// not add a getter here that exposes [componenteEstabilidadeSinaisVitais]
/// or [componenteConsistenciaMetas] as a raw percentage to end-user UI —
/// they exist for the B2B export pipeline (see `B2BAnalyticsPayload`), a
/// separate, professional-facing audience that is explicitly in scope for
/// clinical-adjacent framing.
class HealthScoreEngine {
  HealthScoreEngine({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int pontuacaoMaxima = 1000;

  /// Regra de Cálculo Estrita (PRD Mestre): 40% consistência de
  /// metas/streak, 40% estabilidade dos sinais vitais.
  static const double _pesoConsistenciaMetas = 0.40;
  static const double _pesoEstabilidadeSinaisVitais = 0.40;

  /// Penalidade por anomalia: cada linha em `eventos_anomalias_saude` (a
  /// "Caixa Preta") custa 2 pontos percentuais, até um teto de 20 pontos
  /// percentuais (10 anomalias já atingem o teto). Interpretação
  /// deliberada de "-20% de penalidade por cada linha": lida literalmente
  /// (-20 pontos percentuais *por linha*) o score zeraria depois de 5
  /// anomalias em uma janela de 30 dias, o que descaracterizaria a métrica
  /// de "estabilidade" em algo binário/instável demais para gamificação. Se
  /// a leitura pretendida era mesmo -20pp por linha, ajuste
  /// [_penalidadePorAnomalia] para 0.20 e remova o teto.
  static const double _penalidadePorAnomalia = 0.02;
  static const double _tetoPenalidadeAnomalias = 0.20;

  static const int _diasHistoricoConsiderados = 30;

  /// Calcula o HealthScore do usuário autenticado atual.
  Future<HealthScoreResult?> calcularParaUsuarioAtual() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    return calcularParaUsuario(userId);
  }

  /// Calcula localmente (processa os dados já lidos, sem RPC) o HealthScore
  /// de [userId]. RLS já garante que uma sessão comum só consegue ler suas
  /// próprias linhas nas três tabelas envolvidas; um contexto com
  /// privilégio elevado (o futuro job noturno server-side do ONDA 3) pode
  /// chamar isto com qualquer [userId].
  ///
  /// "Processa localmente ou gera a query no banco": a implementação de
  /// referência é esta — busca as linhas tipadas e calcula em Dart. Para o
  /// lote noturno em escala (milhares de usuários de uma vez), a forma
  /// correta de evoluir isto é espelhar a mesma fórmula numa function SQL
  /// (`calcular_health_score(usuario_id uuid)`) rodando dentro do Postgres,
  /// evitando puxar o histórico bruto de cada usuário para um isolate Dart
  /// um por um — está fora do escopo deste arquivo (puramente Dart) criar
  /// essa migration, mas a assinatura pública aqui foi desenhada para que
  /// trocar a implementação por uma chamada RPC não mude nenhum chamador.
  Future<HealthScoreResult> calcularParaUsuario(String userId) async {
    final progresso = await _buscarProgressoGamificacao(userId);
    final historicoClinico = await buscarHistoricoClinico(userId);
    final totalAnomalias = await _contarAnomalias(userId);

    final consistenciaMetas = _calcularConsistenciaMetas(progresso);
    final estabilidadeSinaisVitais =
        _calcularEstabilidadeSinaisVitais(historicoClinico);
    final penalidadeAnomalias = _calcularPenalidadeAnomalias(totalAnomalias);

    final pontuacaoBase = (consistenciaMetas * _pesoConsistenciaMetas) +
        (estabilidadeSinaisVitais * _pesoEstabilidadeSinaisVitais);
    final pontuacaoNormalizada =
        (pontuacaoBase - penalidadeAnomalias).clamp(0.0, 1.0);

    return HealthScoreResult(
      pontuacao: (pontuacaoNormalizada * pontuacaoMaxima).round(),
      componenteConsistenciaMetas: consistenciaMetas,
      componenteEstabilidadeSinaisVitais: estabilidadeSinaisVitais,
      penalidadeAnomalias: penalidadeAnomalias,
      totalAnomalias: totalAnomalias,
      calculadoEm: DateTime.now(),
    );
  }

  /// Consistência de metas/streak Garmin: normaliza `ofensiva_atual`
  /// (`progresso_gamificacao`) pela janela de 30 dias — bater 30 dias
  /// seguidos já é o teto (1.0); streaks maiores não rendem mais pontos,
  /// o que evita um jogador "farmar" o HealthScore indefinidamente só
  /// alongando uma sequência já perfeita.
  double _calcularConsistenciaMetas(_ProgressoGamificacaoSnapshot? progresso) {
    if (progresso == null) return 0.0;
    return (progresso.ofensivaAtual / _diasHistoricoConsiderados).clamp(0.0, 1.0);
  }

  /// Estabilidade dos sinais vitais clínicos: para cada parâmetro fixo
  /// disponível (FC repouso, peso, sono, pressão sistólica, glicose),
  /// calcula o coeficiente de variação (desvio padrão / média) ao longo do
  /// histórico e inverte — quanto menor a variação dia a dia, mais estável
  /// (mais perto de 1.0). Um parâmetro nunca sincronizado simplesmente não
  /// entra na média, em vez de penalizar por um dado que o usuário nunca
  /// coletou.
  double _calcularEstabilidadeSinaisVitais(List<HealthPayloadModel> historico) {
    if (historico.length < 2) return 0.5; // dado insuficiente -> neutro

    final estabilidades = <double>[];
    void considerar(Iterable<double?> valores) {
      final estabilidade = _estabilidadeDeSerie(valores);
      if (estabilidade != null) estabilidades.add(estabilidade);
    }

    considerar(historico.map((d) => d.fcRepouso?.toDouble()));
    considerar(historico.map((d) => d.pesoKg));
    considerar(historico.map((d) => d.minutosSono?.toDouble()));
    considerar(historico.map((d) => d.pressaoSistolica?.toDouble()));
    considerar(historico.map((d) => d.glicoseJejum));

    if (estabilidades.isEmpty) return 0.5;
    return estabilidades.reduce((a, b) => a + b) / estabilidades.length;
  }

  /// `null` se houver menos de 2 valores válidos (sem variação calculável).
  /// Um coeficiente de variação de 50% ou mais já é tratado como
  /// instabilidade máxima (satura em 0.0) — limiar arbitrário, mas
  /// consistente entre parâmetros de escalas bem diferentes (bpm vs. kg).
  double? _estabilidadeDeSerie(Iterable<double?> valores) {
    final validos = valores.whereType<double>().toList();
    if (validos.length < 2) return null;

    final media = validos.reduce((a, b) => a + b) / validos.length;
    if (media == 0) return null;

    final variancia = validos
            .map((v) => (v - media) * (v - media))
            .reduce((a, b) => a + b) /
        validos.length;
    final desvioPadrao = math.sqrt(variancia);
    final coeficienteVariacao = (desvioPadrao / media).abs();

    return (1 - (coeficienteVariacao / 0.5)).clamp(0.0, 1.0);
  }

  double _calcularPenalidadeAnomalias(int totalAnomalias) {
    return (_penalidadePorAnomalia * totalAnomalias)
        .clamp(0.0, _tetoPenalidadeAnomalias);
  }

  Future<_ProgressoGamificacaoSnapshot?> _buscarProgressoGamificacao(
    String userId,
  ) async {
    try {
      final response = await _client
          .from('progresso_gamificacao')
          .select()
          .eq('usuario_id_anonimo', userId)
          .maybeSingle();
      if (response == null) return null;
      return _ProgressoGamificacaoSnapshot.fromJson(response);
    } on PostgrestException catch (e) {
      debugPrint('Erro ao buscar progresso_gamificacao: ${e.message}');
      return null;
    }
  }

  /// Público — reaproveitado por `B2BSyncRepository` para montar a curva
  /// bruta de parâmetros clínicos do payload B2B sem duplicar esta query.
  Future<List<HealthPayloadModel>> buscarHistoricoClinico(
    String userId, {
    int dias = _diasHistoricoConsiderados,
  }) async {
    final desde = DateTime.now().subtract(Duration(days: dias));
    try {
      final response = await _client
          .from('metricas_saude_diarias')
          .select()
          .eq('usuario_id_anonimo', userId)
          .gte('data_referencia', _dataOnlyIso(desde))
          .order('data_referencia');
      return (response as List)
          .cast<Map<String, dynamic>>()
          .map(HealthPayloadModel.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('Erro ao buscar metricas_saude_diarias: ${e.message}');
      return const [];
    }
  }

  Future<int> _contarAnomalias(String userId) async {
    final desde = DateTime.now().subtract(
      const Duration(days: _diasHistoricoConsiderados),
    );
    try {
      final response = await _client
          .from('eventos_anomalias_saude')
          .select('id')
          .eq('usuario_id_anonimo', userId)
          .gte('detectado_em', desde.toIso8601String());
      return (response as List).length;
    } on PostgrestException catch (e) {
      debugPrint('Erro ao contar eventos_anomalias_saude: ${e.message}');
      return 0;
    }
  }

  static String _dataOnlyIso(DateTime data) =>
      data.toIso8601String().split('T').first;
}

class _ProgressoGamificacaoSnapshot {
  final int ofensivaAtual;
  final int pontuacaoRanking;
  final String statusUsuario;

  const _ProgressoGamificacaoSnapshot({
    required this.ofensivaAtual,
    required this.pontuacaoRanking,
    required this.statusUsuario,
  });

  factory _ProgressoGamificacaoSnapshot.fromJson(Map<String, dynamic> json) {
    return _ProgressoGamificacaoSnapshot(
      ofensivaAtual: json['ofensiva_atual'] as int? ?? 0,
      pontuacaoRanking: json['pontuacao_ranking'] as int? ?? 0,
      statusUsuario: json['status_usuario'] as String? ?? 'ativo',
    );
  }
}

/// Resultado do cálculo — 0 a [HealthScoreEngine.pontuacaoMaxima]. Ver a
/// documentação de [HealthScoreEngine] para a regra de blindagem ANVISA:
/// [pontuacao]/[faixaGamificada]/[chaveTituloGamificado] são o único
/// vocabulário seguro para UI. Os campos de componente
/// ([componenteConsistenciaMetas], [componenteEstabilidadeSinaisVitais],
/// [penalidadeAnomalias]) existem para consumo B2B/profissional
/// (`B2BAnalyticsPayload`), não para telas do app do usuário final.
@immutable
class HealthScoreResult {
  final int pontuacao;
  final double componenteConsistenciaMetas;
  final double componenteEstabilidadeSinaisVitais;
  final double penalidadeAnomalias;
  final int totalAnomalias;
  final DateTime calculadoEm;

  const HealthScoreResult({
    required this.pontuacao,
    required this.componenteConsistenciaMetas,
    required this.componenteEstabilidadeSinaisVitais,
    required this.penalidadeAnomalias,
    required this.totalAnomalias,
    required this.calculadoEm,
  });

  /// Serialização usada só pela fila local de `B2BSyncRepository`
  /// (`FlutterSecureStorage`) — nunca enviada como está para o endpoint B2B,
  /// que só recebe o [HealthScorePonto] reduzido dentro de
  /// `B2BAnalyticsPayload`.
  Map<String, dynamic> toJson() => {
        'pontuacao': pontuacao,
        'componente_consistencia_metas': componenteConsistenciaMetas,
        'componente_estabilidade_sinais_vitais': componenteEstabilidadeSinaisVitais,
        'penalidade_anomalias': penalidadeAnomalias,
        'total_anomalias': totalAnomalias,
        'calculado_em': calculadoEm.toIso8601String(),
      };

  factory HealthScoreResult.fromJson(Map<String, dynamic> json) {
    return HealthScoreResult(
      pontuacao: json['pontuacao'] as int,
      componenteConsistenciaMetas:
          (json['componente_consistencia_metas'] as num).toDouble(),
      componenteEstabilidadeSinaisVitais:
          (json['componente_estabilidade_sinais_vitais'] as num).toDouble(),
      penalidadeAnomalias: (json['penalidade_anomalias'] as num).toDouble(),
      totalAnomalias: json['total_anomalias'] as int,
      calculadoEm: DateTime.parse(json['calculado_em'] as String),
    );
  }

  /// Faixa gamificada — reaproveita [LeagueType], o mesmo vocabulário de
  /// liga já usado pelo restante da gamificação, para que o HealthScore se
  /// pareça com progressão de jogo, nunca com um resultado de exame.
  LeagueType get faixaGamificada {
    if (pontuacao >= 900) return LeagueType.diamond;
    if (pontuacao >= 750) return LeagueType.platinum;
    if (pontuacao >= 550) return LeagueType.gold;
    if (pontuacao >= 350) return LeagueType.silver;
    return LeagueType.bronze;
  }

  /// Chave i18n (namespace `healthscore.*`) do título gamificado — a UI
  /// deve usar SOMENTE isto para rotular a nota ao usuário; nunca uma
  /// string montada a partir de [componenteEstabilidadeSinaisVitais] ou
  /// termos como "score clínico"/"risco"/"diagnóstico".
  String get chaveTituloGamificado {
    switch (faixaGamificada) {
      case LeagueType.diamond:
        return 'healthscore.titulo_diamante';
      case LeagueType.platinum:
        return 'healthscore.titulo_platina';
      case LeagueType.gold:
        return 'healthscore.titulo_ouro';
      case LeagueType.silver:
        return 'healthscore.titulo_prata';
      case LeagueType.bronze:
        return 'healthscore.titulo_bronze';
    }
  }
}
