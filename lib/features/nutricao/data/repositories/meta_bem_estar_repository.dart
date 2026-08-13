import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo de uma meta (`objetivos_alimentares`) — só os campos que a tela
/// de Bem-Estar precisa mostrar, mesmo espírito enxuto de `TreinoModel`.
class MetaResumo {
  final int caloriasAlvo;
  final int? proteinaG;
  final int? carboG;
  final int? gorduraG;
  final DateTime dataCriacao;

  const MetaResumo({
    required this.caloriasAlvo,
    required this.dataCriacao,
    this.proteinaG,
    this.carboG,
    this.gorduraG,
  });

  factory MetaResumo.fromJson(Map<String, dynamic> json) {
    return MetaResumo(
      caloriasAlvo: json['calorias_alvo'] as int,
      proteinaG: json['proteina_g'] as int?,
      carboG: json['carbo_g'] as int?,
      gorduraG: json['gordura_g'] as int?,
      dataCriacao: DateTime.parse(json['data_criacao'] as String),
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
