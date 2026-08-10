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
}
