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
  PostgrestFilterBuilder<T> or(String filters, {String? referencedTable}) => this;

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

  /// Stuba `perfis_usuarios.upsert` (só `sexo_biologico` — RELATÓRIO
  /// 20260916_0001/SSOT: altura/peso pararam de gravar aqui) — o único
  /// efeito colateral de [AnamneseRepository.salvarAnamnese] ANTES do
  /// INSERT em `anamneses`. Chamado por todo teste de `salvarAnamnese` que
  /// não é o foco específico dessa gravação.
  _MockSupabaseQueryBuilder stubarUpsertSexo() {
    final perfisBuilder = builderPara('perfis_usuarios');
    when(() => perfisBuilder.upsert(any(), onConflict: any(named: 'onConflict'))).thenAnswer(
      (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
    );
    return perfisBuilder;
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
            'objetivo_codigo': 'ganhar_massa_muscular',
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
      expect(anamnese!.objetivoCodigo, 'ganhar_massa_muscular');
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

    test('resolve sexo de perfis_usuarios e altura/peso da última anamnese com os dois preenchidos', () async {
      final perfisBuilder = builderPara('perfis_usuarios');
      when(() => perfisBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'sexo_biologico': 'M'},
        ]),
      );

      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'peso_kg': 78.5, 'altura_cm': 179},
        ]),
      );

      final dados = await repository.buscarDadosFisicosAtuais();

      expect(dados.alturaCm, 179.0);
      expect(dados.sexoBiologico, 'M');
      expect(dados.pesoKg, 78.5);
    });
  });

  group('buscarSugestaoBalanca', () {
    test('devolve tudo null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final sugestao = await repository.buscarSugestaoBalanca();

      expect(sugestao.pesoKg, isNull);
      expect(sugestao.percentualGordura, isNull);
      verifyNever(() => supabase.from(any()));
    });

    test('devolve peso e percentual de gordura da última leitura', () async {
      final metricasBuilder = builderPara('metricas_saude_diarias');
      when(() => metricasBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'peso_kg': 82.4, 'percentual_gordura': 18.5, 'data_referencia': '2026-09-16'},
        ]),
      );

      final sugestao = await repository.buscarSugestaoBalanca();

      expect(sugestao.pesoKg, 82.4);
      expect(sugestao.percentualGordura, 18.5);
      expect(sugestao.dataReferencia, DateTime.parse('2026-09-16'));
      expect(sugestao.temAlgumDado, isTrue);
    });

    test('devolve tudo null quando nunca sincronizou nada (não é erro)', () async {
      final metricasBuilder = builderPara('metricas_saude_diarias');
      when(() => metricasBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([]),
      );

      final sugestao = await repository.buscarSugestaoBalanca();

      expect(sugestao.temAlgumDado, isFalse);
    });
  });

  group('buscarHistoricoAnamneses', () {
    test('devolve lista vazia sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final historico = await repository.buscarHistoricoAnamneses();

      expect(historico, isEmpty);
      verifyNever(() => supabase.from(any()));
    });

    test('devolve todas as anamneses mapeadas, mais recente primeiro', () async {
      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.select(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {
            'id': 'anamnese-2',
            'data_preenchimento': '2026-09-10T00:00:00Z',
            'objetivo_codigo': 'ganhar_massa_muscular',
            'peso_kg': 79.3,
            'altura_cm': 178.0,
            'status_vigencia': 'ativo',
          },
          {
            'id': 'anamnese-1',
            'data_preenchimento': '2026-08-10T00:00:00Z',
            'objetivo_codigo': 'perder_peso',
            'peso_kg': null,
            'altura_cm': null,
            'status_vigencia': 'historico',
          },
        ]),
      );

      final historico = await repository.buscarHistoricoAnamneses();

      expect(historico, hasLength(2));
      expect(historico[0].id, 'anamnese-2');
      expect(historico[0].pesoKg, 79.3);
      expect(historico[0].alturaCm, 178.0);
      expect(historico[0].statusVigencia, 'ativo');
      expect(historico[1].id, 'anamnese-1');
      expect(historico[1].pesoKg, isNull);
      expect(historico[1].statusVigencia, 'historico');
    });
  });

  group('buscarHistoricoPeso', () {
    test('devolve tudo null sem consultar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      final historico = await repository.buscarHistoricoPeso();

      expect(historico.pesoAtual, isNull);
      verifyNever(() => supabase.rpc(any(), params: any(named: 'params')));
    });

    test('chama a RPC anamnese_historico_peso e mapeia o resultado', () async {
      when(() => supabase.rpc('anamnese_historico_peso', params: {'p_usuario_id': _usuarioId})).thenAnswer(
        (_) => _FakeQuery<Map<String, dynamic>>({
          'peso_atual': 88.0,
          'peso_anterior': 90.0,
          'peso_30_dias': null,
          'peso_3_meses': null,
          'peso_6_meses': null,
          'peso_12_meses': null,
          'maior_peso': 90.0,
          'menor_peso': 88.0,
          'variacao_percentual': -2.2,
        }),
      );

      final historico = await repository.buscarHistoricoPeso();

      expect(historico.pesoAtual, 88.0);
      expect(historico.pesoAnterior, 90.0);
      expect(historico.maiorPeso, 90.0);
      expect(historico.menorPeso, 88.0);
      expect(historico.variacaoPercentual, -2.2);
      expect(historico.temAlgumDado, isTrue);
    });
  });

  group('salvarAnamnese', () {
    test('lança StateError sem chamar o Supabase quando ninguém está logado', () async {
      when(() => auth.currentUser).thenReturn(null);

      expect(
        () => repository.salvarAnamnese(
          objetivoCodigo: 'perder_peso',
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

    test('grava sexo (perfis_usuarios) + peso/altura DIRETO na anamnese (SSOT)', () async {
      final perfisBuilder = stubarUpsertSexo();

      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'manter_peso',
        alturaCm: 179,
        sexoBiologico: 'M',
        pesoKg: 78.5,
        problemasSaudeIds: const [],
        alergiaIds: const [],
        atividades: const [],
      );

      verify(
        () => perfisBuilder.upsert({'id': _usuarioId, 'sexo_biologico': 'M'}, onConflict: 'id'),
      ).called(1);

      final hoje = DateTime.now();
      final dataReferenciaEsperada =
          '${hoje.year.toString().padLeft(4, '0')}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';

      // RELATÓRIO 20260918_0001 — o payload ganhou ~35 campos opcionais
      // (Blocos 1-16 de docs/motor_metabolico.txt); em vez de igualdade
      // exata do Map inteiro (frágil a cada novo campo opcional futuro),
      // captura a chamada e confere só os campos que este teste realmente
      // documenta — os campos "fixos" que já existiam antes desta tarefa +
      // os 2 que toda chamada de salvarAnamnese sempre grava agora
      // (dados_confirmados/confirmado_em, Seção 11 — "Confirme seus dados").
      final payload = verify(() => anamnesesBuilder.insert(captureAny())).captured.single as Map<String, dynamic>;
      expect(payload['usuario_id'], _usuarioId);
      expect(payload['objetivo_codigo'], 'manter_peso');
      expect(payload['peso_kg'], 78.5);
      expect(payload['altura_cm'], 179.0);
      expect(payload['peso_data_medicao'], dataReferenciaEsperada);
      expect(payload['peso_origem'], 'usuario');
      expect(payload['dados_confirmados'], isTrue);
      expect(payload['confirmado_em'], isNotNull);
    });

    test('insere a anamnese e as relações N:N (incluindo a rotina por dia) com os payloads corretos', () async {
      stubarUpsertSexo();

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
        objetivoCodigo: 'manter_peso',
        alturaCm: 179,
        sexoBiologico: 'M',
        pesoKg: 78.5,
        problemasSaudeIds: const ['p1', 'p2'],
        alergiaIds: const ['a1'],
        atividades: const [
          AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 1, intensidade: 'alta'),
        ],
      );

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
          {'anamnese_id': 'anamnese-nova', 'atividade_id': 30, 'dia_semana': 1, 'minutos': 45, 'intensidade': 'alta'},
        ]),
      ).called(1);
    });

    test('não chama insert nas tabelas N:N quando as listas vêm vazias', () async {
      stubarUpsertSexo();

      final anamnesesBuilder = builderPara('anamneses');
      when(() => anamnesesBuilder.insert(any())).thenAnswer(
        (_) => _FakeQuery<List<Map<String, dynamic>>>([
          {'id': 'anamnese-nova'},
        ]),
      );

      await repository.salvarAnamnese(
        objetivoCodigo: 'perder_peso',
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
