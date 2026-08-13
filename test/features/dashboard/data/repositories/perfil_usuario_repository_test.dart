import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/features/dashboard/data/repositories/perfil_usuario_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Mesmo padrão de `health_sync_service_test.dart`
/// (`_FakeFilterBuilder`/`_FakeAlturaFilterBuilder`): `PostgrestFilterBuilder`
/// e `PostgrestTransformBuilder` resolvem `await` via `.then()` (implementam
/// `Future`), então basta encaminhar `.then()` a um `Future` controlável.
class _FakeFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  _FakeFilterBuilder(this._future);
  final Future<T> _future;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _future.then(onValue, onError: onError);
}

class _FakeSelectFilterBuilder extends Fake
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  _FakeSelectFilterBuilder(this._resultado);
  final Map<String, dynamic>? _resultado;

  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> eq(
    String column,
    Object value,
  ) => this as PostgrestFilterBuilder<List<Map<String, dynamic>>>;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() =>
      _FakeSelectTransformBuilder(_resultado);
}

class _FakeSelectTransformBuilder extends Fake
    implements PostgrestTransformBuilder<Map<String, dynamic>?> {
  _FakeSelectTransformBuilder(this._resultado);
  final Map<String, dynamic>? _resultado;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(Map<String, dynamic>? value) onValue, {
    Function? onError,
  }) => Future.value(_resultado).then(onValue, onError: onError);
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
  late _MockSupabaseQueryBuilder perfisBuilder;
  late PerfilUsuarioRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    perfisBuilder = _MockSupabaseQueryBuilder();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('perfis_usuarios')).thenAnswer((_) => perfisBuilder);

    repository = PerfilUsuarioRepository(supabaseClient: supabase);
  });

  group('buscarAlturaCm', () {
    test('devolve a altura quando a coluna está preenchida', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'altura_cm': 179}),
      );

      final altura = await repository.buscarAlturaCm();

      expect(altura, 179.0);
    });

    test('devolve null quando a coluna está vazia (não é erro)', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'altura_cm': null}),
      );

      final altura = await repository.buscarAlturaCm();

      expect(altura, isNull);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final altura = await repository.buscarAlturaCm();

      expect(altura, isNull);
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  group('atualizarAlturaCm', () {
    test('faz UPDATE em perfis_usuarios filtrado pelo id do usuário logado', () async {
      when(() => perfisBuilder.update(any())).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(const <Map<String, dynamic>>[]),
        ),
      );

      await repository.atualizarAlturaCm(179);

      verify(() => perfisBuilder.update({'altura_cm': 179.0})).called(1);
    });

    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(() => repository.atualizarAlturaCm(179), throwsStateError);
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  // N03 (RELATÓRIO 20260811_0005) — mesmo padrão de buscarAlturaCm/
  // atualizarAlturaCm acima, incluindo a convenção "null = ninguém
  // logado ou coluna vazia".
  group('buscarDataNascimento', () {
    test('devolve a data quando a coluna está preenchida', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'data_nascimento': '2000-05-20'}),
      );

      final data = await repository.buscarDataNascimento();

      expect(data, DateTime(2000, 5, 20));
    });

    test('devolve null quando a coluna está vazia (não é erro)', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'data_nascimento': null}),
      );

      final data = await repository.buscarDataNascimento();

      expect(data, isNull);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final data = await repository.buscarDataNascimento();

      expect(data, isNull);
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  group('atualizarDataNascimento', () {
    test('faz UPDATE em perfis_usuarios só com a data (sem hora), filtrado pelo id', () async {
      when(() => perfisBuilder.update(any())).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(const <Map<String, dynamic>>[]),
        ),
      );

      await repository.atualizarDataNascimento(DateTime(2000, 5, 20));

      verify(() => perfisBuilder.update({'data_nascimento': '2000-05-20'}))
          .called(1);
    });

    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        () => repository.atualizarDataNascimento(DateTime(2000, 5, 20)),
        throwsStateError,
      );
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  // N07 (RELATÓRIO 20260812_0008) — mesmo padrão de buscarDataNascimento/
  // atualizarDataNascimento acima.
  group('buscarSexoBiologico', () {
    test('devolve o sexo quando a coluna está preenchida', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'sexo_biologico': 'F'}),
      );

      final sexo = await repository.buscarSexoBiologico();

      expect(sexo, SexoBiologico.feminino);
    });

    test('devolve null quando a coluna está vazia (não é erro)', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'sexo_biologico': null}),
      );

      final sexo = await repository.buscarSexoBiologico();

      expect(sexo, isNull);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final sexo = await repository.buscarSexoBiologico();

      expect(sexo, isNull);
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  group('atualizarSexoBiologico', () {
    test('faz UPDATE em perfis_usuarios com o código do ENUM, filtrado pelo id', () async {
      when(() => perfisBuilder.update(any())).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(const <Map<String, dynamic>>[]),
        ),
      );

      await repository.atualizarSexoBiologico(SexoBiologico.masculino);

      verify(() => perfisBuilder.update({'sexo_biologico': 'M'})).called(1);
    });

    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        () => repository.atualizarSexoBiologico(SexoBiologico.masculino),
        throwsStateError,
      );
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });
}
