import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/resultado_motor_metabolico_page.dart';

class _MockRepository extends Mock implements MetaBemEstarRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(0);
  });

  late _MockRepository repository;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    repository = _MockRepository();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // `_fecharFluxo` (botão "Definir depois"/salvar com sucesso) faz DOIS
  // `Navigator.pop()` em sequência — em produção sempre seguro (a tela só
  // existe empilhada sobre a Anamnese, 2 rotas reais). Pra um teste isolado
  // não quebrar com "!_debugLocked" (só 1 rota na pilha), a home vira uma
  // tela "vazia" e cada teste EMPILHA [ResultadoMotorMetabolicoPage] por
  // cima via `navigatorKey`, mesma topologia de 2 rotas da produção.
  Widget criarApp() {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }

  Future<void> abrirResultado(WidgetTester tester) async {
    await tester.pumpWidget(criarApp());
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => ResultadoMotorMetabolicoPage(repository: repository)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('chama calcular_motor_metabolico_v1 e mostra TMB + TDEE médio (Seção A, só leitura) + disclaimer exato', (tester) async {
    when(() => repository.calcularMotorMetabolicoV1()).thenAnswer(
      (_) async => const MotorMetabolicoV1Resultado(
        tmb: 1774,
        tdeeMedio: 2200,
        formulaCodigo: 'TMB-001',
        estrategiaTdee: 'pal',
        avisos: [],
      ),
    );

    await configurarViewportAlto(tester);
    await abrirResultado(tester);

    expect(find.text('Resultados Calculados'), findsOneWidget);
    expect(find.text('2200 kcal'), findsOneWidget);
    expect(find.text('1774 kcal'), findsOneWidget);
    expect(
      find.text(
        'Estas informações são meramente informativas, qualquer dúvida ou informações adicionais '
        'deverá procurar um profissional de saúde. Estas informações não são gravadas em sua metas '
        'Calóricas e de Nutrientes.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sem tdee_medio (dados insuficientes), mostra "—" em vez de inventar um número', (tester) async {
    when(() => repository.calcularMotorMetabolicoV1()).thenAnswer(
      (_) async => const MotorMetabolicoV1Resultado(
        tmb: null,
        tdeeMedio: null,
        formulaCodigo: '—',
        estrategiaTdee: 'pal',
        avisos: ['sem_peso'],
      ),
    );

    await configurarViewportAlto(tester);
    await abrirResultado(tester);

    expect(find.text('—'), findsOneWidget);
    expect(find.text('• sem_peso'), findsOneWidget);
  });

  testWidgets('erro ao chamar a RPC mostra mensagem de erro com opção de tentar de novo', (tester) async {
    when(() => repository.calcularMotorMetabolicoV1()).thenThrow(Exception('RLS negou'));

    await abrirResultado(tester);

    expect(find.text('Não foi possível calcular sua avaliação agora. Tente novamente.'), findsOneWidget);
  });

  group('Seção B — Minha Meta Diária (editável, item 2 da tarefa)', () {
    setUp(() {
      when(() => repository.calcularMotorMetabolicoV1()).thenAnswer(
        (_) async => const MotorMetabolicoV1Resultado(
          tmb: 1774,
          tdeeMedio: 2200,
          formulaCodigo: 'TMB-001',
          estrategiaTdee: 'pal',
          avisos: [],
        ),
      );
    });

    testWidgets('os 4 campos de meta começam EM BRANCO — o app nunca pré-calcula/preenche sozinho', (tester) async {
      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      expect(find.text('Minha Meta Diária'), findsOneWidget);
      for (final campo in tester.widgetList<TextFormField>(find.byType(TextFormField))) {
        expect(campo.controller?.text, isEmpty);
      }
    });

    testWidgets('salvar sem preencher calorias mostra erro de validação, não chama o repositório', (tester) async {
      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar Minha Meta'));
      await tester.pumpAndSettle();

      expect(find.text('Informe a meta de calorias'), findsOneWidget);
      verifyNever(() => repository.salvarMeta(
            caloriasAlvo: any(named: 'caloriasAlvo'),
            proteinaG: any(named: 'proteinaG'),
            carboG: any(named: 'carboG'),
            gorduraG: any(named: 'gorduraG'),
          ));
    });

    testWidgets('preenchendo a meta e salvando, chama salvarMeta com os valores DIGITADOS e fecha o fluxo', (tester) async {
      when(() => repository.salvarMeta(
            caloriasAlvo: any(named: 'caloriasAlvo'),
            proteinaG: any(named: 'proteinaG'),
            carboG: any(named: 'carboG'),
            gorduraG: any(named: 'gorduraG'),
          )).thenAnswer((_) async {});

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      final campos = find.byType(TextFormField);
      await tester.enterText(campos.at(0), '1900');
      await tester.enterText(campos.at(1), '150');
      await tester.enterText(campos.at(2), '180');
      await tester.enterText(campos.at(3), '60');

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar Minha Meta'));
      await tester.pumpAndSettle();

      // Note o valor digitado (1900) é DIFERENTE do TDEE médio calculado
      // (2200) — prova que a meta salva é a que o usuário escreveu, nunca
      // o número que o motor calculou (Restrição da tarefa).
      verify(() => repository.salvarMeta(
            caloriasAlvo: 1900,
            proteinaG: 150,
            carboG: 180,
            gorduraG: 60,
          )).called(1);
      // `_fecharFluxo` (duplo pop) fecha a tela em seguida ao sucesso — a
      // asserção real de "salvou e voltou" é a tela ter saído da pilha
      // (o snackbar em si é transiente demais pra sobreviver ao pop no
      // mesmo ciclo de frame, mesma limitação já documentada nos outros
      // testes desta suíte que usam duplo pop).
      expect(find.byType(ResultadoMotorMetabolicoPage), findsNothing);
    });

    testWidgets('trava clínica (N08_TRAVA_CLINICA) mostra o modal vermelho compartilhado', (tester) async {
      when(() => repository.salvarMeta(
            caloriasAlvo: any(named: 'caloriasAlvo'),
            proteinaG: any(named: 'proteinaG'),
            carboG: any(named: 'carboG'),
            gorduraG: any(named: 'gorduraG'),
          )).thenThrow(
        MetaBloqueadaException(MotivoBloqueioN08.travaClinica, 'N08_TRAVA_CLINICA: ...'),
      );

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '5000');
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar Minha Meta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Meta fora da faixa de segurança'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Entendi'));
      await tester.pumpAndSettle();
    });

    testWidgets('"Definir depois" fecha o fluxo sem chamar salvarMeta', (tester) async {
      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Definir depois'));
      await tester.pumpAndSettle();

      verifyNever(() => repository.salvarMeta(
            caloriasAlvo: any(named: 'caloriasAlvo'),
            proteinaG: any(named: 'proteinaG'),
            carboG: any(named: 'carboG'),
            gorduraG: any(named: 'gorduraG'),
          ));
    });
  });
}
