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
  });

  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
  });

  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  // O botão "Concluir" faz `Navigator.of(context)..pop()..pop()` (fecha
  // esta tela E a Anamnese embaixo dela, ver o comentário de `_concluir`
  // na própria página) — não testado aqui isoladamente porque exigiria
  // montar uma pilha de 3 rotas só pra isso; comportamento trivial de
  // navegação, coberto pela leitura do código.
  Widget criarApp() {
    return MaterialApp(home: ResultadoMotorMetabolicoPage(repository: repository));
  }

  testWidgets('chama gerar_sugestao_meta e mostra a média + TMB + detalhe por dia + disclaimer exato', (tester) async {
    when(() => repository.gerarSugestaoMeta()).thenAnswer(
      (_) async => const SugestaoMetaResultado(
        tmb: 1774,
        tdeeMedio: 2200,
        tdeePorDia: {0: 2128, 1: 2328, 2: 2328, 3: 2328, 4: 2328, 5: 2328, 6: 2128},
        formulaUsada: 'mifflin_st_jeor',
        avisos: [],
      ),
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('2200 kcal'), findsOneWidget);
    expect(find.text('1774 kcal'), findsOneWidget);
    expect(find.text('Domingo'), findsOneWidget);
    expect(find.text('Sábado'), findsOneWidget);
    expect(
      find.text(
        'Estas informações são meramente informativas, qualquer dúvida ou informações adicionais '
        'deverá procurar um profissional de saúde. Estas informações não são gravadas em sua metas '
        'Calóricas e de Nutrientes.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sem tdee_medio (7 dias incompletos), mostra "—" em vez de inventar um número', (tester) async {
    when(() => repository.gerarSugestaoMeta()).thenAnswer(
      (_) async => const SugestaoMetaResultado(
        tmb: null,
        tdeeMedio: null,
        tdeePorDia: {0: null, 1: null, 2: null, 3: null, 4: null, 5: null, 6: null},
        formulaUsada: 'dados_insuficientes',
        avisos: ['sem_peso'],
      ),
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('—'), findsWidgets);
    expect(find.text('• sem_peso'), findsOneWidget);
  });

  testWidgets('erro ao chamar a RPC mostra mensagem de erro com opção de tentar de novo', (tester) async {
    when(() => repository.gerarSugestaoMeta()).thenThrow(Exception('RLS negou'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível calcular sua sugestão agora. Tente novamente.'), findsOneWidget);
  });
}
