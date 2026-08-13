import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

/// Fake genérico de query encadeável — cobre `.select()`/`.insert()`/
/// `.eq()`/`.order()`/`.maybeSingle()`/`.single()` devolvendo sempre `this`
/// (ou um `_FakeQuery` derivado, no caso de `maybeSingle`/`single`), e
/// resolve via `.then()` — mesmo espírito de `_FakeFilterBuilder`/
/// `_FakeSelectFilterBuilder` já usados em
/// `perfil_usuario_repository_test.dart`/`treinos_historico_repository_test.dart`,
/// só que unificado porque [AnamneseRepository] encadeia bem mais
/// combinações diferentes de método por chamada.
class _FakeQuery<T> extends Fake implements PostgrestFilterBuilder<T> {
  _FakeQuery(this._value);
  final T _value;

  // Só chamado no encadeamento `.insert(...).select('id').single()` — o
  // `.select()' usado DIRETO em `supabase.from(x).select(...)` roda no
  // `_MockSupabaseQueryBuilder` (stubado por teste), nunca aqui. Por isso o
  // retorno fixo em `PostgrestList` (a assinatura real de
  // `PostgrestTransformBuilder.select`), não genérico em `T`.
  @override
  PostgrestTransformBuilder<List<Map<String, dynamic>>> select([String columns = '*']) {
    return _FakeQuery<List<Map<String, dynamic>>>(_value as List<Map<String, dynamic>>);
  }

  @override
  PostgrestFilterBuilder<T> eq(String column, Object value) => this;

  @override
  PostgrestTransformBuilder<T> order(
    String column, {
    bool ascending = false,
    bool nullsFirst = false,
    String? referencedTable,
  }) => this as PostgrestTransformBuilder<T>;

  @override
  PostgrestTransformBuilder<Map<String, dynamic>?> maybeSingle() {
    final lista = _value as List;
    final unica = lista.isEmpty ? null : lista.first as Map<String, dynamic>;
    return _FakeQuery<Map<String, dynamic>?>(unica);
  }

