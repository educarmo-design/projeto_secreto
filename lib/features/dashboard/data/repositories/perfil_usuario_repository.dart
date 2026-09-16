import 'package:supabase_flutter/supabase_flutter.dart';

/// Espelha o ENUM Postgres `sexo_biologico_enum`
/// (`20260812100000_n07_motor_metabolico_sexo_biologico_telemetria_manual.sql`,
/// RELATÓRIO 20260812_0008) — insumo do Motor Metabólico N07
/// (Mifflin-St Jeor precisa dele quando não há massa magra medida).
enum SexoBiologico {
  masculino('M'),
  feminino('F');

  const SexoBiologico(this.codigo);

  /// Valor gravado no banco — exatamente o rótulo do ENUM Postgres.
  final String codigo;

  static SexoBiologico? fromCodigo(String? codigo) {
    if (codigo == null) return null;
    return SexoBiologico.values.firstWhere(
      (valor) => valor.codigo == codigo,
      orElse: () => throw ArgumentError('Código de sexo_biologico desconhecido: $codigo'),
    );
  }
}

/// Repositório do "dado físico" do usuário — hoje `data_nascimento`/
/// `sexo_biologico`/`tamanho_copo_ml` (todos em `perfis_usuarios`).
///
/// RELATÓRIO 20260916_0001 (SSOT, docs/motor_metabolico.txt) — `altura_cm`
/// e `peso_kg` PARARAM de existir em `perfis_usuarios` (colunas removidas):
/// "o peso não deve ser mantido como atributo permanente do perfil" / "a
/// altura deverá ser confirmada em toda nova Anamnese". Este repositório não
/// tem mais `buscarAlturaCm`/`atualizarAlturaCm` — quem precisa da altura
/// oficial do usuário agora lê [buscarAlturaCmDaUltimaAnamnese] (read-only:
/// a ÚNICA forma de mudar a altura oficial é preencher uma anamnese nova,
/// em `lib/features/nutricao/`).
///
/// `.select(...)` sempre com colunas explícitas, nunca `.select()` (todas as
/// colunas): `perfis_usuarios.nome/telefone/email` são PII cifradas em
/// repouso (D2, `20260730160000_d2_pii_criptografia_repouso.sql`) e este
/// repositório não tem nenhum motivo pra puxá-las.
///
/// RELATÓRIO 20260812_0011 — BUG CORRIGIDO: as gravações usavam `.update()`,
/// que precisa de uma linha PRÉ-EXISTENTE em `perfis_usuarios` pra afetar
/// algo. Um usuário logado cuja linha nunca chegou a ser criada (ex.:
/// conta provisionada fora do fluxo normal de cadastro do app — achado
/// real ao investigar `atleta1000@teste.com`, que tinha `auth.users` e
/// `metricas_saude_diarias` cheios de dados do Garmin, mas ZERO linha em
/// `perfis_usuarios`) fazia esse `.update()` rodar, devolver sucesso
/// (Postgrest não trata "0 linhas afetadas" como erro) e não gravar
/// NADA — um `try/catch` nunca dispararia porque nenhuma exceção
/// acontecia. Trocado por `.upsert()`: cria a linha se não existir, edita
/// se existir. Seguro porque a RLS `perfis_usuarios_insert_own`
/// (`20260714100000_add_approval_workflow.sql`) só exige `auth.uid() =
/// id` mais os defaults seguros de `eh_profissional`/`status_aprovacao`/
/// `is_admin` — nenhum dos quais este repositório tenta sobrescrever.
class PerfilUsuarioRepository {
  PerfilUsuarioRepository({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// RELATÓRIO 20260916_0001 — altura OFICIAL do usuário: a da última
  /// anamnese com o campo preenchido (mesma resolução usada por
  /// `calcular_motor_metabolico_v1` no banco — duplicada aqui em vez de
  /// importar `AnamneseRepository`/feature `nutricao`, mesmo espírito de
  /// baixo acoplamento entre features já usado em outros pontos do app).
  /// `null` tanto para "ninguém logado" quanto para "nunca preencheu uma
  /// anamnese com altura ainda" — a tela trata os dois casos como "sem
  /// dado", não como erro.
  Future<double?> buscarAlturaCmDaUltimaAnamnese() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('anamneses')
        .select('altura_cm')
        .eq('usuario_id', usuarioId)
        .not('altura_cm', 'is', null)
        .order('data_preenchimento', ascending: false)
        .limit(1)
        .maybeSingle();

    return (linha?['altura_cm'] as num?)?.toDouble();
  }

  /// N03 (RELATÓRIO 20260811_0005, ajuste do fundador) — `null` tanto para
  /// "ninguém logado" quanto para "coluna vazia", mesma convenção de
  /// [buscarAlturaCmDaUltimaAnamnese].
  Future<DateTime?> buscarDataNascimento() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('perfis_usuarios')
        .select('data_nascimento')
        .eq('id', usuarioId)
        .maybeSingle();

    final valor = linha?['data_nascimento'] as String?;
    return valor == null ? null : DateTime.parse(valor);
  }

