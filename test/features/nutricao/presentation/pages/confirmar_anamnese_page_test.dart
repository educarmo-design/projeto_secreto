import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/confirmar_anamnese_page.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/resultado_motor_metabolico_page.dart';

class _MockRepository extends Mock implements AnamneseRepository {}

class _MockMetaRepository extends Mock implements MetaBemEstarRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(const DadosComplementaresAnamnese());
  });

  late _MockRepository repository;
  late _MockMetaRepository metaRepository;

  const rascunho = AnamneseRascunho(
    objetivoCodigo: 'perder_peso',
    alturaCm: 179,
    sexoBiologico: 'M',
    pesoKg: 78.5,
    idade: 30,
    problemasSaudeSelecionados: [CatalogoItem(id: 'p1', nome: 'Diabetes Tipo 2')],
    alergiasSelecionadas: [CatalogoItem(id: 'a1', nome: 'Intolerância à Lactose')],
    atividades: [
      AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 0, intensidade: 'alta'),
    ],
    complementares: DadosComplementaresAnamnese(possuiCondicaoSaude: true),
  );

  setUp(() {
    repository = _MockRepository();
    metaRepository = _MockMetaRepository();
    when(() => metaRepository.calcularMotorMetabolicoV1()).thenAnswer(
      (_) async => const MotorMetabolicoV1Resultado(
        tmb: 1774,
        tdeeMedio: 2200,
        formulaCodigo: 'TMB-001',
        estrategiaTdee: 'pal',
        avisos: [],
      ),
    );
  });

  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget criarApp() {
    return MaterialApp(
      home: ConfirmarAnamnesePage(rascunho: rascunho, repository: repository, metaRepository: metaRepository),
    );
  }

  testWidgets('mostra o resumo dos dados coletados, ainda sem gravar nada', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Confirme seus dados'), findsOneWidget);
    expect(find.textContaining('Perder peso'), findsOneWidget);
    expect(find.textContaining('78.5 kg'), findsOneWidget);
    expect(find.textContaining('179.0 cm'), findsOneWidget);
    expect(find.textContaining('Diabetes Tipo 2'), findsOneWidget);
    expect(find.textContaining('Intolerância à Lactose'), findsOneWidget);
    verifyNever(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          alturaCm: any(named: 'alturaCm'),
          sexoBiologico: any(named: 'sexoBiologico'),
          pesoKg: any(named: 'pesoKg'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        ));
  });

  testWidgets('"Confirmar e Enviar" grava a anamnese e navega para o Resultado', (tester) async {
    when(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          alturaCm: any(named: 'alturaCm'),
          sexoBiologico: any(named: 'sexoBiologico'),
          pesoKg: any(named: 'pesoKg'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
          complementares: any(named: 'complementares'),
        )).thenAnswer((_) async {});

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar e Enviar'));
    await tester.pumpAndSettle();

    verify(() => repository.salvarAnamnese(
          objetivoCodigo: 'perder_peso',
          alturaCm: 179,
          sexoBiologico: 'M',
          pesoKg: 78.5,
          problemasSaudeIds: ['p1'],
          alergiaIds: ['a1'],
          atividades: rascunho.atividades,
          complementares: rascunho.complementares,
        )).called(1);

    expect(find.byType(ResultadoMotorMetabolicoPage), findsOneWidget);
  });

  testWidgets('falha ao gravar mostra mensagem de erro, não navega', (tester) async {
    when(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          alturaCm: any(named: 'alturaCm'),
          sexoBiologico: any(named: 'sexoBiologico'),
          pesoKg: any(named: 'pesoKg'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
          complementares: any(named: 'complementares'),
        )).thenThrow(Exception('RLS negou'));

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar e Enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Erro ao salvar. Tente novamente.'), findsOneWidget);
    expect(find.byType(ResultadoMotorMetabolicoPage), findsNothing);
  });

  testWidgets('"Voltar e Editar" fecha a tela sem gravar', (tester) async {
    // Precisa de uma tela anterior de verdade na pilha pra `pop()` ter
    // efeito — diferente dos outros testes deste arquivo, que testam
    // ConfirmarAnamnesePage como `home` (raiz, sem pra onde voltar).
    await configurarViewportAlto(tester);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConfirmarAnamnesePage(rascunho: rascunho, repository: repository, metaRepository: metaRepository),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Voltar e Editar'));
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmarAnamnesePage), findsNothing);
    verifyNever(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          alturaCm: any(named: 'alturaCm'),
          sexoBiologico: any(named: 'sexoBiologico'),
          pesoKg: any(named: 'pesoKg'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        ));
  });
}
