import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/anamnese_self_service_page.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/confirmar_anamnese_page.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/widgets/seletor_multiplo_bottom_sheet.dart';

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
    TipoAtividadeItem(id: 30, nomeExibicao: 'Corrida', nomeCodigo: 'RUNNING'),
    TipoAtividadeItem(id: 42, nomeExibicao: 'Natação', nomeCodigo: 'SWIMMING'),
  ];
  const dadosFisicosVazios = DadosFisicosAtuais();
  const historicoPesoVazio = HistoricoPeso();

  setUp(() {
    repository = _MockRepository();
    metaRepository = _MockMetaRepository();
    when(() => repository.buscarProblemasSaude()).thenAnswer((_) async => problemasSaude);
    when(() => repository.buscarAlergias()).thenAnswer((_) async => alergias);
    when(() => repository.buscarTiposAtividades()).thenAnswer((_) async => tiposAtividades);
    when(() => repository.buscarAnamneseAtiva()).thenAnswer((_) async => null);
    when(() => repository.buscarDadosFisicosAtuais()).thenAnswer((_) async => dadosFisicosVazios);
    when(() => repository.buscarHistoricoPeso()).thenAnswer((_) async => historicoPesoVazio);
    // RELATÓRIO 20260917 — item 1, "Captura Inteligente": default "nada
    // sincronizado ainda", testes específicos da sugestão sobrescrevem.
    when(() => repository.buscarSugestaoBalanca()).thenAnswer((_) async => const SugestaoBalanca());
  });

  // A tela é um ListView bem longo (RELATÓRIO 20260918_0001 — Blocos 1-12
  // inteiros) — no viewport padrão de teste (800×600) o fim da lista fica
  // além do `cacheExtent` do Sliver e nem chega a ser montado. Aumentar o
  // viewport evita ter que rolar manualmente em cada teste que precisa do
  // botão Salvar/de seções mais abaixo.
  Future<void> configurarViewportAlto(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 9000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget criarApp() {
    return MaterialApp(
      home: AnamneseSelfServicePage(repository: repository, metaRepository: metaRepository),
    );
  }

  testWidgets('carrega os catálogos e mostra as seções principais', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Seus Dados'), findsOneWidget);
    expect(find.text('Objetivo'), findsOneWidget);
    expect(find.text('Alergias'), findsOneWidget);
    expect(find.text('Sono e Recuperação (opcional)'), findsOneWidget);
    expect(find.text('Rotina por Dia da Semana'), findsOneWidget);
    expect(find.text('Domingo'), findsOneWidget);
    expect(find.text('Sábado'), findsOneWidget);
    expect(find.text('Medicamentos (opcional)'), findsOneWidget);
    expect(find.text('Suplementos (opcional)'), findsOneWidget);
    expect(find.text('Exames Laboratoriais (opcional)'), findsOneWidget);
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
        objetivoCodigo: 'ganhar_massa_muscular',
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
        objetivoCodigo: 'ganhar_massa_muscular',
        dataPreenchimento: preenchidaHa40Dias,
        problemasSaudeIds: const ['p1'],
        alergiaIds: const ['a1'],
        atividades: const [
          AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 1, intensidade: 'moderada'),
        ],
      ),
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    final radioObjetivo = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'Ganhar massa muscular'),
    );
    expect(radioObjetivo.value, 'ganhar_massa_muscular');

    // Condições: 1 problema de saúde pré-selecionado marca "possui
    // condição" automaticamente e mostra o resumo com a contagem (a lista
    // em si agora fica num bottom sheet, não mais inline — UX Global,
    // RELATÓRIO 20260918_0001). A alergia pré-selecionada (1) também usa o
    // mesmo texto genérico de resumo — por isso 2, não 1.
    expect(find.text('1 selecionado(s)'), findsNWidgets(2));

    // A atividade pré-preenchida está no dia 1 (Segunda) — precisa expandir
    // a seção daquele dia pra aparecer.
    await tester.tap(find.text('Segunda'));
    await tester.pumpAndSettle();
    expect(find.text('Corrida'), findsOneWidget);
    expect(find.text('45 min · Moderada'), findsOneWidget);
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

  testWidgets('com peso recente da balança, mostra a sugestão e "Confirmar" preenche o campo de peso', (tester) async {
    when(() => repository.buscarSugestaoBalanca()).thenAnswer(
      (_) async => SugestaoBalanca(pesoKg: 82.4, dataReferencia: DateTime(2026, 9, 16)),
    );

    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Dado lido da balança'), findsOneWidget);
    expect(find.text('Peso: 82.4 kg (registrado em 16/09/2026)'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Confirmar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '82.4'), findsOneWidget);
  });

  testWidgets('sem dado recente da balança, não mostra a sugestão', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Dado lido da balança'), findsNothing);
  });

  testWidgets('salvar sem preencher altura/peso mostra erro de validação, não navega para a confirmação', (tester) async {
    await configurarViewportAlto(tester);
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe sua altura'), findsOneWidget);
    expect(find.text('Informe seu peso'), findsOneWidget);
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

  testWidgets(
    'preenchendo tudo, adicionando uma atividade com intensidade e selecionando uma condição, '
    '"Salvar" navega para a Confirmação com o rascunho correto (sem gravar nada ainda)',
    (tester) async {
      await configurarViewportAlto(tester);
      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Altura (cm)'), '179');
      await tester.enterText(find.widgetWithText(TextFormField, 'Peso (kg)'), '78.5');
      await tester.tap(find.widgetWithText(RadioListTile<String>, 'Masculino'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(RadioListTile<String>, 'Perder peso'));
      await tester.pumpAndSettle();

      // Bloco 8 — Condições: "Sim, tenho" abre o resumo, "Editar seleção"
      // abre o bottom sheet, marca e confirma.
      await tester.tap(find.widgetWithText(RadioListTile<bool>, 'Sim, tenho'));
      await tester.pumpAndSettle();
      // 3 seções usam "Editar seleção" nesta tela (objetivos secundários,
      // condições, alergias) — mira especificamente a de condições via o
      // `ResumoSelecaoMultipla` que tem esse rótulo.
      await tester.tap(find.descendant(
        of: find.widgetWithText(ResumoSelecaoMultipla, 'Selecionar condições'),
        matching: find.widgetWithText(TextButton, 'Editar seleção'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Diabetes Tipo 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pumpAndSettle();

      // Atividade no domingo (dia 0), com busca + intensidade alta.
      await tester.tap(find.text('Domingo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Adicionar'));
      await tester.pumpAndSettle();

      // 1º TextField do modal é a busca, 2º são os minutos — mais confiável
      // que casar pelo hint (`find.widgetWithText` não garante achar
      // hintText de forma consistente).
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first,
        'Corr',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<TipoAtividadeItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corrida').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).last,
        '45',
      );
      await tester.tap(find.widgetWithText(RadioListTile<String>, 'Alta'));
      await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
      await tester.pumpAndSettle();

      expect(find.text('Corrida'), findsOneWidget);
      expect(find.text('45 min · Alta'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      // Nada foi gravado ainda — só navegou pra confirmação (Seção 11).
      verifyNever(() => repository.salvarAnamnese(
            objetivoCodigo: any(named: 'objetivoCodigo'),
            alturaCm: any(named: 'alturaCm'),
            sexoBiologico: any(named: 'sexoBiologico'),
            pesoKg: any(named: 'pesoKg'),
            problemasSaudeIds: any(named: 'problemasSaudeIds'),
            alergiaIds: any(named: 'alergiaIds'),
            atividades: any(named: 'atividades'),
          ));

      expect(find.byType(ConfirmarAnamnesePage), findsOneWidget);
      final confirmarPage = tester.widget<ConfirmarAnamnesePage>(find.byType(ConfirmarAnamnesePage));
      expect(confirmarPage.rascunho.objetivoCodigo, 'perder_peso');
      expect(confirmarPage.rascunho.alturaCm, 179);
      expect(confirmarPage.rascunho.pesoKg, 78.5);
      expect(confirmarPage.rascunho.sexoBiologico, 'M');
      expect(confirmarPage.rascunho.problemasSaudeSelecionados.map((e) => e.id), ['p1']);
      expect(confirmarPage.rascunho.atividades, [
        const AtividadeSelecionada(atividadeId: 30, nomeExibicao: 'Corrida', minutos: 45, diaSemana: 0, intensidade: 'alta'),
      ]);
    },
  );
}
