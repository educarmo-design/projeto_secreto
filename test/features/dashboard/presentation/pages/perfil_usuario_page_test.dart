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
  });

  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
    // N03 — `_carregar` sempre busca a data de nascimento junto com a
    // altura; default "sem data cadastrada" pra não quebrar os testes de
    // altura que não mexem com esse campo (mocktail lança MissingStubError
    // pra chamada não-stubada, não devolve null sozinho).
    when(() => repository.buscarDataNascimento()).thenAnswer((_) async => null);
  });

  Widget criarApp() {
    return MaterialApp(
      home: PerfilUsuarioPage(repository: repository),
    );
  }

  testWidgets('carrega a altura já cadastrada e preenche o campo', (tester) async {
    when(() => repository.buscarAlturaCm()).thenAnswer((_) async => 179.0);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '179'), findsOneWidget);
  });

  testWidgets('sem altura cadastrada, campo abre vazio (não é erro)', (tester) async {
    when(() => repository.buscarAlturaCm()).thenAnswer((_) async => null);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar seus dados. Tente novamente.'), findsNothing);
    final campo = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(campo.controller?.text, isEmpty);
  });

  testWidgets('erro ao carregar mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarAlturaCm()).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar seus dados. Tente novamente.'), findsOneWidget);
  });

  testWidgets('salvar com altura válida chama o repositório e mostra "Salvo com sucesso"', (tester) async {
    when(() => repository.buscarAlturaCm()).thenAnswer((_) async => null);
    when(() => repository.atualizarAlturaCm(any())).thenAnswer((_) async {});

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '179');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    verify(() => repository.atualizarAlturaCm(179.0)).called(1);
    expect(find.text('Salvo com sucesso'), findsOneWidget);
  });

  testWidgets('impede letras: campo vazio ao salvar mostra erro de validação, não chama o repositório', (tester) async {
    when(() => repository.buscarAlturaCm()).thenAnswer((_) async => null);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe sua altura'), findsOneWidget);
    verifyNever(() => repository.atualizarAlturaCm(any()));
  });

  testWidgets('altura fora da faixa plausível (50–250cm) mostra erro de validação', (tester) async {
    when(() => repository.buscarAlturaCm()).thenAnswer((_) async => null);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '1790');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Altura deve estar entre 50 e 250 cm'), findsOneWidget);
    verifyNever(() => repository.atualizarAlturaCm(any()));
  });

  testWidgets('falha ao salvar mostra mensagem de erro', (tester) async {
    when(() => repository.buscarAlturaCm()).thenAnswer((_) async => null);
    when(() => repository.atualizarAlturaCm(any())).thenThrow(Exception('RLS negou'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '179');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Erro ao salvar. Tente novamente.'), findsOneWidget);
  });

  // N03 (RELATÓRIO 20260811_0005).
  group('data de nascimento (N03)', () {
    testWidgets('carrega a data já cadastrada e mostra formatada', (tester) async {
      when(() => repository.buscarAlturaCm()).thenAnswer((_) async => 179.0);
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => DateTime(2000, 5, 20));

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('20/05/2000'), findsOneWidget);
    });

    testWidgets('sem data cadastrada, mostra a dica "Toque para escolher"', (tester) async {
      when(() => repository.buscarAlturaCm()).thenAnswer((_) async => null);

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Toque para escolher'), findsOneWidget);
    });

    testWidgets('salvar com data de nascimento carregada (maior de idade) persiste a data', (tester) async {
      final dataMaiorDeIdade = DateTime.now().subtract(const Duration(days: 365 * 25));
      when(() => repository.buscarAlturaCm()).thenAnswer((_) async => 179.0);
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => dataMaiorDeIdade);
      when(() => repository.atualizarAlturaCm(any())).thenAnswer((_) async {});
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
      when(() => repository.buscarAlturaCm()).thenAnswer((_) async => 179.0);
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
      verifyNever(() => repository.atualizarAlturaCm(any()));
      verifyNever(() => repository.atualizarDataNascimento(any()));
    });

    testWidgets('CHECK constraint do banco recusando a data mostra a mesma mensagem amigável', (tester) async {
      // Zero Trust: mesmo que a validação client-side tenha, por algum
      // motivo, deixado passar, a barreira real é a CHECK constraint
      // `perfis_usuarios_maioridade` — o PostgrestException dela deve
      // virar a mesma mensagem amigável, não o erro genérico.
      final dataMaiorDeIdade = DateTime.now().subtract(const Duration(days: 365 * 25));
      when(() => repository.buscarAlturaCm()).thenAnswer((_) async => 179.0);
      when(() => repository.buscarDataNascimento())
          .thenAnswer((_) async => dataMaiorDeIdade);
      when(() => repository.atualizarAlturaCm(any())).thenAnswer((_) async {});
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
}
