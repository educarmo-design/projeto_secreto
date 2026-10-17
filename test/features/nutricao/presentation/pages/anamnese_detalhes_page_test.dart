import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/anamnese_detalhes_page.dart';

class _MockRepository extends Mock implements AnamneseRepository {}

/// RELATÓRIO 20261016_0005 (item 2) — 100% SOMENTE LEITURA. Nenhum teste
/// deste arquivo procura por um `TextFormField`/`FilledButton` de salvar —
/// a Restrição da tarefa é que esta tela NUNCA tenha um caminho de
/// escrita, então a ausência desses widgets é, em si, parte do contrato.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;

  setUp(() {
    repository = _MockRepository();
  });

  Widget criarApp() {
    return MaterialApp(
      home: AnamneseDetalhesPage(anamneseId: 'anamnese-1', repository: repository),
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
}
