import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Fake genérico de query encadeável — mesmo espírito de `_FakeQuery` em
/// `anamnese_repository_test.dart`, estendido com `.isFilter()`/`.not()`
/// (usados por `buscarMinhaUltimaMetaPropria`/`buscarMetaAtivaDoProfissional`).
class _FakeQuery<T> extends Fake implements PostgrestFilterBuilder<T> {
  _FakeQuery(this._value);
  final T _value;

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestFilterBuilder<T> isFilter(String column, bool? value) => this;

  @override
  PostgrestFilterBuilder<T> not(String column, String operator, Object? value) => this;

  @override
  PostgrestTransformBuilder<T> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) => this as PostgrestTransformBuilder<T>;

  @override
  PostgrestTransformBuilder<T> limit(int count, {String? referencedTable}) =>
      this as PostgrestTransformBuilder<T>;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    final lista = _value as List;
    final unica = lista.isEmpty ? null : lista.first as Map<String, dynamic>;
    return _FakeQuery<Map<String, dynamic>?>(unica);
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => Future.value(_value).then(onValue, onError: onError);
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
  late _MockSupabaseQueryBuilder objetivosBuilder;
  late MetaBemEstarRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    objetivosBuilder = _MockSupabaseQueryBuilder();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);
    when(() => supabase.from('objetivos_alimentares')).thenAnswer((_) => objetivosBuilder);

    repository = MetaBemEstarRepository(supabaseClient: supabase);
  });

  group('buscarMinhaUltimaMetaPropria', () {
    test('devolve a meta quando existe uma auto-criada', () async {
      when(() => objetivosBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'calorias_alvo': 2200,
            'proteina_g': 150,
            'carbo_g': 220,
            'gordura_g': 70,
            'data_criacao': '2026-08-01T00:00:00Z',
          },
        ]),
      );

      final meta = await repository.buscarMinhaUltimaMetaPropria();

      expect(meta, isNotNull);
      expect(meta!.caloriasAlvo, 2200);
      expect(meta.dataCriacao, DateTime.parse('2026-08-01T00:00:00Z'));
    });

    test('devolve null quando nunca criou uma (não é erro)', () async {
      when(() => objetivosBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final meta = await repository.buscarMinhaUltimaMetaPropria();

      expect(meta, isNull);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final meta = await repository.buscarMinhaUltimaMetaPropria();

      expect(meta, isNull);
      verifyNever(() => supabase.from('objetivos_alimentares'));
    });
  });

  group('buscarMetaAtivaDoProfissional', () {
    test('devolve a meta quando o profissional tem uma ativa', () async {
      when(() => objetivosBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'calorias_alvo': 1900,
            'proteina_g': 160,
            'carbo_g': 180,
            'gordura_g': 60,
            'data_criacao': '2026-08-05T00:00:00Z',
          },
        ]),
      );

      final meta = await repository.buscarMetaAtivaDoProfissional();

      expect(meta, isNotNull);
      expect(meta!.caloriasAlvo, 1900);
    });

    test('devolve null quando não há meta prescrita (não é erro)', () async {
      when(() => objetivosBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final meta = await repository.buscarMetaAtivaDoProfissional();

      expect(meta, isNull);
    });
  });

  // RELATÓRIO 20260820 — card "consumo × meta" (N12) usa isto pra achar a
  // meta EFETIVA sem duplicar a regra de precedência já em
  // MetaBemEstarPage._carregar.
  group('buscarMetaEfetivaAtual', () {
    test('meta do profissional vence — própria nunca é consultada (short-circuit)', () async {
      when(() => objetivosBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'calorias_alvo': 1900,
            'proteina_g': 160,
            'carbo_g': 180,
            'gordura_g': 60,
            'data_criacao': '2026-08-05T00:00:00Z',
          },
        ]),
      );

      final meta = await repository.buscarMetaEfetivaAtual();

      expect(meta, isNotNull);
      expect(meta!.caloriasAlvo, 1900);
      verify(() => objetivosBuilder.select(any())).called(1);
    });

    test('sem meta do profissional, cai pra própria (as duas consultas rodam)', () async {
      when(() => objetivosBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final meta = await repository.buscarMetaEfetivaAtual();

      expect(meta, isNull);
      verify(() => objetivosBuilder.select(any())).called(2);
    });
  });

  group('buscarSugestaoCalorias', () {
    test('devolve gasto_sedentario do Motor N07', () async {
      when(() => supabase.rpc('calcular_motor_metabolico', params: any(named: 'params')))
          .thenAnswer((_) => _FakeQuery<Map<String, dynamic>>({'gasto_sedentario': 2128.8, 'tmb': 1774}));

      final sugestao = await repository.buscarSugestaoCalorias();

      expect(sugestao, 2128.8);
    });

    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final sugestao = await repository.buscarSugestaoCalorias();

      expect(sugestao, isNull);
      verifyNever(() => supabase.rpc(any(), params: any(named: 'params')));
    });
  });

  group('salvarMeta', () {
    test('chama a RPC validar_e_salvar_meta com p_is_profissional=false', () async {
      when(() => supabase.rpc('validar_e_salvar_meta', params: any(named: 'params'))).thenAnswer(
        (_) => _FakeQuery<Map<String, dynamic>>({'sucesso': true, 'violacao_clinica': false, 'avisos': []}),
      );

      await repository.salvarMeta(caloriasAlvo: 2200, proteinaG: 150, carboG: 220, gorduraG: 70);

      verify(() => supabase.rpc('validar_e_salvar_meta', params: {
            'p_payload': {
              'tipo_dia': 'PADRAO',
              'calorias_alvo': 2200,
              'proteina_g': 150,
              'carbo_g': 220,
              'gordura_g': 70,
            },
            'p_is_profissional': false,
          })).called(1);
    });

    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(() => repository.salvarMeta(caloriasAlvo: 2200), throwsStateError);
      verifyNever(() => supabase.rpc(any(), params: any(named: 'params')));
    });

    test('trava clínica (N08_TRAVA_CLINICA) vira MetaBloqueadaException com o motivo certo', () async {
      when(() => supabase.rpc('validar_e_salvar_meta', params: any(named: 'params'))).thenThrow(
        const PostgrestException(
          message: 'N08_TRAVA_CLINICA: Esta meta está fora da faixa de segurança...',
        ),
      );

      try {
        await repository.salvarMeta(caloriasAlvo: 5000, gorduraG: 10);
        fail('deveria ter lançado MetaBloqueadaException');
      } on MetaBloqueadaException catch (erro) {
        expect(erro.motivo, MotivoBloqueioN08.travaClinica);
      }
    });

    test('prioridade profissional (N08_PRIORIDADE_PROFISSIONAL) vira o motivo certo', () async {
      when(() => supabase.rpc('validar_e_salvar_meta', params: any(named: 'params'))).thenThrow(
        const PostgrestException(message: 'N08_PRIORIDADE_PROFISSIONAL: ...'),
      );

      try {
        await repository.salvarMeta(caloriasAlvo: 2200);
        fail('deveria ter lançado MetaBloqueadaException');
      } on MetaBloqueadaException catch (erro) {
        expect(erro.motivo, MotivoBloqueioN08.prioridadeProfissional);
      }
    });

    test('carência mensal (N08_CARENCIA_MENSAL) vira o motivo certo', () async {
      when(() => supabase.rpc('validar_e_salvar_meta', params: any(named: 'params'))).thenThrow(
        const PostgrestException(message: 'N08_CARENCIA_MENSAL: ...'),
      );

      try {
        await repository.salvarMeta(caloriasAlvo: 2200);
        fail('deveria ter lançado MetaBloqueadaException');
      } on MetaBloqueadaException catch (erro) {
        expect(erro.motivo, MotivoBloqueioN08.carenciaMensal);
      }
    });
  });
}
