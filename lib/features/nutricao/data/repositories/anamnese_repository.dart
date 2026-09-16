import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/anamnese_models.dart';

/// N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada,
/// self-service. Todo preenchimento é um INSERT novo em `anamneses`
/// (nunca UPDATE) — o trigger `anamneses_trg_versionar`
/// (`20260811240000_n09_anamnese_versionada_e_gaps_n06.sql`) vira o
/// `status_vigencia` da anamnese anterior do usuário para `historico`
/// automaticamente antes do INSERT completar. Esta classe nunca precisa
/// saber disso — só insere com o padrão da coluna (`ativo`).
class AnamneseRepository {
  AnamneseRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Catálogo de comorbidades (`problemas_saude`) — leitura pública pra
  /// `authenticated`, curadoria só por Admin (AdminProblemasSaude.tsx).
  Future<List<CatalogoItem>> buscarProblemasSaude() async {
    final linhas = await _supabase.from('problemas_saude').select('id, nome').order('nome');

    return (linhas as List)
        .cast<Map<String, dynamic>>()
        .map((json) => CatalogoItem.fromJson(json))
        .toList();
  }

  /// Catálogo de alergias (`alergias`) — mesma tabela usada por
  /// `AdminAlergias.tsx`. `nome_exibicao` é a coluna certa (não `nome`,
  /// diferente de `problemas_saude`).
  Future<List<CatalogoItem>> buscarAlergias() async {
    final linhas = await _supabase.from('alergias').select('id, nome_exibicao').order('nome_exibicao');

    return (linhas as List)
        .cast<Map<String, dynamic>>()
        .map((json) => CatalogoItem.fromJson(json, campoNome: 'nome_exibicao'))
        .toList();
  }

  /// Dicionário de modalidades (`tipos_atividades_fisicas`) — mesma tabela
  /// usada por `atividades_fisicas_treinos`/`AdminAtividadesFisicas.tsx`.
  Future<List<TipoAtividadeItem>> buscarTiposAtividades() async {
    final linhas = await _supabase
        .from('tipos_atividades_fisicas')
        .select('id, nome_exibicao')
        .order('nome_exibicao');

    return (linhas as List)
        .cast<Map<String, dynamic>>()
        .map(TipoAtividadeItem.fromJson)
        .toList();
  }

  /// A anamnese vigente do usuário logado (`status_vigencia = 'ativo'`),
  /// com as relações N:N já resolvidas — usada para pré-preencher a tela
  /// quando o usuário volta pra atualizar. `null` tanto pra "ninguém
  /// logado" quanto pra "nunca preencheu uma anamnese ainda" — os dois
  /// casos são "formulário em branco, pronto pra preencher" pra UI, não
  /// erro (mesma convenção de [PerfilUsuarioRepository]).
  ///
  /// RELATÓRIO 20260915_0003 — lê a Rotina por Dia da Semana de
  /// `anamneses_atividades_dias` (não mais de `anamneses_atividades`, que
  /// esta tela para de gravar a partir desta tarefa — ver
  /// [salvarAnamnese]).
  Future<AnamneseAtiva?> buscarAnamneseAtiva() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final anamnese = await _supabase
        .from('anamneses')
        .select('id, objetivo_codigo, data_preenchimento')
        .eq('usuario_id', usuarioId)
        .eq('status_vigencia', 'ativo')
        .maybeSingle();

    if (anamnese == null) return null;
    final anamneseId = anamnese['id'] as String;

    final results = await Future.wait([
      _supabase.from('anamneses_problemas_saude').select('problema_saude_id').eq('anamnese_id', anamneseId),
      _supabase.from('anamneses_alergias').select('alergia_id').eq('anamnese_id', anamneseId),
      // Embed pra trazer o nome de exibição junto, sem N+1 — mesmo padrão
      // de TreinosHistoricoRepository.buscarUltimosTreinos.
      _supabase
          .from('anamneses_atividades_dias')
          .select('atividade_id, dia_semana, minutos, tipos_atividades_fisicas(nome_exibicao)')
          .eq('anamnese_id', anamneseId),
    ]);