  /// N03 — a barreira REAL de maioridade é a CHECK constraint
  /// `perfis_usuarios_maioridade` no banco
  /// (`20260811190000_n03_trava_maioridade.sql`); a validação em
  /// [PerfilUsuarioPage] é só UX. Um UPDATE com menor de 18 anos é
  /// recusado pelo Postgres mesmo que, por algum motivo, a validação
  /// client-side seja contornada — o erro do Postgres sobe como
  /// [PostgrestException], não tratado aqui de propósito (a tela decide
  /// como mostrar).
  Future<void> atualizarDataNascimento(DateTime dataNascimento) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    await _supabase.from('perfis_usuarios').upsert({
      'id': usuarioId,
      'data_nascimento': _dataOnly(dataNascimento),
    }, onConflict: 'id');
  }

  static String _dataOnly(DateTime data) => data.toIso8601String().split('T').first;

  /// N07 (RELATÓRIO 20260812_0008) — `null` tanto para "ninguém logado"
  /// quanto para "coluna vazia", mesma convenção de [buscarAlturaCmDaUltimaAnamnese].
  Future<SexoBiologico?> buscarSexoBiologico() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('perfis_usuarios')
        .select('sexo_biologico')
        .eq('id', usuarioId)
        .maybeSingle();

    return SexoBiologico.fromCodigo(linha?['sexo_biologico'] as String?);
  }

  /// Mesma regra de segurança de [atualizarDataNascimento] — RLS
  /// `perfis_usuarios_update_own` já garante que só o dono da linha grava.
  Future<void> atualizarSexoBiologico(SexoBiologico sexoBiologico) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    await _supabase.from('perfis_usuarios').upsert({
      'id': usuarioId,
      'sexo_biologico': sexoBiologico.codigo,
    }, onConflict: 'id');
  }

  /// RELATÓRIO 20260812_0011 — última leitura de `peso_kg` em
  /// `metricas_saude_diarias` (vem do wearable, nunca digitado nesta
  /// tela), pra alimentar o cálculo de IMC exibido ao lado do campo de
  /// altura. `null` tanto para "ninguém logado" quanto para "nenhum peso
  /// sincronizado ainda" — mesma convenção do resto da classe.
  Future<PesoRecente?> buscarUltimoPesoKg() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('metricas_saude_diarias')
        .select('peso_kg, data_referencia')
        .eq('usuario_id_anonimo', usuarioId)
        .not('peso_kg', 'is', null)
        .order('data_referencia', ascending: false)
        .limit(1)
        .maybeSingle();

    final pesoKg = (linha?['peso_kg'] as num?)?.toDouble();
    final dataReferencia = linha?['data_referencia'] as String?;
    if (pesoKg == null || dataReferencia == null) return null;

    return PesoRecente(pesoKg: pesoKg, dataReferencia: DateTime.parse(dataReferencia));
  }

  /// N16 (RELATÓRIO 20260819) — tamanho do copo (ml) usado pelo botão
  /// "+1 copo" da tela de hidratação. `200` (o padrão da coluna no banco,
  /// `20260819160000_n16_hidratacao_tamanho_copo.sql`) tanto para "ninguém
  /// logado" quanto para "linha de perfil ainda não existe" — diferente do
  /// resto da classe (que devolve `null` pra "campo em branco"), aqui o
  /// valor em branco JÁ TEM um padrão de produto definido (200 ml,
  /// Documento Mestre Parte V1.I), então nunca faz sentido a tela mostrar
  /// um campo vazio.
  Future<int> buscarTamanhoCopoMl() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return 200;

    final linha = await _supabase
        .from('perfis_usuarios')
        .select('tamanho_copo_ml')
        .eq('id', usuarioId)
        .maybeSingle();

    return (linha?['tamanho_copo_ml'] as num?)?.toInt() ?? 200;
  }

  /// Mesma regra de segurança de [atualizarDataNascimento] — RLS
  /// `perfis_usuarios_update_own` já garante que só o dono da linha grava.
  /// Faixa plausível (50–1000 ml) é validada em
  /// `RegistroHidratacaoPage`, não aqui.
  Future<void> atualizarTamanhoCopoMl(int tamanhoCopoMl) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    await _supabase.from('perfis_usuarios').upsert(
      {'id': usuarioId, 'tamanho_copo_ml': tamanhoCopoMl},
      onConflict: 'id',
    );
  }
}

/// Última leitura de peso conhecida + o dia a que ela se refere — usada só
/// para o IMC exibido em [PerfilUsuarioPage] mostrar "baseado no peso de
/// dd/mm" em vez de um número solto sem contexto.
class PesoRecente {
  const PesoRecente({required this.pesoKg, required this.dataReferencia});

  final double pesoKg;
  final DateTime dataReferencia;
}
