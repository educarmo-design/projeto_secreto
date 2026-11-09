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
    // Default seguro ("sem meta atrelada a esta anamnese") — os testes do
    // Plano de Metas sobrescrevem.
    when(() => metaRepository.buscarMetasPorAnamneseId(any())).thenAnswer((_) async => const []);
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

  // RELATÓRIO 20261102_0002 — "Plano de Metas" atrelado a esta anamnese,
  // correlacionado por FK direta (anamnese_id), nunca mais por tempo (ver
  // doc da classe).
  group('Plano de Metas (RELATÓRIO 20261102_0002)', () {
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

    testWidgets('sem nenhuma meta atrelada (anamnese_id) mostra o aviso de fallback', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheBasico());

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Sem prescrição/cálculo atrelado a este registro.'), findsOneWidget);
    });

    testWidgets('meta única self-service (Motor Metabólico) mostra o card consolidado, sem nome de profissional',
        (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheBasico());
      when(() => metaRepository.buscarMetasPorAnamneseId('anamnese-1')).thenAnswer(
        (_) async => [
          MetaResumo(
            caloriasAlvo: 2200,
            proteinaG: 150,
            carboG: 220,
            gorduraG: 70,
            dataCriacao: DateTime(2026, 10, 1),
            tipoDia: 'PADRAO',
            anamneseId: 'anamnese-1',
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
      when(() => metaRepository.buscarMetasPorAnamneseId('anamnese-1')).thenAnswer(
        (_) async => [
          MetaResumo(
            caloriasAlvo: 2400,
            proteinaG: 180,
            carboG: 260,
            gorduraG: 75,
            dataCriacao: DateTime(2026, 10, 1),
            tipoDia: 'TREINO',
            profissionalId: 'prof-1',
            anamneseId: 'anamnese-1',
          ),
          MetaResumo(
            caloriasAlvo: 1900,
            proteinaG: 160,
            carboG: 150,
            gorduraG: 70,
            dataCriacao: DateTime(2026, 10, 1),
            tipoDia: 'DESCANSO',
            profissionalId: 'prof-1',
            anamneseId: 'anamnese-1',
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

    testWidgets('busca a meta exclusivamente pelo anamneseId (FK direta) — nunca por data', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheBasico());
      when(() => metaRepository.buscarMetasPorAnamneseId('anamnese-1')).thenAnswer(
        (_) async => [
          MetaResumo(caloriasAlvo: 2000, dataCriacao: DateTime(2026, 10, 5), anamneseId: 'anamnese-1'),
        ],
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      verify(() => metaRepository.buscarMetasPorAnamneseId('anamnese-1')).called(1);
      expect(find.text('2000 kcal'), findsOneWidget);
    });
  });

  // RELATÓRIO 20261103_0001 (item 3) — "ao final da tela de detalhes,
  // exibição completa dos resultados do Motor Metabólico". Lido de
  // `anamneses.resultado_motor_v1` (snapshot do RELATÓRIO 20260917_0001),
  // nunca recalculado por esta tela.
  group('Resultado do Motor Metabólico (RELATÓRIO 20261103_0001)', () {
    AnamneseDetalheModel detalheComMotor(Map<String, dynamic>? resultadoMotorV1) => AnamneseDetalheModel(
          id: 'anamnese-1',
          dataPreenchimento: DateTime(2026, 10, 1),
          statusVigencia: 'ativo',
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
          resultadoMotorV1: resultadoMotorV1,
        );

    testWidgets('sem snapshot gravado (nenhuma meta salva ainda) mostra o aviso de fallback', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheComMotor(null));

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Sem resultado do Motor Metabólico calculado para esta avaliação.'), findsOneWidget);
    });

    testWidgets('com snapshot gravado, mostra TMB, TDEE médio, qualidade, energia recomendada e macros',
        (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer(
        (_) async => detalheComMotor({
          'formula_tmb': {'codigo': 'TMB-001'},
          'estrategia_tdee': 'pal',
          'tmb': 1655.5,
          'tdee_medio': 1986.6,
          'avisos': <String>[],
          'qualidade': {'score': 'alta', 'motivos': <String>[]},
          'energia_recomendacao': {
            'estrategia': 'deficit_conservador',
            'deficit_percentual': 0.1,
            'deficit_versao': 'DEFICIT-002-multicriterio-v1',
            'recomendacao_media_diaria': 1788,
          },
          'macros_recomendados': {
            // RELATÓRIO 20261103_0002 — `energia_alvo` dos protocolos de
            // macros é a RECOMENDAÇÃO (déficit/manutenção), não o TDEE
            // médio bruto — mesmo valor de `recomendacao_media_diaria`
            // (1788), de propósito, pra refletir o dado real da RPC.
            'energia_alvo': 1788,
            'macro_001': {
              'versao': 'MACRO-001-default-v1',
              'disponivel': true,
              'parametros': {'percentual_proteina': 0.25, 'percentual_carboidrato': 0.45, 'percentual_gordura': 0.30},
              'proteina_g': 124,
              'carboidrato_g': 223,
              'gordura_g': 66,
              'validacao_soma_ok': true,
            },
          },
        }),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('1987 kcal'), findsOneWidget);
      expect(find.text('1656 kcal'), findsOneWidget);
      expect(find.text('Alta'), findsOneWidget);
      // RELATÓRIO 20261103_0002 — 1788 kcal aparece 2x de propósito: uma
      // vez no card de Energia Recomendada (Seção A original) e outra
      // como VET do card de protocolo de macros (mesmo valor real, a RPC
      // usa a MESMA energia-alvo recomendada pros dois).
      expect(find.text('1788 kcal'), findsNWidgets(2));
      expect(find.text('MACRO-001'), findsOneWidget);
      // RELATÓRIO 20261103_0002 — gramas + PORCENTAGEM agora (percentual
      // calculado a partir dos gramas/energia-alvo, nunca inventado):
      // 124g×4kcal=496kcal/1788=28%; 223g×4=892/1788=50%; 66g×9=594/1788=33%.
      expect(find.text('P 124g (28%) · C 223g (50%) · G 66g (33%)'), findsOneWidget);
    });
  });

  // RELATÓRIO 20261103_0002 (item 1 — "Detalhamento de Calorias e
  // Nutrientes no Histórico") — kcal por refeição + total consolidado do
  // dia, lidos de `refeicoesDiariasHabituais` (já existia no modelo,
  // nunca renderizado nesta tela até esta tarefa).
  group('Refeições Habituais e Total Diário (RELATÓRIO 20261103_0002)', () {
    AnamneseDetalheModel detalheComRefeicoes(List<Map<String, dynamic>> refeicoes) => AnamneseDetalheModel(
          id: 'anamnese-1',
          dataPreenchimento: DateTime(2026, 10, 1),
          statusVigencia: 'ativo',
          objetivoCodigo: 'manter_peso',
          pesoKg: 80.0,
          alturaCm: 178.0,
          problemasSaudeNomes: const [],
          alergiasNomes: const [],
          atividades: const [],
          medicamentos: const [],
          suplementos: const [],
          exames: const [],
          complementares: DadosComplementaresAnamnese(refeicoesDiariasHabituais: refeicoes),
        );

    testWidgets('sem nenhuma refeição habitual, a seção inteira some (sem título, sem total)', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer((_) async => detalheComRefeicoes(const []));

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Refeições diárias habituais'), findsNothing);
      expect(find.text('Total do Dia'), findsNothing);
    });

    testWidgets('mostra kcal/macros por refeição e o total consolidado do dia', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer(
        (_) async => detalheComRefeicoes([
          {
            'numero_refeicao': 1,
            'horario': '08:00',
            'fora_de_casa': false,
            'descricao_texto': 'Pão integral com ovo',
            'kcal': 350.0,
            'proteina_g': 20.0,
            'carboidrato_g': 30.0,
            'gordura_g': 12.0,
          },
          {
            'numero_refeicao': 2,
            'horario': '12:30',
            'fora_de_casa': true,
            'descricao_texto': 'Arroz, feijão e frango grelhado',
            'kcal': 650.0,
            'proteina_g': 45.0,
            'carboidrato_g': 70.0,
            'gordura_g': 18.0,
          },
        ]),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Refeições diárias habituais'), findsOneWidget);
      expect(find.text('Refeição 1'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('Pão integral com ovo'), findsOneWidget);
      expect(find.text('350 kcal'), findsOneWidget);
      expect(find.text('P 20g · C 30g · G 12g'), findsOneWidget);

      expect(find.text('Refeição 2'), findsOneWidget);
      expect(find.text('Fora de casa'), findsOneWidget);
      expect(find.text('650 kcal'), findsOneWidget);

      // Total do dia = soma das 2 refeições: 1000 kcal, P 65g, C 100g, G 30g.
      expect(find.text('Total do Dia'), findsOneWidget);
      expect(find.text('1000 kcal'), findsOneWidget);
      expect(find.text('P 65g · C 100g · G 30g'), findsOneWidget);
    });

    testWidgets(
        'refeição sem cálculo (IA nunca rodou, inclusive anamnese antiga — chave nem existe) mostra o fallback, sem travar o total',
        (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer(
        (_) async => detalheComRefeicoes([
          // Sem `kcal`/`proteina_g`/`carboidrato_g`/`gordura_g` — nem a
          // chave existe no mapa (mesmo formato de uma anamnese de antes
          // da IA de refeições existir, ou uma refeição nunca interpretada).
          {'numero_refeicao': 1, 'fora_de_casa': false},
          {
            'numero_refeicao': 2,
            'fora_de_casa': false,
            'kcal': 500.0,
            'proteina_g': 30.0,
            'carboidrato_g': 50.0,
            'gordura_g': 15.0,
          },
        ]),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Sem cálculo de calorias/macros para esta refeição.'), findsOneWidget);
      // O total soma só a refeição 2 (que TEM dado) — nunca trava nem
      // inventa um valor pra refeição 1.
      expect(find.text('500 kcal'), findsWidgets);
      expect(find.text('P 30g · C 50g · G 15g'), findsWidgets);
    });

    testWidgets('nenhuma refeição com cálculo mostra o fallback do total, nunca "0 kcal"', (tester) async {
      when(() => repository.buscarAnamnesePorId('anamnese-1')).thenAnswer(
        (_) async => detalheComRefeicoes([
          {'numero_refeicao': 1, 'fora_de_casa': false},
        ]),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      expect(find.text('Total do Dia'), findsOneWidget);
      expect(find.text('Sem dados suficientes para calcular o total do dia.'), findsOneWidget);
      expect(find.text('0 kcal'), findsNothing);
    });
  });
}
