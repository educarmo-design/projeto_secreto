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

/// Repositório mínimo do "dado físico" do usuário — hoje só `altura_cm`
/// (RELATÓRIO 20260810_0006, decisão do fundador: tela de Perfil em vez de
/// injetar o dado via SQL manual). Não usa [HealthPayloadModel]/a tabela
/// `metricas_saude_diarias`: `altura_cm` é um dado de PERFIL (muda raramente,
/// não é uma métrica diária), mora em `perfis_usuarios`
/// (`20260811130000_metricas_saude_fc_maxima_balanca.sql`) e é lido de lá por
/// `HealthSyncService._buscarAlturaMetros` para inferir o IMC.
///
/// `.select('altura_cm')`/`.upsert({'altura_cm': ...})` — nunca `.select()`
/// (todas as colunas): `perfis_usuarios.nome/telefone/email` são PII
/// cifradas em repouso (D2, `20260730160000_d2_pii_criptografia_repouso.sql`)
/// e esta tela não tem nenhum motivo pra puxá-las.
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

  /// `null` tanto para "ninguém logado" quanto para "coluna vazia" — a
  /// tela trata os dois casos como "campo em branco, pronto pra
  /// preencher", não como erro.
  Future<double?> buscarAlturaCm() async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) return null;

    final linha = await _supabase
        .from('perfis_usuarios')
        .select('altura_cm')
        .eq('id', usuarioId)
        .maybeSingle();

    return (linha?['altura_cm'] as num?)?.toDouble();
  }

  /// `.upsert()`, não `.update()` (RELATÓRIO 20260812_0011 — ver o
  /// comentário da classe): cria a linha em `perfis_usuarios` se ela ainda
  /// não existir, atualiza se já existir. RLS `perfis_usuarios_insert_own`/
  /// `_update_own` (`auth.uid() = id`) já garante que só o dono da linha
  /// grava — sem checagem extra de segurança no cliente. Lança
  /// [StateError] se ninguém estiver logado (não deveria ser alcançável: a
  /// tela só existe atrás do gate de autenticação do router).
  Future<void> atualizarAlturaCm(double alturaCm) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    await _supabase
        .from('perfis_usuarios')
        .upsert({'id': usuarioId, 'altura_cm': alturaCm}, onConflict: 'id');
  }

  /// N03 (RELATÓRIO 20260811_0005, ajuste do fundador) — `null` tanto para
  /// "ninguém logado" quanto para "coluna vazia", mesma convenção de
  /// [buscarAlturaCm].
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
  /// quanto para "coluna vazia", mesma convenção de [buscarAlturaCm].
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

  /// Mesma regra de segurança de [atualizarAlturaCm]/[atualizarDataNascimento]
  /// — RLS `perfis_usuarios_update_own` já garante que só o dono da linha
  /// grava.
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
}

/// Última leitura de peso conhecida + o dia a que ela se refere — usada só
/// para o IMC exibido em [PerfilUsuarioPage] mostrar "baseado no peso de
/// dd/mm" em vez de um número solto sem contexto.
class PesoRecente {
  const PesoRecente({required this.pesoKg, required this.dataReferencia});

  final double pesoKg;
  final DateTime dataReferencia;
}
