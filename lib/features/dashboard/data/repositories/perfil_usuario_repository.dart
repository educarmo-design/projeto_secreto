import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositório mínimo do "dado físico" do usuário — hoje só `altura_cm`
/// (RELATÓRIO 20260810_0006, decisão do fundador: tela de Perfil em vez de
/// injetar o dado via SQL manual). Não usa [HealthPayloadModel]/a tabela
/// `metricas_saude_diarias`: `altura_cm` é um dado de PERFIL (muda raramente,
/// não é uma métrica diária), mora em `perfis_usuarios`
/// (`20260811130000_metricas_saude_fc_maxima_balanca.sql`) e é lido de lá por
/// `HealthSyncService._buscarAlturaMetros` para inferir o IMC.
///
/// `.select('altura_cm')`/`.update({'altura_cm': ...})` — nunca `.select()`
/// (todas as colunas): `perfis_usuarios.nome/telefone/email` são PII
/// cifradas em repouso (D2, `20260730160000_d2_pii_criptografia_repouso.sql`)
/// e esta tela não tem nenhum motivo pra puxá-las.
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

  /// RLS `perfis_usuarios_update_own` (`auth.uid() = id`) já garante que só
  /// o dono da linha grava — basta filtrar por `id` como qualquer outro
  /// UPDATE, sem checagem extra de segurança no cliente. Lança
  /// [StateError] se ninguém estiver logado (não deveria ser alcançável: a
  /// tela só existe atrás do gate de autenticação do router).
  Future<void> atualizarAlturaCm(double alturaCm) async {
    final usuarioId = _supabase.auth.currentUser?.id;
    if (usuarioId == null) {
      throw StateError('Nenhum usuário logado.');
    }

    await _supabase
        .from('perfis_usuarios')
        .update({'altura_cm': alturaCm})
        .eq('id', usuarioId);
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

    await _supabase.from('perfis_usuarios').update({
      'data_nascimento': _dataOnly(dataNascimento),
    }).eq('id', usuarioId);
  }

  static String _dataOnly(DateTime data) => data.toIso8601String().split('T').first;
}
