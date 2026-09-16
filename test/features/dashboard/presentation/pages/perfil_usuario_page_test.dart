import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/repositories/perfil_usuario_repository.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/pages/perfil_usuario_page.dart';

class _MockRepository extends Mock implements PerfilUsuarioRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(SexoBiologico.masculino);
  });

  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
    // RELATÓRIO 20260916_0001 (SSOT) — `_carregar` sempre busca a altura
    // da última anamnese, data de nascimento, sexo biológico e o último
    // peso sincronizado; defaults "sem dado" pra não quebrar os testes que
    // não mexem com um campo específico (mocktail lança MissingStubError
    // pra chamada não-stubada, não devolve null sozinho).
    when(() => repository.buscarAlturaCmDaUltimaAnamnese()).thenAnswer((_) async => null);
    when(() => repository.buscarDataNascimento()).thenAnswer((_) async => null);
    when(() => repository.buscarSexoBiologico()).thenAnswer((_) async => null);
    when(() => repository.buscarUltimoPesoKg()).thenAnswer((_) async => null);
  });

  Widget criarApp() {
    return MaterialApp(
      home: PerfilUsuarioPage(repository: repository),
    );
  }

  testWidgets('carrega a altura da última anamnese e mostra somente leitura', (tester) async {
    when(() => repository.buscarAlturaCmDaUltimaAnamnese()).thenAnswer((_) async => 179.0);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('179 cm'), findsOneWidget);
    // Não é mais editável — nenhum TextFormField na tela.
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('sem altura registrada ainda, mostra a dica pra preencher uma Anamnese', (tester) async {
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Nenhuma altura registrada ainda — preencha uma Anamnese para informar.'),
      findsOneWidget,
    );
  });

  testWidgets('erro ao carregar mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarAlturaCmDaUltimaAnamnese()).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar seus dados. Tente novamente.'), findsOneWidget);
  });

  // N03 (RELATÓRIO 20260811_0005).
  group('data de nascimento (N03)', () {
    testWidgets('carrega a data já cadastrada e mostra formatada', (tester) async {
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => DateTime(2000, 5, 20));

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('20/05/2000'), findsOneWidget);
    });

    testWidgets('sem data cadastrada, mostra a dica "Toque para escolher"', (tester) async {
      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Toque para escolher'), findsOneWidget);
    });

    testWidgets('salvar com data de nascimento carregada (maior de idade) persiste a data', (tester) async {
      final dataMaiorDeIdade = DateTime.now().subtract(const Duration(days: 365 * 25));
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => dataMaiorDeIdade);
      when(() => repository.atualizarDataNascimento(any())).thenAnswer((_) async {});

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      verify(() => repository.atualizarDataNascimento(dataMaiorDeIdade)).called(1);
      expect(find.text('Salvo com sucesso'), findsOneWidget);
    });

    testWidgets('data de nascimento de menor de idade bloqueia o salvamento com erro, sem chamar o repositório', (tester) async {
      final dataMenorDeIdade = DateTime.now().subtract(const Duration(days: 365 * 15));
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => dataMenorDeIdade);

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(
        find.text('É necessário ter 18 anos ou mais para usar o aplicativo.'),
        findsOneWidget,
      );
      verifyNever(() => repository.atualizarDataNascimento(any()));
    });

    testWidgets('CHECK constraint do banco recusando a data mostra a mesma mensagem amigável', (tester) async {
      // Zero Trust: mesmo que a validação client-side tenha, por algum
      // motivo, deixado passar, a barreira real é a CHECK constraint
      // `perfis_usuarios_maioridade` — o PostgrestException dela deve
      // virar a mesma mensagem amigável, não o erro genérico.
      final dataMaiorDeIdade = DateTime.now().subtract(const Duration(days: 365 * 25));
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => dataMaiorDeIdade);
      when(() => repository.atualizarDataNascimento(any())).thenThrow(
        const PostgrestException(
          message:
              'new row for relation "perfis_usuarios" violates check constraint "perfis_usuarios_maioridade"',
        ),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(
        find.text('É necessário ter 18 anos ou mais para usar o aplicativo.'),
        findsOneWidget,
      );
    });
  });

  // N07 (RELATÓRIO 20260812_0008).
  group('sexo biológico (N07)', () {
    testWidgets('carrega o sexo já cadastrado e marca o RadioListTile certo', (tester) async {
      when(() => repository.buscarSexoBiologico()).thenAnswer((_) async => SexoBiologico.feminino);

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      final radioFeminino = tester.widget<RadioListTile<SexoBiologico>>(
        find.widgetWithText(RadioListTile<SexoBiologico>, 'Feminino'),
      );
      expect(radioFeminino.value, SexoBiologico.feminino);
    });

    testWidgets('salvar com sexo biológico escolhido chama o repositório', (tester) async {
      when(() => repository.atualizarSexoBiologico(any())).thenAnswer((_) async {});

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(RadioListTile<SexoBiologico>, 'Masculino'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      verify(() => repository.atualizarSexoBiologico(SexoBiologico.masculino)).called(1);
      expect(find.text('Salvo com sucesso'), findsOneWidget);
    });

    testWidgets('sem sexo biológico escolhido, salvar não chama atualizarSexoBiologico', (tester) async {
      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      verifyNever(() => repository.atualizarSexoBiologico(any()));
      expect(find.text('Salvo com sucesso'), findsOneWidget);
    });

    testWidgets('falha ao salvar mostra mensagem de erro', (tester) async {
      when(() => repository.atualizarSexoBiologico(any())).thenThrow(Exception('RLS negou'));

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(RadioListTile<SexoBiologico>, 'Masculino'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Erro ao salvar. Tente novamente.'), findsOneWidget);
    });
  });

  // RELATÓRIO 20260812_0011 — auditoria do bug "IMC não calcula". RELATÓRIO
  // 20260916_0001: altura não é mais digitada nesta tela — o IMC usa a
  // altura carregada da última anamnese direto, sem recalcular "ao vivo"
  // por dígito (não há mais campo pra digitar).
  group('IMC', () {
    testWidgets('sem peso sincronizado, mostra a dica pra sincronizar o wearable', (tester) async {
      when(() => repository.buscarAlturaCmDaUltimaAnamnese()).thenAnswer((_) async => 179.0);

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(
        find.text('Sincronize seu peso pelo wearable para ver o IMC estimado aqui.'),
        findsOneWidget,
      );
    });

    testWidgets('com peso sincronizado mas sem altura na anamnese, mostra a dica de altura', (tester) async {
      when(() => repository.buscarUltimoPesoKg()).thenAnswer(
        (_) async => PesoRecente(pesoKg: 80.6, dataReferencia: DateTime(2026, 8, 10)),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Informe uma altura válida para calcular o IMC.'), findsOneWidget);
    });

    testWidgets('com peso e altura, calcula e mostra o IMC (peso / altura_m²)', (tester) async {
      when(() => repository.buscarAlturaCmDaUltimaAnamnese()).thenAnswer((_) async => 178.0);
      when(() => repository.buscarUltimoPesoKg()).thenAnswer(
        (_) async => PesoRecente(pesoKg: 80.0, dataReferencia: DateTime(2026, 8, 10)),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      // 80 / 1.78² = 25.25...
      expect(find.text('IMC estimado: 25.2 (baseado no peso de 10/08/2026)'), findsOneWidget);
    });
  });
}
