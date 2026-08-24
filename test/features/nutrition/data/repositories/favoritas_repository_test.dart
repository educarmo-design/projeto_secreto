import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/features/nutrition/data/models/favorita_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/favoritas_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Mesmo padrão de `coleta_diaria_repository_test.dart`.
class _FakeInsertBuilder extends Fake implements PostgrestFilterBuilder<dynamic> {
  _FakeInsertBuilder(this._future);
  final Future<dynamic> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
}

class _FakeSelectListBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeSelectListBuilder(this._linhas);
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
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>> value) onValue, {
    Function? onError,
  }) => Future.value(_linhas).then(onValue, onError: onError);
}

class _FakeEqBuilder extends Fake implements PostgrestFilterBuilder<dynamic> {
  _FakeEqBuilder(this._future);
  final Future<dynamic> _future;

  @override
  PostgrestFilterBuilder<dynamic> eq(String column, Object value) => this;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
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
  late _MockSupabaseQueryBuilder favoritosBuilder;
  late FavoritasRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    favoritosBuilder = _MockSupabaseQueryBuilder();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('alimentos_favoritos')).thenAnswer((_) => favoritosBuilder);

    repository = FavoritasRepository(supabaseClient: supabase);
  });

  group('salvar', () {
    test('grava usuario_id/tipo_refeicao/nome/payload_jsonb', () async {
      when(() => favoritosBuilder.insert(any())).thenAnswer(
        (_) => _FakeInsertBuilder(Future.value(null)),
      );

      final resultado = await repository.salvar(
        nome: 'Meu almoço',
        tipoRefeicao: TipoRefeicao.almoco,
        payloadJsonb: {
          'itens': [],
          'totais': {'calorias': 500},
        },
      );

      expect(resultado.success, isTrue);
      verify(() => favoritosBuilder.insert({
            'usuario_id': _usuarioId,
            'tipo_refeicao': 'almoco',
            'nome': 'Meu almoço',
            'payload_jsonb': {
              'itens': [],
              'totais': {'calorias': 500},
            },
          })).called(1);
    });

    test('falha sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final resultado = await repository.salvar(
        nome: 'x',
        tipoRefeicao: TipoRefeicao.jantar,
        payloadJsonb: const {},
      );

      expect(resultado.success, isFalse);
      verifyNever(() => supabase.from('alimentos_favoritos'));
    });
  });

  group('listar', () {
    test('devolve as favoritas convertidas', () async {
      when(() => favoritosBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectListBuilder([
          {
            'id': 'fav-1',
            'tipo_refeicao': 'almoco',
            'nome': 'Meu almoço',
            'payload_jsonb': {
              'itens': [
                {'nome': 'Arroz'},
              ],
              'totais': {'calorias': 500},
            },
            'criado_em': '2026-08-20T12:00:00Z',
          },
        ]),
      );

      final favoritas = await repository.listar();

      expect(favoritas, hasLength(1));
      expect(favoritas.single.nome, 'Meu almoço');
      expect(favoritas.single.tipoRefeicao, TipoRefeicao.almoco);
      expect(favoritas.single.caloriasTotais, 500);
      expect(favoritas.single.quantidadeItens, 1);
    });

    test('lista vazia sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final favoritas = await repository.listar();

      expect(favoritas, isEmpty);
      verifyNever(() => supabase.from('alimentos_favoritos'));
    });

    test('lista vazia quando a consulta falha (não é erro pra tela)', () async {
      when(() => favoritosBuilder.select(any())).thenThrow(Exception('falha de rede'));

      final favoritas = await repository.listar();

      expect(favoritas, isEmpty);
    });
  });

  group('excluir', () {
    test('apaga pelo id', () async {
      when(() => favoritosBuilder.delete())
          .thenAnswer((_) => _FakeEqBuilder(Future.value(null)));

      final resultado = await repository.excluir('fav-1');

      expect(resultado.success, isTrue);
    });

    test('falha sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final resultado = await repository.excluir('fav-1');

      expect(resultado.success, isFalse);
      verifyNever(() => supabase.from('alimentos_favoritos'));
    });
  });

  group('atualizarTipo', () {
    test('faz UPDATE do tipo_refeicao pelo id', () async {
      when(() => favoritosBuilder.update({'tipo_refeicao': 'jantar'}))
          .thenAnswer((_) => _FakeEqBuilder(Future.value(null)));

      final resultado = await repository.atualizarTipo('fav-1', TipoRefeicao.jantar);

      expect(resultado.success, isTrue);
    });

    test('falha sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final resultado = await repository.atualizarTipo('fav-1', TipoRefeicao.jantar);

      expect(resultado.success, isFalse);
      verifyNever(() => supabase.from('alimentos_favoritos'));
    });
  });

  // RELATÓRIO 20260823 — 2º gap: editar o CONTEÚDO (itens/quantidades) de
  // uma favorita já salva.
  group('atualizarPayload', () {
    test('faz UPDATE do payload_jsonb pelo id', () async {
      final novoPayload = {
        'itens': [
          {'nome': 'Feijão'},
        ],
        'totais': {'calorias': 300},
      };
      when(() => favoritosBuilder.update({'payload_jsonb': novoPayload}))
          .thenAnswer((_) => _FakeEqBuilder(Future.value(null)));

      final resultado = await repository.atualizarPayload('fav-1', novoPayload);

      expect(resultado.success, isTrue);
      verify(() => favoritosBuilder.update({'payload_jsonb': novoPayload})).called(1);
    });

    test('falha sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final resultado = await repository.atualizarPayload('fav-1', const {});

      expect(resultado.success, isFalse);
      verifyNever(() => supabase.from('alimentos_favoritos'));
    });
  });
}
