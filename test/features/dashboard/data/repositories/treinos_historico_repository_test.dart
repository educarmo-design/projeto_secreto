import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/features/dashboard/data/repositories/treinos_historico_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Encadeamento falso de
/// `.select('*, tipos_atividades_fisicas(nome_exibicao)').eq('usuario_id', ...)
/// .order('inicio_atividade', ascending: false).limit(...)` — RELATÓRIO
/// 20260811_0002.
class _FakeTreinosFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeTreinosFilterBuilder(this._linhas);
  final List<Map<String, dynamic>> _linhas;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) => this;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) => this as PostgrestTransformBuilder<List<Map<String, dynamic>>>;

  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> limit(
    int count, {
    String? referencedTable,
  }) => this as PostgrestTransformBuilder<List<Map<String, dynamic>>>;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) => Future.value(_linhas).then(onValue, onError: onError);
}

const _usuarioId = 'user-123';
const _usuarioAutenticado = User(
  id: _usuarioId,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  late _MockSupabaseClient supabase;
  late _MockGoTrueClient auth;
  late _MockSupabaseQueryBuilder treinosBuilder;
  late TreinosHistoricoRepository repository;

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    treinosBuilder = _MockSupabaseQueryBuilder();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('atividades_fisicas_treinos'))
        .thenAnswer((_) => treinosBuilder);

    repository = TreinosHistoricoRepository(supabaseClient: supabase);
  });

  test('devolve os treinos com o nome de exibição vindo do embed', () async {
    when(() => treinosBuilder.select(any())).thenAnswer(
      (_) => _FakeTreinosFilterBuilder([
        {
          'id': 'treino-1',
          'tipo_atividade_codigo': 'RUNNING',
          'tipos_atividades_fisicas': {'nome_exibicao': 'Corrida'},
          'inicio_atividade': '2026-07-08T07:00:00.000Z',
          'fim_atividade': '2026-07-08T07:45:00.000Z',
          'energia_queimada_kcal': 450,
          'distancia_metros': 8000,
          'fc_media': 155,
          'fc_maxima': 172,
          'fc_minima': 130,
        },
      ]),
    );

    final treinos = await repository.buscarUltimosTreinos();

    expect(treinos, hasLength(1));
    expect(treinos.single.nomeExibicao, 'Corrida');
    expect(treinos.single.fcMedia, 155);
    expect(treinos.single.distanciaMetros, 8000);
  });

  test('devolve lista vazia sem consultar o Supabase quando ninguém está logado', () async {
    when(() => auth.currentUser).thenReturn(null);

    final treinos = await repository.buscarUltimosTreinos();

    expect(treinos, isEmpty);
    verifyNever(() => supabase.from('atividades_fisicas_treinos'));
  });
}
