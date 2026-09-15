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
/// `.eq()`/`.not()`/`.order()`/`.limit()`/`.maybeSingle()`/`.single()`
/// devolvendo sempre `this` (ou um `_FakeQuery` derivado, no caso de
/// `maybeSingle`/`single`), e resolve via `.then()` — mesmo espírito de
/// `_FakeFilterBuilder`/`_FakeSelectFilterBuilder` já usados em
/// `perfil_usuario_repository_test.dart`/`treinos_historico_repository_test.dart`,
/// só que unificado porque [AnamneseRepository] encadeia bem mais
/// combinações diferentes de método por chamada. `.upsert()` NÃO precisa
/// de suporte aqui — é stubado direto no `_MockSupabaseQueryBuilder` por
/// cada teste, mesmo padrão de `.insert()`.
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
  PostgrestFilterBuilder<T> not(String column, String operator, Object? value) => this;

  @override
  PostgrestTransformBuilder<T> limit(int count, {String? referencedTable}) =>
      this as PostgrestTransformBuilder<T>;

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

  /// Stuba `perfis_usuarios.upsert` (altura/sexo) + `metricas_saude_diarias`
  /// (o select de checagem "já tem peso hoje?" devolvendo vazio, e o
  /// upsert) — os dois efeitos colaterais de [AnamneseRepository.salvarAnamnese]
  /// ANTES do INSERT em `anamneses`. Chamado por todo teste de
  /// `salvarAnamnese` que não é o foco específico de altura/sexo/peso.
  ({_MockSupabaseQueryBuilder perfis, _MockSupabaseQueryBuilder metricas}) stubarDadosFisicos() {
    final perfisBuilder = builderPara('perfis_usuarios');
    when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
      (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
    );

    final metricasBuilder = builderPara('metricas_saude_diarias');
    when(() => metricasBuilder.select(any())).thenAnswer(
      (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
    );
    when(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
      (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
    );

    return (perfis: perfisBuilder, metricas: metricasBuilder);
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

    test('devolve a anamnese ativa com a rotina por dia da semana resolvida', () async {
      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'id': 'anamnese-1',
            'objetivo_codigo': 'hipertrofia',
            'data_preenchimento': '2026-09-01T00:00:00Z',
          },
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

      final atividadesBuilder = builderPara('anamneses_atividades_dias');
      when(() => atividadesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'atividade_id': 30,
            'dia_semana': 1,
            'minutos': 45,
            'tipos_atividades_fisicas': {'nome_exibicao': 'Corrida'},
          },
        ]),
      );

      final anamnese = await repository.buscarAnamneseAtiva();

      expect(anamnese, isNotNull);
      expect(anamnese!.objetivoCodigo, 'hipertrofia');
      expect(anamnese.dataPreenchimento, DateTime.parse('2026-09-01T00:00:00Z'));
      expect(anamnese.problemasSaudeIds, ['p1']);
      expect(anamnese.alergiaIds, ['a1']);
      expect(anamnese.atividades, hasLength(1));
      expect(anamnese.atividades.single.atividadeId, 30);
      expect(anamnese.atividades.single.diaSemana, 1);
      expect(anamnese.atividades.single.minutos, 45);
      expect(anamnese.atividades.single.nomeExibicao, 'Corrida');
    });
  });

  group('buscarDadosFisicosAtuais', () {
    test('devolve tudo null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final dados = await repository.buscarDadosFisicosAtuais();

      expect(dados.alturaCm, isNull);
      expect(dados.sexoBiologico, isNull);
      expect(dados.pesoKg, isNull);
      verifyNever(() => supabase.from(any()));
    });

    test('resolve altura/sexo de perfis_usuarios e peso da última leitura de metricas_saude_diarias', () async {
      final perfisBuilder = builderPara('perfis_usuarios');
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'altura_cm': 179, 'sexo_biologico': 'M'},
        ]),
      );

      final metricasBuilder = builderPara('metricas_saude_diarias');
      when(() => metricasBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'peso_kg': 78.5},
        ]),
      );

      final dados = await repository.buscarDadosFisicosAtuais();

      expect(dados.alturaCm, 179.0);
      expect(dados.sexoBiologico, 'M');
      expect(dados.pesoKg, 78.5);
    });
  });

  group('salvarAnamnese', () {
    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        () => repository.salvarAnamnese(
          objetivoCodigo: 'emagrecimento',
          alturaCm: 179,
          sexoBiologico: 'M',
          pesoKg: 78,
          problemasSaudeIds: const [],
          alergiaIds: const [],
          atividades: const [],
        ),
        throwsStateError,
      );
      verifyNever(() => supabase.from(any()));
    });

    test('grava altura/sexo (perfis_usuarios) e peso de hoje (metricas_saude_diarias) antes da anamnese', () async {
      final dadosFisicos = stubarDadosFisicos();

      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'manutencao',
        alturaCm: 179,
        sexoBiologico: 'M',
        pesoKg: 78.5,
        problemasSaudeIds: const [],
        alergiaIds: const [],
        atividades: const [],
      );

      verify(
        () => dadosFisicos.perfis
            .upsert({'id': _usuarioId, 'altura_cm': 179.0, 'sexo_biologico': 'M'}, onConflict: 'id'),
      ).called(1);

      final hoje = DateTime.now();
      final dataReferenciaEsperada =
          '${hoje.year.toString().padLeft(4, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
      verify(
        () => dadosFisicos.metricas.upsert(
          {
            'usuario_id_anonimo': _usuarioId,
            'data_referencia': dataReferenciaEsperada,
            'peso_kg': 78.5,
            'origem': 'manual',
          },
          onConflict: 'usuario_id_anonimo,data_referencia',
        ),
      ).called(1);
    });

    test('NÃO sobrescreve o peso quando já existe uma leitura pra hoje', () async {
      final perfisBuilder = builderPara('perfis_usuarios');
      when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final metricasBuilder = builderPara('metricas_saude_diarias');
      when(() => metricasBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'peso_kg': 80.0},
        ]),
      );

      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'manutencao',
        alturaCm: 179,
        sexoBiologico: 'M',
        pesoKg: 78.5,
        problemasSaudeIds: const [],
        alergiaIds: const [],
        atividades: const [],
      );

      verifyNever(() => metricasBuilder.upsert(any(), onConflict: any(named: 'onConflict')));
    });

    test('insere a anamnese e as relações N:N (incluindo a rotina por dia) com os payloads corretos', () async {
      stubarDadosFisicos();

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

      final atividadesBuilder = builderPara('anamneses_atividades_dias');
      when(() => atividadesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'manutencao',
        alturaCm: 179,
        sexoBiologico: 'M',
        pesoKg: 78.5,
        problemasSaudeIds: const ['p1', 'p2'],
        alergiaIds: const ['a1'],
        atividades: const [
          AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 1),
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
          {'anamnese_id': 'anamnese-nova', 'atividade_id': 30, 'dia_semana': 1, 'minutos': 45},
        ]),
      ).called(1);
    });

    test('não chama insert nas tabelas N:N quando as listas vêm vazias', () async {
      stubarDadosFisicos();

      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'emagrecimento',
        alturaCm: 179,
        sexoBiologico: 'M',
        pesoKg: 78.5,
        problemasSaudeIds: const [],
        alergiaIds: const [],
        atividades: const [],
      );

      verifyNever(() => supabase.from('anamneses_problemas_saude'));
      verifyNever(() => supabase.from('anamneses_alergias'));
      verifyNever(() => supabase.from('anamneses_atividades_dias'));
    });
  });
}
