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
  /// com as 3 relações N:N já resolvidas — usada para pré-preencher a tela
  /// quando o usuário volta pra atualizar. `null` tanto pra "ninguém
  /// logado" quanto pra "nunca preencheu uma anamnese ainda" — os dois
  /// casos são "formulário em branco, pronto pra preencher" pra UI, não
  /// erro (mesma convenção de [PerfilUsuarioRepository]).
  Future<AnamneseAtiva?> buscarAnamneseAtiva() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final anamnese = await _supabase
        .from('anamneses')
        .select('id, objetivo_codigo')
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
          .from('anamneses_atividades')
          .select('atividade_id, minutos_diarios, tipos_atividades_fisicas(nome_exibicao)')
          .eq('anamnese_id', anamneseId),
    ]);

    final problemasSaude = (results[0] as List).cast<Map<String, dynamic>>();
    final alergias = (results[1] as List).cast<Map<String, dynamic>>();
    final atividades = (results[2] as List).cast<Map<String, dynamic>>();

    return AnamneseAtiva(
      objetivoCodigo: anamnese['objetivo_codigo'] as String,
      problemasSaudeIds: problemasSaude.map((linha) => linha['problema_saude_id'] as String).toList(),
      alergiaIds: alergias.map((linha) => linha['alergia_id'] as String).toList(),
      atividades: atividades.map((linha) {
        final tipoAtividade = linha['tipos_atividades_fisicas'];
        return AtividadeSelecionada(
          atividadeId: linha['atividade_id'] as int,
          nomeExibicao: tipoAtividade is Map
              ? (tipoAtividade['nome_exibicao'] as String? ?? '')
              : '',
          minutosDiarios: linha['minutos_diarios'] as int,
        );
      }).toList(),
    );
  }

  /// Grava um preenchimento NOVO da anamnese: 1 INSERT em `anamneses` +
  /// batch insert nas 3 tabelas N:N (`anamneses_alergias`,
  /// `anamneses_problemas_saude`, `anamneses_atividades`). Um `.insert()`
  /// por tabela com a lista inteira de linhas — diferente do bug histórico
  /// de "upsert destrutivo" (`_enviarLinhas`, RELATÓRIO 20260811_0001), que
  /// era um problema de `.upsert()` batch com colunas DIFERENTES por linha
  /// fazendo o PostgREST nulificar o que faltava; aqui é `.insert()` puro
  /// (nunca upsert) e toda linha de uma mesma chamada tem exatamente as
  /// mesmas colunas — o risco daquele bug não existe nesta gravação.
  ///
  /// Lança [StateError] se ninguém estiver logado. Uma falha em qualquer
  /// uma das 3 chamadas depois do INSERT principal deixa a anamnese
  /// "órfã" de parte das relações (sem transação client-side possível via
  /// PostgREST) — aceitável nesta v1 self-service porque o usuário sempre
  /// pode preencher de novo (o trigger versiona a tentativa anterior
  /// automaticamente); registrado como limitação conhecida, não corrigido
  /// nesta tarefa.
  Future<void> salvarAnamnese({
    required String objetivoCodigo,
    required List<String> problemasSaudeIds,
    required List<String> alergiaIds,
    required List<AtividadeSelecionada> atividades,
  }) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
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
      await _supabase.from('anamneses_atividades').insert([
        for (final atividade in atividades)
          {
            'anamnese_id': anamneseId,
            'atividade_id': atividade.atividadeId,
            'minutos_diarios': atividade.minutosDiarios,
          },
      ]);
    }
  }
}