  @override
  PostgrestTransformBuilder<Map<String, dynamic>> single() {
    final lista = _value as List;
    return _FakeQuery<Map<String, dynamic>>(lista.first as Map<String, dynamic>);
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
  late AnamneseRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(_usuarioAutenticado);

    repository = AnamneseRepository(supabaseClient: supabase);
  });

  _MockSupabaseQueryBuilder builderPara(String tabela) {
    final builder = _MockSupabaseQueryBuilder();
    when(() => supabase.from(tabela)).thenAnswer((_) => builder);
    return builder;
  }

  group('catálogos', () {
    test('buscarProblemasSaude devolve a lista mapeada (id/nome)', () async {
      final builder = builderPara('problemas_saude');
      when(() => builder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'p1', 'nome': 'Diabetes Tipo 2'},
        ]),
      );

      final itens = await repository.buscarProblemasSaude();

      expect(itens, hasLength(1));
      expect(itens.single.id, 'p1');
      expect(itens.single.nome, 'Diabetes Tipo 2');
    });

    test('buscarAlergias devolve a lista mapeada a partir de nome_exibicao', () async {
      final builder = builderPara('alergias');
      when(() => builder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'a1', 'nome_exibicao': 'Intolerância à Lactose'},
        ]),
      );

      final itens = await repository.buscarAlergias();

      expect(itens.single.id, 'a1');
      expect(itens.single.nome, 'Intolerância à Lactose');
    });

    test('buscarTiposAtividades devolve a lista mapeada (id smallint/nome_exibicao)', () async {
      final builder = builderPara('tipos_atividades_fisicas');
      when(() => builder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 30, 'nome_exibicao': 'Corrida'},
        ]),
      );

      final itens = await repository.buscarTiposAtividades();

      expect(itens.single.id, 30);
      expect(itens.single.nomeExibicao, 'Corrida');
    });
  });

  group('buscarAnamneseAtiva', () {
    test('devolve null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final anamnese = await repository.buscarAnamneseAtiva();

      expect(anamnese, isNull);
      verifyNever(() => supabase.from(any()));
    });

    test('devolve null quando o usuário nunca preencheu uma anamnese', () async {
      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final anamnese = await repository.buscarAnamneseAtiva();

      expect(anamnese, isNull);
    });

    test('devolve a anamnese ativa com as 3 relações N:N resolvidas', () async {
      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-1', 'objetivo_codigo': 'hipertrofia'},
        ]),
      );

      final problemasBuilder = builderPara('anamneses_problemas_saude');
      when(() => problemasBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'problema_saude_id': 'p1'},
        ]),
      );

      final alergiasBuilder = builderPara('anamneses_alergias');
      when(() => alergiasBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'alergia_id': 'a1'},
        ]),
      );

      final atividadesBuilder = builderPara('anamneses_atividades');
      when(() => atividadesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'atividade_id': 30,
            'minutos_diarios': 45,
            'tipos_atividades_fisicas': {'nome_exibicao': 'Corrida'},
          },
        ]),
      );

      final anamnese = await repository.buscarAnamneseAtiva();

      expect(anamnese, isNotNull);
      expect(anamnese!.objetivoCodigo, 'hipertrofia');
      expect(anamnese.problemasSaudeIds, ['p1']);
      expect(anamnese.alergiaIds, ['a1']);
      expect(anamnese.atividades, hasLength(1));
      expect(anamnese.atividades.single.atividadeId, 30);
      expect(anamnese.atividades.single.minutosDiarios, 45);
      expect(anamnese.atividades.single.nomeExibicao, 'Corrida');
    });
  });

  group('salvarAnamnese', () {
    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        () => repository.salvarAnamnese(
          objetivoCodigo: 'emagrecimento',
          problemasSaudeIds: const [],
          alergiaIds: const [],
          atividades: const [],
        ),
        throwsStateError,
      );
      verifyNever(() => supabase.from(any()));
    });

    test('insere a anamnese e as 3 relações N:N com os payloads corretos', () async {
      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      final problemasBuilder = builderPara('anamneses_problemas_saude');
      when(() => problemasBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final alergiasBuilder = builderPara('anamneses_alergias');
      when(() => alergiasBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final atividadesBuilder = builderPara('anamneses_atividades');
      when(() => atividadesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'manutencao',
        problemasSaudeIds: const ['p1', 'p2'],
        alergiaIds: const ['a1'],
        atividades: const [
          AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutosDiarios: 45),
        ],
      );

      verify(
        () => anamnesesBuilder.insert({'usuario_id': _usuarioId, 'objetivo_codigo': 'manutencao'}),
      ).called(1);
      verify(
        () => problemasBuilder.insert([
          {'anamnese_id': 'anamnese-nova', 'problema_saude_id': 'p1'},
          {'anamnese_id': 'anamnese-nova', 'problema_saude_id': 'p2'},
        ]),
      ).called(1);
      verify(
        () => alergiasBuilder.insert([
          {'anamnese_id': 'anamnese-nova', 'alergia_id': 'a1'},
        ]),
      ).called(1);
      verify(
        () => atividadesBuilder.insert([
          {'anamnese_id': 'anamnese-nova', 'atividade_id': 30, 'minutos_diarios': 45},
        ]),
      ).called(1);
    });

    test('não chama insert nas tabelas N:N quando as listas vêm vazias', () async {
      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'emagrecimento',
        problemasSaudeIds: const [],
        alergiaIds: const [],
        atividades: const [],
      );

      verifyNever(() => supabase.from('anamneses_problemas_saude'));
      verifyNever(() => supabase.from('anamneses_alergias'));
      verifyNever(() => supabase.from('anamneses_atividades'));
    });
  });
}
