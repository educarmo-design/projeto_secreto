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

  // Usados só por `buscarUltimoPesoKg` (RELATÓRIO 20260812_0011) — mesmo
  // encadeamento de `.select().eq().not().order().limit().maybeSingle()`.
  @override
  PostgrestFilterBuilder<List<Map<String, dynamic>>> not(
    String column,
    String operator,
    Object? value,
  ) => this as PostgrestFilterBuilder<List<Map<String, dynamic>>>;

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
  late _MockSupabaseQueryBuilder metricasBuilder;
  late _MockSupabaseQueryBuilder anamnesesBuilder;
  late PerfilUsuarioRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    perfisBuilder = _MockSupabaseQueryBuilder();
    metricasBuilder = _MockSupabaseQueryBuilder();
    anamnesesBuilder = _MockSupabaseQueryBuilder();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('perfis_usuarios')).thenAnswer((_) => perfisBuilder);
    when(() => supabase.from('metricas_saude_diarias')).thenAnswer((_) => metricasBuilder);
    when(() => supabase.from('anamneses')).thenAnswer((_) => anamnesesBuilder);

    repository = PerfilUsuarioRepository(supabaseClient: supabase);
  });

  // RELATÓRIO 20260916_0001 (SSOT, docs/motor_metabolico.txt) —
  // `perfis_usuarios.altura_cm` foi removida; a altura oficial agora vem da
  // última anamnese com o campo preenchido. Mesmo encadeamento
  // `.select().eq().not().order().limit().maybeSingle()` de
  // `buscarUltimoPesoKg`, por isso reaproveita `_FakeSelectFilterBuilder`.
  group('buscarAlturaCmDaUltimaAnamnese', () {
    test('devolve a altura da última anamnese com o campo preenchido', () async {
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'altura_cm': 179}),
      );

      final altura = await repository.buscarAlturaCmDaUltimaAnamnese();

      expect(altura, 179.0);
    });

    test('devolve null quando nunca preencheu uma anamnese com altura (não é erro)', () async {
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder(null),
      );

      final altura = await repository.buscarAlturaCmDaUltimaAnamnese();

      expect(altura, isNull);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final altura = await repository.buscarAlturaCmDaUltimaAnamnese();

      expect(altura, isNull);
      verifyNever(() => supabase.from('anamneses'));
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
    test('faz UPSERT em perfis_usuarios só com a data (sem hora) e o id', () async {
      when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(const <Map<String, dynamic>>[]),
        ),
      );

      await repository.atualizarDataNascimento(DateTime(2000, 5, 20));

      verify(() => perfisBuilder.upsert(
            {'id': _usuarioId, 'data_nascimento': '2000-05-20'},
            onConflict: 'id',
          )).called(1);
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
    test('faz UPSERT em perfis_usuarios com o código do ENUM e o id', () async {
      when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(const <Map<String, dynamic>>[]),
        ),
      );

      await repository.atualizarSexoBiologico(SexoBiologico.masculino);

      verify(() => perfisBuilder.upsert(
            {'id': _usuarioId, 'sexo_biologico': 'M'},
            onConflict: 'id',
          )).called(1);
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

  // RELATÓRIO 20260812_0011.
  group('buscarUltimoPesoKg', () {
    test('devolve o peso e a data quando há leitura sincronizada', () async {
      when(() => metricasBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'peso_kg': 80.6, 'data_referencia': '2026-08-10'}),
      );

      final peso = await repository.buscarUltimoPesoKg();

      expect(peso, isNotNull);
      expect(peso!.pesoKg, 80.6);
      expect(peso.dataReferencia, DateTime(2026, 8, 10));
    });

    test('devolve null quando nunca sincronizou peso (não é erro)', () async {
      when(() => metricasBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder(null),
      );

      final peso = await repository.buscarUltimoPesoKg();

      expect(peso, isNull);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final peso = await repository.buscarUltimoPesoKg();

      expect(peso, isNull);
      verifyNever(() => supabase.from('metricas_saude_diarias'));
    });
  });

  // N16 (RELATÓRIO 20260819) — mesmo padrão de buscarDataNascimento/
  // atualizarDataNascimento, exceto o valor padrão de "campo em branco":
  // aqui é 200 (o padrão de produto/coluna no banco), não `null`.
  group('buscarTamanhoCopoMl', () {
    test('devolve o tamanho quando a coluna está preenchida', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'tamanho_copo_ml': 350}),
      );

      final tamanho = await repository.buscarTamanhoCopoMl();

      expect(tamanho, 350);
    });

    test('devolve 200 (padrão) quando a coluna está vazia (não é erro)', () async {
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'tamanho_copo_ml': null}),
      );

      final tamanho = await repository.buscarTamanhoCopoMl();

      expect(tamanho, 200);
    });

    test('devolve 200 sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final tamanho = await repository.buscarTamanhoCopoMl();

      expect(tamanho, 200);
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  group('atualizarTamanhoCopoMl', () {
    test('faz UPSERT em perfis_usuarios com o id do usuário logado (cria a linha se faltar)', () async {
      when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(const <Map<String, dynamic>>[]),
        ),
      );

      await repository.atualizarTamanhoCopoMl(350);

      verify(() => perfisBuilder.upsert(
            {'id': _usuarioId, 'tamanho_copo_ml': 350},
            onConflict: 'id',
          )).called(1);
    });

    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(() => repository.atualizarTamanhoCopoMl(350), throwsStateError);
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });

  // RELATÓRIO 20261016_0005 (Tela de Perfil) / BUG CORRIGIDO no RELATÓRIO
  // 20261016_0008 — ver o doc de [PerfilUsuarioRepository.buscarPerfilConta].
  group('buscarPerfilConta', () {
    test('devolve email/nome/tipo decifrados pela RPC + cep lido direto, quando a linha já existe', () async {
      when(() => supabase.rpc('meu_perfil_seguro')).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(<Map<String, dynamic>>[
            {
              'nome': 'Maria Silva',
              'email': 'maria@teste.com',
              'eh_profissional': false,
              'tipo_profissional': null,
            },
          ]),
        ),
      );
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeSelectFilterBuilder({'cep': '01001000'}),
      );

      final perfil = await repository.buscarPerfilConta();

      expect(perfil, isNotNull);
      expect(perfil!.nome, 'Maria Silva');
      expect(perfil.email, 'maria@teste.com');
      expect(perfil.ehProfissional, false);
      expect(perfil.cep, '01001000');
    });

    // BUG CORRIGIDO (RELATÓRIO 20261016_0008) — achado real no device: a
    // tela "Meu Perfil" aparecia inteiramente vazia (sem erro nenhum) pra
    // uma conta cuja linha em `perfis_usuarios` nunca chegou a ser criada
    // (mesmo achado de `atleta1000@teste.com`, documentado no resto desta
    // classe). `meu_perfil_seguro()` devolve uma lista VAZIA nesse caso —
    // não é "ninguém logado", é "perfil ainda não existe".
    test('linha de perfis_usuarios ainda não existe: cria a linha e cai pro e-mail da sessão (nunca tela vazia)', () async {
      when(() => supabase.rpc('meu_perfil_seguro')).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(Future.value(const <Map<String, dynamic>>[])),
      );
      when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(Future.value(const <Map<String, dynamic>>[])),
      );
      when(() => auth.currentUser).thenReturn(
        const User(
          id: _usuarioId,
          email: 'sessao@teste.com',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );

      final perfil = await repository.buscarPerfilConta();

      expect(perfil, isNotNull);
      expect(perfil!.email, 'sessao@teste.com');
      expect(perfil.nome, isNull);
      expect(perfil.cep, isNull);
      expect(perfil.ehProfissional, false);
      verify(() => perfisBuilder.upsert({'id': _usuarioId}, onConflict: 'id')).called(1);
    });

    test('perfis_usuarios.email nulo (linha existe, mas sem email cifrado) cai pro e-mail da sessão', () async {
      when(() => supabase.rpc('meu_perfil_seguro')).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(
          Future.value(<Map<String, dynamic>>[
            {'nome': null, 'email': null, 'eh_profissional': false, 'tipo_profissional': null},
          ]),
        ),
      );
      when(() => perfisBuilder.select(any())).thenAnswer((_) => _FakeSelectFilterBuilder(null));
      when(() => auth.currentUser).thenReturn(
        const User(
          id: _usuarioId,
          email: 'sessao@teste.com',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );

      final perfil = await repository.buscarPerfilConta();

      expect(perfil!.email, 'sessao@teste.com');
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final perfil = await repository.buscarPerfilConta();

      expect(perfil, isNull);
      verifyNever(() => supabase.rpc(any()));
    });
  });

  group('atualizarNomeECep', () {
    test('faz UPSERT em perfis_usuarios com nome e cep', () async {
      when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
        (_) => _FakeFilterBuilder<dynamic>(Future.value(const <Map<String, dynamic>>[])),
      );

      await repository.atualizarNomeECep(nome: 'João Pereira', cep: '01001000');

      verify(() => perfisBuilder.upsert(
            {'id': _usuarioId, 'nome': 'João Pereira', 'cep': '01001000'},
            onConflict: 'id',
          )).called(1);
    });

    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        () => repository.atualizarNomeECep(nome: 'João', cep: '01001000'),
        throwsStateError,
      );
      verifyNever(() => supabase.from('perfis_usuarios'));
    });
  });
}
