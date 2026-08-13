import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/meta_bem_estar_page.dart';

class _MockRepository extends Mock implements MetaBemEstarRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
    // Defaults "caminho livre" — sem meta prescrita, sem carência — pra
    // não obrigar cada teste a stubar os dois quando não é o foco dele.
    when(() => repository.buscarMetaAtivaDoProfissional()).thenAnswer((_) async => null);
    when(() => repository.buscarMinhaUltimaMetaPropria()).thenAnswer((_) async => null);
    when(() => repository.buscarSugestaoCalorias()).thenAnswer((_) async => null);
  });

  Widget criarApp() {
    return MaterialApp(
      home: MetaBemEstarPage(repository: repository),
    );
  }

  // A tela tem um `ListView` (formulário) que passa da viewport padrão de
  // teste (800×600) — mesmo ajuste já usado em
  // `anamnese_self_service_page_test.dart`.
  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('sem meta prescrita e sem carência, mostra o formulário', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsOneWidget);
  });

  testWidgets('com sugestão de calorias, mostra o botão de usar sugestão e preenche o campo ao tocar', (tester) async {
    await configurarViewportAlto(tester);
    when(() => repository.buscarSugestaoCalorias()).thenAnswer((_) async => 2128.8);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Usar sugestão: 2129 kcal'), findsOneWidget);

    await tester.tap(find.text('Usar sugestão: 2129 kcal'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '2129'), findsOneWidget);
  });

  testWidgets('meta prescrita ativa bloqueia a tela e mostra os valores dela', (tester) async {
    when(() => repository.buscarMetaAtivaDoProfissional()).thenAnswer(
      (_) async => MetaResumo(
        caloriasAlvo: 1900,
        proteinaG: 160,
        carboG: 180,
        gorduraG: 60,
        dataCriacao: DateTime(2026, 8, 5),
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Você está sob acompanhamento profissional'), findsOneWidget);
    expect(find.text('1900 kcal'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsNothing);
  });

  testWidgets('meta própria criada há menos de 30 dias bloqueia a tela por carência', (tester) async {
    final criadaHa5Dias = DateTime.now().subtract(const Duration(days: 5));
    when(() => repository.buscarMinhaUltimaMetaPropria()).thenAnswer(
      (_) async => MetaResumo(caloriasAlvo: 2200, dataCriacao: criadaHa5Dias),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Meta já definida este mês'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsNothing);
  });

  testWidgets('meta própria criada há mais de 30 dias NÃO bloqueia — mostra o formulário', (tester) async {
    await configurarViewportAlto(tester);
    final criadaHa40Dias = DateTime.now().subtract(const Duration(days: 40));
    when(() => repository.buscarMinhaUltimaMetaPropria()).thenAnswer(
      (_) async => MetaResumo(caloriasAlvo: 2200, dataCriacao: criadaHa40Dias),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsOneWidget);
  });

  testWidgets('salvar com sucesso mostra snackbar e recarrega (vira bloqueadaCarencia)', (tester) async {
    await configurarViewportAlto(tester);
    when(() => repository.salvarMeta(
          caloriasAlvo: any(named: 'caloriasAlvo'),
          proteinaG: any(named: 'proteinaG'),
          carboG: any(named: 'carboG'),
          gorduraG: any(named: 'gorduraG'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '2200');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar Meta'));
    await tester.pumpAndSettle();

    expect(find.text('Meta salva com sucesso'), findsOneWidget);
    verify(() => repository.salvarMeta(
          caloriasAlvo: 2200,
          proteinaG: null,
          carboG: null,
          gorduraG: null,
        )).called(1);
  });

  testWidgets('trava clínica (N08_TRAVA_CLINICA) mostra o modal vermelho de bloqueio', (tester) async {
    await configurarViewportAlto(tester);
    when(() => repository.salvarMeta(
          caloriasAlvo: any(named: 'caloriasAlvo'),
          proteinaG: any(named: 'proteinaG'),
          carboG: any(named: 'carboG'),
          gorduraG: any(named: 'gorduraG'),
        )).thenThrow(
      MetaBloqueadaException(MotivoBloqueioN08.travaClinica, 'N08_TRAVA_CLINICA: ...'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '5000');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar Meta'));
    // Não usa pumpAndSettle: o modal fica aberto esperando o usuário
    // dispensar (CircularProgressIndicator do botão continuaria animando
    // enquanto isso, o que faz pumpAndSettle nunca convergir).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Meta fora da faixa de segurança'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Entendi'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Entendi'));
    await tester.pumpAndSettle();
  });

  testWidgets('calorias vazias mostram erro de validação, não chamam o repositório', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar Meta'));
    await tester.pumpAndSettle();

    expect(find.text('Informe a meta de calorias'), findsOneWidget);
    verifyNever(() => repository.salvarMeta(
          caloriasAlvo: any(named: 'caloriasAlvo'),
          proteinaG: any(named: 'proteinaG'),
          carboG: any(named: 'carboG'),
          gorduraG: any(named: 'gorduraG'),
        ));
  });
}
