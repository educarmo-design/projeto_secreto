import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/anamnese_self_service_page.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/resultado_motor_metabolico_page.dart';

class _MockRepository extends Mock implements AnamneseRepository {}

class _MockMetaRepository extends Mock implements MetaBemEstarRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;
  late _MockMetaRepository metaRepository;

  const problemasSaude = [CatalogoItem(id: 'p1', nome: 'Diabetes Tipo 2')];
  const alergias = [CatalogoItem(id: 'a1', nome: 'Intolerância à Lactose')];
  const tiposAtividades = [
    TipoAtividadeItem(id: 30, nomeExibicao: 'Corrida'),
    TipoAtividadeItem(id: 42, nomeExibicao: 'Natação'),
  ];
  const dadosFisicosVazios = DadosFisicosAtuais();

  setUp(() {
    repository = _MockRepository();
    metaRepository = _MockMetaRepository();
    when(() => repository.buscarProblemasSaude()).thenAnswer((_) async => problemasSaude);
    when(() => repository.buscarAlergias()).thenAnswer((_) async => alergias);
    when(() => repository.buscarTiposAtividades()).thenAnswer((_) async => tiposAtividades);
    when(() => repository.buscarAnamneseAtiva()).thenAnswer((_) async => null);
    when(() => repository.buscarDadosFisicosAtuais()).thenAnswer((_) async => dadosFisicosVazios);
    // A tela pusha ResultadoMotorMetabolicoPage após salvar — stub padrão
    // pra testes que chegam a tocar "Salvar" não baterem no Supabase real
    // (a página de resultado é só mockada aqui, não é o foco destes
    // testes, que ficam em `resultado_motor_metabolico_page_test.dart`).
    when(() => metaRepository.gerarSugestaoMeta()).thenAnswer(
      (_) async => const SugestaoMetaResultado(
        tmb: 1774,
        tdeeMedio: 2200,
        tdeePorDia: {0: 2200, 1: 2200, 2: 2200, 3: 2200, 4: 2200, 5: 2200, 6: 2200},
        formulaUsada: 'mifflin_st_jeor',
        avisos: [],
      ),
    );
  });

  // A tela é um ListView longo (Dados Físicos + Objetivo + catálogos +
  // Rotina por Dia da Semana com 7 seções + botão Salvar) — no viewport
  // padrão de teste (800×600) o fim da lista fica além do `cacheExtent` do
  // Sliver e nem chega a ser montado. Aumentar o viewport evita ter que
  // rolar manualmente em cada teste que precisa do botão Salvar/do modal.
  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget criarApp() {
    return MaterialApp(
      home: AnamneseSelfServicePage(repository: repository, metaRepository: metaRepository),
    );
  }

  testWidgets('carrega os catálogos e mostra as seções', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Seus Dados'), findsOneWidget);
    expect(find.text('Objetivo'), findsOneWidget);
    expect(find.text('Diabetes Tipo 2'), findsOneWidget);
    expect(find.text('Intolerância à Lactose'), findsOneWidget);
    expect(find.text('Rotina por Dia da Semana'), findsOneWidget);
    expect(find.text('Domingo'), findsOneWidget);
    expect(find.text('Sábado'), findsOneWidget);
  });

  testWidgets('erro ao carregar mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarProblemasSaude()).thenThrow(Exception('sem rede'));

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar. Tente novamente.'), findsOneWidget);
  });

  testWidgets('trava de 30 dias: anamnese preenchida há menos de 30 dias bloqueia a tela', (tester) async {
    final preenchidaHa5Dias = DateTime.now().subtract(const Duration(days: 5));
    when(() => repository.buscarAnamneseAtiva()).thenAnswer(
      (_) async => AnamneseAtiva(
        objetivoCodigo: 'hipertrofia',
        dataPreenchimento: preenchidaHa5Dias,
        problemasSaudeIds: const [],
        alergiaIds: const [],
        atividades: const [],
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Anamnese já preenchida recentemente'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Salvar'), findsNothing);
  });

  testWidgets('anamnese preenchida há mais de 30 dias NÃO bloqueia — mostra o formulário pré-preenchido', (tester) async {
    final preenchidaHa40Dias = DateTime.now().subtract(const Duration(days: 40));
    when(() => repository.buscarAnamneseAtiva()).thenAnswer(
      (_) async => AnamneseAtiva(
        objetivoCodigo: 'hipertrofia',
        dataPreenchimento: preenchidaHa40Dias,
        problemasSaudeIds: const ['p1'],
        alergiaIds: const ['a1'],
        atividades: const [
          AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 1),
        ],
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

    // A atividade pré-preenchida está no dia 1 (Segunda) — precisa expandir
    // a seção daquele dia pra aparecer.
    await tester.tap(find.text('Segunda'));
    await tester.pumpAndSettle();
    expect(find.text('Corrida'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
  });

  testWidgets('pré-preenche altura/sexo/peso quando já existem', (tester) async {
    when(() => repository.buscarDadosFisicosAtuais()).thenAnswer(
      (_) async => const DadosFisicosAtuais(alturaCm: 179, sexoBiologico: 'M', pesoKg: 78.5),
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '179'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '78.5'), findsOneWidget);
    final radioMasculino = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'Masculino'),
    );
    expect(radioMasculino.value, 'M');
  });

  testWidgets('salvar sem preencher altura/peso mostra erro de validação, não chama o repositório', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe sua altura'), findsOneWidget);
    expect(find.text('Informe seu peso'), findsOneWidget);
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

  testWidgets('preenchendo tudo, adicionando uma atividade num dia e salvando, chama o repositório e abre o resultado', (tester) async {
    when(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          alturaCm: any(named: 'alturaCm'),
          sexoBiologico: any(named: 'sexoBiologico'),
          pesoKg: any(named: 'pesoKg'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        )).thenAnswer((_) async {});

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Altura (cm)'), '179');
    await tester.enterText(find.widgetWithText(TextFormField, 'Peso (kg)'), '78.5');
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Masculino'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Emagrecimento'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Diabetes Tipo 2'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Intolerância à Lactose'));
    await tester.pumpAndSettle();

    // Atividade no domingo (dia 0), via o botão "Adicionar" da 1ª seção.
    await tester.tap(find.text('Domingo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Adicionar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<TipoAtividadeItem>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corrida').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      '45',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(find.text('Corrida'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    verify(() => repository.salvarAnamnese(
          objetivoCodigo: 'emagrecimento',
          alturaCm: 179,
          sexoBiologico: 'M',
          pesoKg: 78.5,
          problemasSaudeIds: ['p1'],
          alergiaIds: ['a1'],
          atividades: [
            const AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 0),
          ],
        )).called(1);

    // Navegou para a Tela de Resultado do Motor Metabólico.
    expect(find.byType(ResultadoMotorMetabolicoPage), findsOneWidget);
  });

  testWidgets('falha ao salvar mostra mensagem de erro, não navega', (tester) async {
    when(() => repository.salvarAnamnese(
          objetivoCodigo: any(named: 'objetivoCodigo'),
          alturaCm: any(named: 'alturaCm'),
          sexoBiologico: any(named: 'sexoBiologico'),
          pesoKg: any(named: 'pesoKg'),
          problemasSaudeIds: any(named: 'problemasSaudeIds'),
          alergiaIds: any(named: 'alergiaIds'),
          atividades: any(named: 'atividades'),
        )).thenThrow(Exception('RLS negou'));

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Altura (cm)'), '179');
    await tester.enterText(find.widgetWithText(TextFormField, 'Peso (kg)'), '78.5');
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Feminino'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Manutenção'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Erro ao salvar. Tente novamente.'), findsOneWidget);
    expect(find.byType(ResultadoMotorMetabolicoPage), findsNothing);
  });
}
