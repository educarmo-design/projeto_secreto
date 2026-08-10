import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
}
