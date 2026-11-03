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
    when(() => repository.buscarHistoricoMetas()).thenAnswer((_) async => const []);
    // RELATÓRIO 20260922_0002 (Item 5) — `null` = sem anamnese vigente,
    // nunca bloqueia por validade nos testes que não são o foco dela.
    when(() => repository.buscarDataValidadeAnamnese()).thenAnswer((_) async => null);
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

  // RELATÓRIO 20261103_0001 — removida a trava client-side de carência
  // (1x/30 dias): o servidor (RPC, por ciclo de anamnese desde o
  // RELATÓRIO 20261102_0003) é o único que decide se a gravação é
  // permitida. A tela mostra "Meta já definida" só informativo, sem
  // bloquear o formulário.
  testWidgets('meta própria criada há menos de 30 dias NÃO bloqueia — mostra "Meta já definida" e o formulário',
      (tester) async {
    await configurarViewportAlto(tester);
    final criadaHa5Dias = DateTime.now().subtract(const Duration(days: 5));
    when(() => repository.buscarMinhaUltimaMetaPropria()).thenAnswer(
      (_) async => MetaResumo(caloriasAlvo: 2200, dataCriacao: criadaHa5Dias),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Meta já definida'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsOneWidget);
  });

  testWidgets('RELATÓRIO 20260922_0002: anamnese vencida há 40+ dias bloqueia a tela, mesmo sem meta prescrita/carência', (tester) async {
    when(() => repository.buscarDataValidadeAnamnese())
        .thenAnswer((_) async => DateTime.now().subtract(const Duration(days: 41)));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Reavaliação vital para sua saúde'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsNothing);
    // Nunca chega a consultar as travas de carência/profissional — o
    // bloqueio de validade é checado ANTES (RELATÓRIO 20260922_0002).
    verifyNever(() => repository.buscarMetaAtivaDoProfissional());
  });

  testWidgets('RELATÓRIO 20260922_0002: anamnese vencida há só 10 dias NÃO bloqueia — mostra o formulário', (tester) async {
    await configurarViewportAlto(tester);
    when(() => repository.buscarDataValidadeAnamnese())
        .thenAnswer((_) async => DateTime.now().subtract(const Duration(days: 10)));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Salvar Meta'), findsOneWidget);
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

  testWidgets('salvar com sucesso mostra snackbar e recarrega', (tester) async {
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

  // RELATÓRIO 20261103_0001 — o servidor ainda pode recusar
  // (N08_CARENCIA_MENSAL) quando a meta é pro MESMO ciclo de anamnese; o
  // modal avisa na hora, mas sem mais repetir a mensagem de "1x por mês".
  testWidgets('carência recusada pelo servidor (N08_CARENCIA_MENSAL) mostra "Meta já definida" sem a mensagem de limitação mensal',
      (tester) async {
    await configurarViewportAlto(tester);
    when(() => repository.salvarMeta(
          caloriasAlvo: any(named: 'caloriasAlvo'),
          proteinaG: any(named: 'proteinaG'),
          carboG: any(named: 'carboG'),
          gorduraG: any(named: 'gorduraG'),
        )).thenThrow(
      MetaBloqueadaException(MotivoBloqueioN08.carenciaMensal, 'N08_CARENCIA_MENSAL: ...'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '2200');
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar Meta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Meta já definida'), findsOneWidget);
    expect(find.textContaining('1x por mês'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Entendi'));
    await tester.pumpAndSettle();
  });

  testWidgets('sem meta própria ainda, mostra "Meta Atual" vazia e histórico vazio no formulário', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Meta Atual (Média)'), findsOneWidget);
    expect(find.text('Você ainda não definiu uma meta.'), findsOneWidget);
    expect(find.text('Histórico de Metas'), findsOneWidget);
    expect(find.text('Nenhuma meta anterior.'), findsOneWidget);
  });

  testWidgets('com meta própria e histórico, mostra a média atual, "Meta já definida" e o histórico rotulado',
      (tester) async {
    when(() => repository.buscarMinhaUltimaMetaPropria()).thenAnswer(
      (_) async => MetaResumo(
        caloriasAlvo: 2200,
        proteinaG: 150,
        dataCriacao: DateTime.now().subtract(const Duration(days: 40)),
        statusVigencia: 'ativo',
      ),
    );
    when(() => repository.buscarHistoricoMetas()).thenAnswer(
      (_) async => [
        MetaResumo(caloriasAlvo: 2200, dataCriacao: DateTime.now().subtract(const Duration(days: 40)), statusVigencia: 'ativo'),
        MetaResumo(caloriasAlvo: 2000, dataCriacao: DateTime.now().subtract(const Duration(days: 70)), statusVigencia: 'historico'),
      ],
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Meta Atual (Média)'), findsOneWidget);
    expect(find.text('Meta já definida'), findsOneWidget);
    expect(find.text('Atual'), findsOneWidget);
    expect(find.text('Anterior'), findsOneWidget);
    expect(find.text('2000 kcal'), findsOneWidget);
  });

  testWidgets('sob acompanhamento profissional, mostra o texto dinâmico exato pedido pelo fundador', (tester) async {
    when(() => repository.buscarMetaAtivaDoProfissional()).thenAnswer(
      (_) async => MetaResumo(caloriasAlvo: 1900, dataCriacao: DateTime(2026, 8, 5)),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(
      find.text('As suas metas são definidas e acompanhadas pelo profissional de saúde.'),
      findsOneWidget,
    );
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
