import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Mesmo padrão de `perfil_usuario_repository_test.dart`: `PostgrestFilterBuilder`/
/// `PostgrestTransformBuilder` resolvem `await` via `.then()` (implementam
/// `Future`), então basta encaminhar `.then()` a um `Future` controlável.
class _FakeInsertBuilder extends Fake implements PostgrestFilterBuilder<dynamic> {
  _FakeInsertBuilder(this._future);
  final Future<dynamic> _future;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
}

/// Encadeia `.eq()`/`.gte()` (quantas vezes forem chamadas) e `.order()`,
/// resolvendo direto pra uma `List<Map<String, dynamic>>` — usado por
/// `buscarTotalAguaDoDia`/`buscarHistoricoAgua`, que nunca chegam a
/// `.maybeSingle()` (diferente das buscas de `perfis_usuarios`).
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
  PostgrestFilterBuilder<List<Map<String, dynamic>>> gte(
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
  late _MockSupabaseQueryBuilder coletaBuilder;
  late ColetaDiariaRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    coletaBuilder = _MockSupabaseQueryBuilder();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('coleta_diaria')).thenAnswer((_) => coletaBuilder);

    repository = ColetaDiariaRepository(supabaseClient: supabase);
  });

  // N16 (RELATÓRIO 20260819).
  group('gravarAgua', () {
    test('grava uma linha em coleta_diaria com atributo=agua_ml, origem=manual', () async {
      when(() => coletaBuilder.insert(any())).thenAnswer(
        (_) => _FakeInsertBuilder(Future.value(null)),
      );

      final resultado = await repository.gravarAgua(
        mililitros: 200,
        dataColeta: DateTime(2026, 8, 19),
      );

      expect(resultado.success, isTrue);
      verify(() => coletaBuilder.insert({
            'usuario_id': _usuarioId,
            'atributo': 'agua_ml',
            'valor_numerico': 200,
            'unidade': 'ml',
            'origem': 'manual',
            'data_coleta': '2026-08-19',
          })).called(1);
    });

    test('falha sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final resultado = await repository.gravarAgua(mililitros: 200);

      expect(resultado.success, isFalse);
      verifyNever(() => supabase.from('coleta_diaria'));
    });

    test('PostgrestException vira mensagem amigável, nunca propaga crua', () async {
      when(() => coletaBuilder.insert(any())).thenThrow(
        const PostgrestException(message: 'erro de rede', code: '500'),
      );

      final resultado = await repository.gravarAgua(mililitros: 200);

      expect(resultado.success, isFalse);
      expect(resultado.errorMessage, isNotNull);
      expect(resultado.debugDetail, contains('erro de rede'));
    });
  });

  group('buscarTotalAguaDoDia', () {
    test('soma valor_numerico de todas as linhas do dia', () async {
      when(() => coletaBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectListBuilder([
          {'valor_numerico': 200},
          {'valor_numerico': 350},
        ]),
      );

      final total = await repository.buscarTotalAguaDoDia();

      expect(total, 550);
    });

    test('0 quando não há nenhum registro no dia (não é erro)', () async {
      when(() => coletaBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectListBuilder(const []),
      );

      final total = await repository.buscarTotalAguaDoDia();

      expect(total, 0);
    });

    test('0 sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final total = await repository.buscarTotalAguaDoDia();

      expect(total, 0);
      verifyNever(() => supabase.from('coleta_diaria'));
    });
  });

  group('buscarHistoricoAgua', () {
    test('agrupa e soma por dia, mais recente primeiro', () async {
      when(() => coletaBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectListBuilder([
          {'valor_numerico': 200, 'data_coleta': '2026-08-19'},
          {'valor_numerico': 350, 'data_coleta': '2026-08-19'},
          {'valor_numerico': 400, 'data_coleta': '2026-08-18'},
        ]),
      );

      final historico = await repository.buscarHistoricoAgua();

      expect(historico, hasLength(2));
      expect(historico[0].data, DateTime(2026, 8, 19));
      expect(historico[0].totalMl, 550);
      expect(historico[1].data, DateTime(2026, 8, 18));
      expect(historico[1].totalMl, 400);
    });

    test('lista vazia sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final historico = await repository.buscarHistoricoAgua();

      expect(historico, isEmpty);
      verifyNever(() => supabase.from('coleta_diaria'));
    });
  });
}
