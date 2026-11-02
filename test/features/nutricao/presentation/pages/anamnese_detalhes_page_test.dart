import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/meta_bem_estar_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/anamnese_detalhes_page.dart';
import 'package:atleta_gamificacao/features/vinculos/data/services/vinculos_service.dart';

class _MockRepository extends Mock implements AnamneseRepository {}

class _MockMetaRepository extends Mock implements MetaBemEstarRepository {}

class _MockVinculosService extends Mock implements VinculosService {}

/// RELATÓRIO 20261016_0005 (item 2) — 100% SOMENTE LEITURA. Nenhum teste
/// deste arquivo procura por um `TextFormField`/`FilledButton` de salvar —
/// a Restrição da tarefa é que esta tela NUNCA tenha um caminho de
/// escrita, então a ausência desses widgets é, em si, parte do contrato
/// (reafirmada pelo RELATÓRIO 20261102_0001, que só adicionou o Plano de
/// Metas — também somente leitura).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;
  late _MockMetaRepository metaRepository;
  late _MockVinculosService vinculosService;

  setUp(() {
    repository = _MockRepository();
    metaRepository = _MockMetaRepository();
    vinculosService = _MockVinculosService();
    // Defaults seguros ("sem próxima anamnese"/"sem meta na janela") —
    // os testes do Plano de Metas sobrescrevem.
    when(() => repository.buscarDataProximaAnamnese(any())).thenAnswer((_) async => null);
    when(() => metaRepository.buscarMetasNoPeriodo(inicio: any(named: 'inicio'), fim: any(named: 'fim')))
        .thenAnswer((_) async => const []);
  });

  Widget criarApp() {
    return MaterialApp(
      home: AnamneseDetalhesPage(
        anamneseId: 'anamnese-1',
        repository: repository,
        metaRepository: metaRepository,
        vinculosService: vinculosService,
      ),
    );
  }

  testWidgets('id não encontrado mostra a mensagem dedicada, não quebra a tela', (tester) async {
    when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => null);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Avaliação não encontrada.'), findsOneWidget);
  });

  testWidgets('erro ao carregar mostra mensagem de erro com botão de tentar novamente', (tester) async {
    when(() => repository.buscarAnamnesePorId('anamnese-1')).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar os detalhes desta avaliação.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tentar novamente'), findsOneWidget);
  });

  testWidgets('mostra dados gerais, físicos e nenhuma seção vazia', (tester) async {
    when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer(
      (_) async => AnamneseDetalheModel(
        id: 'anamnese-1',
        dataPreenchimento: DateTime(2026, 8, 10),
        statusVigencia: 'historico',
        objetivoCodigo: 'perder_peso',
        pesoKg: 80.0,
        alturaCm: 178.0,
        problemasSaudeNomes: const [],
        alergiasNomes: const [],
        atividades: const [],
        medicamentos: const [],
        suplementos: const [],
        exames: const [],
        complementares: const DadosComplementaresAnamnese(),
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('10/08/2026'), findsOneWidget);
    expect(find.text('Perder peso'), findsOneWidget);
    expect(find.text('Anterior'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);
    expect(find.text('178 cm'), findsOneWidget);
    // Nenhum dado complementar/condição/atividade foi preenchido — as
    // seções correspondentes não devem aparecer (Regra 23: omitir, não
    // inventar "—").
    expect(find.text('Condições de Saúde'), findsNothing);
    expect(find.text('Sono'), findsNothing);
    expect(find.text('Metas e Objetivos'), findsNothing);
    // E, acima de tudo: nenhum caminho de escrita nesta tela.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('mostra condições de saúde, atividades e itens repetíveis quando presentes', (tester) async {
    when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer(
      (_) async => AnamneseDetalheModel(
        id: 'anamnese-1',
        dataPreenchimento: DateTime(2026, 8, 10),
        statusVigencia: 'ativo',
        objetivoCodigo: 'ganhar_massa_muscular',
        pesoKg: 80.0,
        alturaCm: 178.0,
        problemasSaudeNomes: const ['Hipertensão'],
        alergiasNomes: const ['Amendoim'],
        atividades: const [
          AtividadeSelecionada(
            atividadeId: 30,
            nomeExibicao: 'Corrida',
            minutos: 45,
            diaSemana: 1,
            intensidade: 'moderada',
          ),
        ],
        medicamentos: const [
          ItemRepetivel(nome: 'Metformina', campos: {'dose': '500', 'unidade': 'mg'}),
        ],
        suplementos: const [],
        exames: const [],
        complementares: const DadosComplementaresAnamnese(),
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Atual'), findsOneWidget);
    expect(find.text('Condições de Saúde'), findsOneWidget);
    expect(find.text('Hipertensão'), findsOneWidget);
    expect(find.text('Amendoim'), findsOneWidget);
    expect(find.text('Atividade Física e Rotina'), findsOneWidget);
    expect(find.text('Corrida — Segunda'), findsOneWidget);
    expect(find.text('45 min · Moderada'), findsOneWidget);
    expect(find.text('Metformina'), findsOneWidget);
  });

  // RELATÓRIO 20261102_0001 — "Plano de Metas" vigente na janela desta
  // anamnese, correlacionado por tempo (sem FK — ver doc da classe).
  group('Plano de Metas (RELATÓRIO 20261102_0001)', () {
    AnamneseDetalheModel detalheBasico({DateTime? dataPreenchimento, String statusVigencia = 'ativo'}) =>
        AnamneseDetalheModel(
          id: 'anamnese-1',
          dataPreenchimento: dataPreenchimento ?? DateTime(2026, 10, 1),
          statusVigencia: statusVigencia,
          objetivoCodigo: 'manter_peso',
          pesoKg: 80.0,
          alturaCm: 178.0,
          problemasSaudeNomes: const [],
          alergiasNomes: const [],
          atividades: const [],
          medicamentos: const [],
          suplementos: const [],
          exames: const [],
          complementares: const DadosComplementaresAnamnese(),
        );

    testWidgets('sem nenhuma meta na janela mostra o aviso de fallback', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheBasico());

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Sem prescrição/cálculo atrelado a este registro.'), findsOneWidget);
    });

    testWidgets('meta única self-service (Motor Metabólico) mostra o card consolidado, sem nome de profissional',
        (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheBasico());
      when(() => metaRepository.buscarMetasNoPeriodo(inicio: any(named: 'inicio'), fim: any(named: 'fim'))).thenAnswer(
        (_) async => [
          MetaResumo(
            caloriasAlvo: 2200,
            proteinaG: 150,
            carboG: 220,
            gorduraG: 70,
            dataCriacao: DateTime(2026, 10, 1),
            tipoDia: 'PADRAO',
          ),
        ],
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Calculado pelo Motor Metabólico'), findsOneWidget);
      expect(find.text('2200 kcal'), findsOneWidget);
      expect(find.text('P 150g · C 220g · G 70g'), findsOneWidget);
      // Meta única — card consolidado direto, sem lista expansível.
      expect(find.byType(ExpansionTile), findsNothing);
      verifyNever(() => vinculosService.buscarNomesProfissionaisVinculados());
    });

    testWidgets('prescrição profissional com metas por dia da semana mostra o badge e a lista expansível por dia',
        (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheBasico());
      when(() => metaRepository.buscarMetasNoPeriodo(inicio: any(named: 'inicio'), fim: any(named: 'fim'))).thenAnswer(
        (_) async => [
          MetaResumo(
            caloriasAlvo: 2400,
            proteinaG: 180,
            carboG: 260,
            gorduraG: 75,
            dataCriacao: DateTime(2026, 10, 1),
            tipoDia: 'TREINO',
            profissionalId: 'prof-1',
          ),
          MetaResumo(
            caloriasAlvo: 1900,
            proteinaG: 160,
            carboG: 150,
            gorduraG: 70,
            dataCriacao: DateTime(2026, 10, 1),
            tipoDia: 'DESCANSO',
            profissionalId: 'prof-1',
          ),
        ],
      );
      when(() => vinculosService.buscarNomesProfissionaisVinculados()).thenAnswer(
        (_) async => {'prof-1': (nickname: 'dra_ana', tipoProfissional: 'Nutricionista')},
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Prescrição Clínica — dra_ana (Nutricionista)'), findsOneWidget);
      expect(find.text('TREINO'), findsOneWidget);
      expect(find.text('DESCANSO'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNWidgets(2));

      // Macros de cada dia só aparecem depois de expandir (ExpansionTile
      // colapsado por padrão) — expande "TREINO" e confirma o conteúdo.
      await tester.tap(find.text('TREINO'));
      await tester.pumpAndSettle();
      expect(find.text('2400 kcal'), findsWidgets);
      expect(find.text('P 180g · C 260g · G 75g'), findsOneWidget);
    });

    testWidgets('anamnese sem próxima (ainda vigente): janela de metas não tem limite superior', (tester) async {
      final dataPreenchimento = DateTime(2026, 10, 1);
      when(() => repository.buscarAnamnesePorId('anamnese-1'))
          .thenAnswer((_) async => detalheBasico(dataPreenchimento: dataPreenchimento));
      when(() => repository.buscarDataProximaAnamnese(dataPreenchimento)).thenAnswer((_) async => null);
      when(() => metaRepository.buscarMetasNoPeriodo(inicio: any(named: 'inicio'), fim: any(named: 'fim'))).thenAnswer(
        (_) async => [
          MetaResumo(caloriasAlvo: 2000, dataCriacao: DateTime(2026, 10, 5)),
        ],
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      verify(() => metaRepository.buscarMetasNoPeriodo(inicio: dataPreenchimento, fim: null)).called(1);
      expect(find.text('2000 kcal'), findsOneWidget);
    });
  });
}
