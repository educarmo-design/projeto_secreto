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
        qualidade: QualidadeMotorResultado(score: 'alta', motivos: []),
        energiaRecomendacao: null,
        macrosRecomendados: null,
        pesoKg: null,
        massaMagraKg: null,
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
        qualidade: QualidadeMotorResultado(score: 'baixa', motivos: ['dados_insuficientes_para_tmb']),
        energiaRecomendacao: null,
        macrosRecomendados: null,
        pesoKg: null,
        massaMagraKg: null,
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
          qualidade: QualidadeMotorResultado(score: 'alta', motivos: []),
          energiaRecomendacao: null,
          macrosRecomendados: null,
          pesoKg: null,
          massaMagraKg: null,
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

  group('Seção A — Qualidade e Recomendação Energética (RELATÓRIO 20260920)', () {
    testWidgets('mostra o badge de qualidade com o motivo e a recomendação energética de déficit', (tester) async {
      when(() => repository.calcularMotorMetabolicoV1()).thenAnswer(
        (_) async => const MotorMetabolicoV1Resultado(
          tmb: 1700,
          tdeeMedio: 2000,
          formulaCodigo: 'TMB-001',
          estrategiaTdee: 'pal',
          avisos: [],
          qualidade: QualidadeMotorResultado(score: 'media', motivos: ['estrategia_fallback_pal']),
          energiaRecomendacao: EnergiaRecomendacaoResultado(
            estrategia: 'deficit_conservador',
            deficitPercentual: 0.12,
            deficitVersao: 'DEFICIT-002-multicriterio-v1',
            recomendacaoMediaDiaria: 1760,
          ),
          macrosRecomendados: null,
          pesoKg: 80,
          massaMagraKg: null,
        ),
      );

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      expect(find.text('Média'), findsOneWidget);
      expect(find.textContaining('Sem detalhamento de atividades'), findsOneWidget);
      expect(find.text('1760 kcal'), findsOneWidget);
      expect(find.textContaining('Déficit de 12%'), findsOneWidget);

      // "Usar este valor em Calorias" copia o valor pro campo — continua editável.
      await tester.tap(find.widgetWithText(TextButton, 'Usar este valor em Calorias'));
      await tester.pump();
      final caloriasField = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      expect(caloriasField.controller?.text, '1760');
    });

    testWidgets('manutenção mostra a descrição correta, sem percentual de déficit', (tester) async {
      when(() => repository.calcularMotorMetabolicoV1()).thenAnswer(
        (_) async => const MotorMetabolicoV1Resultado(
          tmb: 1700,
          tdeeMedio: 2000,
          formulaCodigo: 'TMB-001',
          estrategiaTdee: 'pal',
          avisos: [],
          qualidade: QualidadeMotorResultado(score: 'alta', motivos: []),
          energiaRecomendacao: EnergiaRecomendacaoResultado(
            estrategia: 'manutencao',
            deficitPercentual: null,
            deficitVersao: null,
            recomendacaoMediaDiaria: 2000,
          ),
          macrosRecomendados: null,
          pesoKg: 80,
          massaMagraKg: null,
        ),
      );

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      expect(find.textContaining('Manutenção'), findsOneWidget);
    });
  });

  group('Seção B — Seletor de Protocolos de Macros (RELATÓRIO 20260920, item 3)', () {
    MotorMetabolicoV1Resultado montarResultadoComProtocolos({required bool macro003Disponivel}) {
      return MotorMetabolicoV1Resultado(
        tmb: 1700,
        tdeeMedio: 2000,
        formulaCodigo: 'TMB-001',
        estrategiaTdee: 'pal',
        avisos: const [],
        qualidade: const QualidadeMotorResultado(score: 'alta', motivos: []),
        energiaRecomendacao: null,
        pesoKg: 80,
        massaMagraKg: macro003Disponivel ? 60 : null,
        macrosRecomendados: MacrosRecomendadosResultado(
          energiaAlvo: 2000,
          macro001: const MacroProtocoloResultado(
            versao: 'MACRO-001-default-v1',
            disponivel: true,
            parametros: {'percentual_proteina': 0.25, 'percentual_carboidrato': 0.45, 'percentual_gordura': 0.30},
            proteinaG: 125,
            carboidratoG: 225,
            gorduraG: 66.7,
            validacaoSomaOk: true,
          ),
          macro002: const MacroProtocoloResultado(
            versao: 'MACRO-002-default-v1',
            disponivel: true,
            parametros: {'proteina_g_por_kg': 1.6, 'gordura_g_por_kg': 0.8},
            proteinaG: 128,
            carboidratoG: 228,
            gorduraG: 64,
            validacaoSomaOk: true,
          ),
          macro003: MacroProtocoloResultado(
            versao: 'MACRO-003-default-v1',
            disponivel: macro003Disponivel,
            parametros: macro003Disponivel
                ? const {'proteina_g_por_kg_mlg': 2.0, 'gordura_g_por_kg_peso': 0.8}
                : const {},
            proteinaG: macro003Disponivel ? 120 : null,
            carboidratoG: macro003Disponivel ? 236 : null,
            gorduraG: macro003Disponivel ? 64 : null,
            validacaoSomaOk: macro003Disponivel,
          ),
        ),
      );
    }

    testWidgets('selecionar MACRO-002 converte g/kg em gramas finais e preenche os 3 campos (editáveis)', (tester) async {
      when(() => repository.calcularMotorMetabolicoV1())
          .thenAnswer((_) async => montarResultadoComProtocolos(macro003Disponivel: true));

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '2000');
      await tester.tap(find.widgetWithText(ChoiceChip, 'MACRO-002 · Proteína/gordura g/kg'));
      await tester.pump();

      // Proteína = 80 × 1.6 = 128g; Gordura = 80 × 0.8 = 64g;
      // Carboidrato = (2000 − 128×4 − 64×9) ÷ 4 = 228g.
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1)).controller?.text, '128');
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(2)).controller?.text, '228');
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(3)).controller?.text, '64');

      // Os campos continuam editáveis — o usuário pode sobrescrever livremente.
      await tester.enterText(find.byType(TextFormField).at(1), '999');
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1)).controller?.text, '999');
    });

    testWidgets('trocar Calorias com um protocolo já selecionado recalcula os gramas automaticamente', (tester) async {
      when(() => repository.calcularMotorMetabolicoV1())
          .thenAnswer((_) async => montarResultadoComProtocolos(macro003Disponivel: true));

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '2000');
      await tester.tap(find.widgetWithText(ChoiceChip, 'MACRO-001 · Percentual energético'));
      await tester.pump();
      // 2000 × 0.45 ÷ 4 = 225g de carboidrato.
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(2)).controller?.text, '225');

      await tester.enterText(find.byType(TextFormField).at(0), '2400');
      await tester.pump();
      // 2400 × 0.45 ÷ 4 = 270g.
      expect(tester.widget<TextFormField>(find.byType(TextFormField).at(2)).controller?.text, '270');
    });

    testWidgets('MACRO-003 fica desabilitado quando a massa magra não está disponível', (tester) async {
      when(() => repository.calcularMotorMetabolicoV1())
          .thenAnswer((_) async => montarResultadoComProtocolos(macro003Disponivel: false));

      await configurarViewportAlto(tester);
      await abrirResultado(tester);

      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'MACRO-003 · Proteína por massa magra'));
      expect(chip.onSelected, isNull);
    });
  });
}