    final problemasSaude = (results[0] as List).cast<Map<String, dynamic>>();
    final alergias = (results[1] as List).cast<Map<String, dynamic>>();
    final atividades = (results[2] as List).cast<Map<String, dynamic>>();

    return AnamneseAtiva(
      objetivoCodigo: anamnese['objetivo_codigo'] as String,
      dataPreenchimento: DateTime.parse(anamnese['data_preenchimento'] as String),
      problemasSaudeIds: problemasSaude.map((linha) => linha['problema_saude_id'] as String).toList(),
      alergiaIds: alergias.map((linha) => linha['alergia_id'] as String).toList(),
      atividades: atividades.map((linha) {
        final tipoAtividade = linha['tipos_atividades_fisicas'];
        return AtividadeSelecionada(
          atividadeId: linha['atividade_id'] as int,
          nomeExibicao: tipoAtividade is Map
              ? (tipoAtividade['nome_exibicao'] as String? ?? '')
              : '',
          minutos: linha['minutos'] as int,
          diaSemana: linha['dia_semana'] as int,
        );
      }).toList(),
    );
  }

  /// Altura/sexo (de `perfis_usuarios`) + último peso conhecido (de
  /// `metricas_saude_diarias`, mesma leitura de
  /// `PerfilUsuarioRepository.buscarUltimoPesoKg`) — os mesmos 3 insumos
  /// físicos que o Motor Metabólico N07 consulta. Duas queries pequenas
  /// duplicadas aqui em vez de importar `PerfilUsuarioRepository`
  /// (feature `dashboard`): mesmo espírito de baixo acoplamento entre
  /// features já usado em outros pontos do app (ex.: `CORS_HEADERS`
  /// duplicado entre Edge Functions) — 2 selects de 1 linha não
  /// justificam uma dependência cross-feature.
  Future<DadosFisicosAtuais> buscarDadosFisicosAtuais() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return const DadosFisicosAtuais();

    final resultados = await Future.wait([
      _supabase.from('perfis_usuarios').select('altura_cm, sexo_biologico').eq('id', usuarioId).maybeSingle(),
      _supabase
          .from('metricas_saude_diarias')
          .select('peso_kg')
          .eq('usuario_id_anonimo', usuarioId)
          .not('peso_kg', 'is', null)
          .order('data_referencia', ascending: false)
          .limit(1)
          .maybeSingle(),
    ]);

    final perfil = resultados[0];
    final ultimoPeso = resultados[1];

    return DadosFisicosAtuais(
      alturaCm: (perfil?['altura_cm'] as num?)?.toDouble(),
      sexoBiologico: perfil?['sexo_biologico'] as String?,
      pesoKg: (ultimoPeso?['peso_kg'] as num?)?.toDouble(),
    );
  }

  /// Grava um preenchimento NOVO da anamnese: upsert de altura/sexo em
  /// `perfis_usuarios` + upsert do peso de HOJE em `metricas_saude_diarias`
  /// (RELATÓRIO 20260915_0003 — item 1 da tarefa, "garantir a captura de
  /// altura, sexo e peso"; `calcular_motor_metabolico` só lê peso desta
  /// tabela, nunca de `perfis_usuarios.peso_kg`, ver a migration
  /// `20260915120000`) + 1 INSERT em `anamneses` + batch insert nas
  /// tabelas N:N (`anamneses_alergias`, `anamneses_problemas_saude`,
  /// `anamneses_atividades_dias`). Um `.insert()` por tabela com a lista
  /// inteira de linhas — diferente do bug histórico de "upsert destrutivo"
  /// (`_enviarLinhas`, RELATÓRIO 20260811_0001), que era um problema de
  /// `.upsert()` batch com colunas DIFERENTES por linha fazendo o
  /// PostgREST nulificar o que faltava; aqui é `.insert()` puro (nunca
  /// upsert) e toda linha de uma mesma chamada tem exatamente as mesmas
  /// colunas — o risco daquele bug não existe nesta gravação.
  ///
  /// A partir desta tarefa, PARA de gravar em `anamneses_atividades` (a
  /// tabela uniforme antiga) — grava só em `anamneses_atividades_dias`
  /// (RELATÓRIO 20260915_0002), que já é o que `gerar_sugestao_meta`
  /// prioriza quando tem dado. `anamneses_atividades` fica órfã de novas
  /// gravações do app a partir de agora (permanece intocada no banco por
  /// compatibilidade retroativa das anamneses antigas, ver a migration).
  ///
  /// Lança [StateError] se ninguém estiver logado. Uma falha em qualquer
  /// chamada depois do INSERT principal deixa a anamnese "órfã" de parte
  /// das relações (sem transação client-side possível via PostgREST) —
  /// aceitável nesta v1 self-service porque o usuário sempre pode
  /// preencher de novo (o trigger versiona a tentativa anterior
  /// automaticamente); registrado como limitação conhecida, não corrigido
  /// nesta tarefa.
  Future<void> salvarAnamnese({
    required String objetivoCodigo,
    required double alturaCm,
    required String sexoBiologico,
    required double pesoKg,
    required List<String> problemasSaudeIds,
    required List<String> alergiaIds,
    required List<AtividadeSelecionada> atividades,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    await _supabase
        .from('perfis_usuarios')
        .upsert({'id': usuarioId, 'altura_cm': alturaCm, 'sexo_biologico': sexoBiologico}, onConflict: 'id');

    // Não sobrescreve um peso já sincronizado hoje por outra fonte (ex.:
    // wearable) — o auto-relato da anamnese só preenche o dia quando
    // ainda não há leitura nenhuma, mesmo espírito de "wearable nunca é
    // sobrescrito por fonte menos confiável" já aplicado à telemetria de
    // calorias (RELATÓRIO 20260813_0018/0019).
    final hoje = DateTime.now();
    final dataReferencia =
        '${hoje.year.toString().padLeft(4, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
    final pesoHojeJaExiste = await _supabase
        .from('metricas_saude_diarias')
        .select('peso_kg')
        .eq('usuario_id_anonimo', usuarioId)
        .eq('data_referencia', dataReferencia)
        .not('peso_kg', 'is', null)
        .maybeSingle();

    if (pesoHojeJaExiste == null) {
      await _supabase.from('metricas_saude_diarias').upsert({
        'usuario_id_anonimo': usuarioId,
        'data_referencia': dataReferencia,
        'peso_kg': pesoKg,
        'origem': 'manual',
      }, onConflict: 'usuario_id_anonimo,data_referencia');
    }

    final anamneseInserida = await _supabase
        .from('anamneses')
        .insert({'usuario_id': usuarioId, 'objetivo_codigo': objetivoCodigo})
        .select('id')
        .single();
    final anamneseId = anamneseInserida['id'] as String;

    if (problemasSaudeIds.isNotEmpty) {
      await _supabase.from('anamneses_problemas_saude').insert([
        for (final problemaSaudeId in problemasSaudeIds)
          {'anamnese_id': anamneseId, 'problema_saude_id': problemaSaudeId},
      ]);
    }

    if (alergiaIds.isNotEmpty) {
      await _supabase.from('anamneses_alergias').insert([
        for (final alergiaId in alergiaIds) {'anamnese_id': anamneseId, 'alergia_id': alergiaId},
      ]);
    }

    if (atividades.isNotEmpty) {
      await _supabase.from('anamneses_atividades_dias').insert([
        for (final atividade in atividades)
          {
            'anamnese_id': anamneseId,
            'atividade_id': atividade.atividadeId,
            'dia_semana': atividade.diaSemana,
            'minutos': atividade.minutos,
          },
      ]);
    }
  }
}
