import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/anamnese_self_service_page.dart';

class _MockRepository extends Mock implements AnamneseRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;

  const problemasSaude = [CatalogoItem(id: 'p1', nome: 'Diabetes Tipo 2')];
  const alergias = [CatalogoItem(id: 'a1', nome: 'Intolerância à Lactose')];
  const tiposAtividades = [
    TipoAtividadeItem(id: 30, nomeExibicao: 'Corrida'),
    TipoAtividadeItem(id: 42, nomeExibicao: 'Natação'),
  ];

  setUp(() {
    repository = _MockRepository();
    when(() => repository.buscarProblemasSaude()).thenAnswer((_) async => problemasSaude);
    when(() => repository.buscarAlergias()).thenAnswer((_) async => alergias);
    when(() => repository.buscarTiposAtividades()).thenAnswer((_) async => tiposAtividades);
    when(() => repository.buscarAnamneseAtiva()).thenAnswer((_) async => null);
  });

  // A tela é um ListView longo (Objetivo + catálogos + Rotina de
  // Atividades + botão Salvar) — no viewport padrão de teste (800×600) o
  // fim da lista fica além do `cacheExtent` do Sliver e nem chega a ser
  // montado (não é só "fora da tela visível", literalmente não existe
  // Element pra encontrar). Aumentar o viewport evita ter que rolar
  // manualmente em cada teste que precisa do botão Salvar/do modal.
  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget criarApp() {
    return MaterialApp(
      home: AnamneseSelfServicePage(repository: repository),
    );
  }

  testWidgets('carrega os catálogos e mostra as seções', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Objetivo'), findsOneWidget);
    expect(find.text('Diabetes Tipo 2'), findsOneWidget);
    expect(find.text('Intolerância à Lactose'), findsOneWidget);
    expect(find.text('Nenhuma atividade adicionada ainda.'), findsOneWidget);
  });

  testWidgets('erro ao carregar mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarProblemasSaude()).thenThrow(Exception('sem rede'));

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar. Tente novamente.'), findsOneWidget);
  });

  testWidgets('pré-preenche com a anamnese ativa quando existe uma', (tester) async {
    when(() => repository.buscarAnamneseAtiva()).thenAnswer(
      (_) async => const AnamneseAtiva(
        objetivoCodigo: 'hipertrofia',
        problemasSaudeIds: ['p1'],
        alergiaIds: ['a1'],
        atividades: [AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutosDiarios: 45)],
      ),
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    final radioHipertrofia = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'Hipertrofia'),
    );
    expect(radioHipertrofia.value, 'hipertrofia');

    final checkboxDiabetes = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Diabetes Tipo 2'),
    );
    expect(checkboxDiabetes.value, isTrue);

    expect(find.text('Corrida'), findsOneWidget);
    expect(find.text('45 min/dia'), findsOneWidget);
  });

  testWidgets('salvar sem escolher objetivo mostra erro de validação, não chama o repositório', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Escolha um objetivo antes de salvar'), findsOneWidget);
    verifyNever(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        ));
  });

  testWidgets('adicionar uma atividade pelo modal e salvar chama o repositório com os dados certos', (tester) async {
    when(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        )).thenAnswer((_) async {});

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    // Objetivo
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Emagrecimento'));
    await tester.pumpAndSettle();

    // Problema de saúde + alergia
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Diabetes Tipo 2'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Intolerância à Lactose'));
    await tester.pumpAndSettle();

    // Atividade via modal
    await tester.tap(find.widgetWithText(OutlinedButton, 'Adicionar Atividade'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<TipoAtividadeItem>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corrida').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(find.text('Corrida'), findsOneWidget);
    expect(find.text('45 min/dia'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    verify(() => repository.salvarAnamnese(
          objetivoCodigo: 'emagrecimento',
          problemasSaudeIds: ['p1'],
          alergiaIds: ['a1'],
          atividades: [
            const AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutosDiarios: 45),
          ],
        )).called(1);
    expect(find.text('Anamnese salva com sucesso'), findsOneWidget);
  });

  testWidgets('falha ao salvar mostra mensagem de erro', (tester) async {
    when(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        )).thenThrow(Exception('RLS negou'));

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Manutenção'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Erro ao salvar. Tente novamente.'), findsOneWidget);
  });
}
