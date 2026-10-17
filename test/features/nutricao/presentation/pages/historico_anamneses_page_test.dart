import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/data/repositories/anamnese_repository.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/anamnese_detalhes_page.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/pages/historico_anamneses_page.dart';

class _MockRepository extends Mock implements AnamneseRepository {}

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
    return MaterialApp(home: HistoricoAnamnesesPage(repository: repository));
  }

  testWidgets('sem nenhuma anamnese, mostra o estado vazio', (tester) async {
    when(() => repository.buscarHistoricoAnamneses()).thenAnswer((_) async => const []);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Você ainda não preencheu nenhuma anamnese.'), findsOneWidget);
  });

  testWidgets('erro ao carregar mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarHistoricoAnamneses()).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar seu histórico. Tente novamente.'), findsOneWidget);
  });

  testWidgets('lista as anamneses (data, peso/altura, objetivo, status) e destaca a próxima revisão', (tester) async {
    final maisRecente = DateTime.now().subtract(const Duration(days: 35));
    final anterior = maisRecente.subtract(const Duration(days: 35));
    when(() => repository.buscarHistoricoAnamneses()).thenAnswer(
      (_) async => [
        AnamneseHistoricoItem(
          id: 'a2',
          dataPreenchimento: maisRecente,
          objetivoCodigo: 'ganhar_massa_muscular',
          pesoKg: 79.3,
          alturaCm: 178,
          statusVigencia: 'ativo',
        ),
        AnamneseHistoricoItem(
          id: 'a1',
          dataPreenchimento: anterior,
          objetivoCodigo: 'perder_peso',
          statusVigencia: 'historico',
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    // Próxima revisão = maisRecente + 30 dias, que já passou (preenchida
    // há 35 dias) — "disponível agora".
    expect(find.text('Revisão disponível agora'), findsOneWidget);

    expect(find.text('Ganhar massa muscular'), findsOneWidget);
    expect(find.text('79.3 kg · 178 cm'), findsOneWidget);
    expect(find.text('Atual'), findsOneWidget);

    expect(find.text('Perder peso'), findsOneWidget);
    expect(find.text('Sem peso/altura registrados'), findsOneWidget);
    expect(find.text('Anterior'), findsOneWidget);
  });

  testWidgets('anamnese recente (< 30 dias) mostra a data exata da próxima revisão', (tester) async {
    final recente = DateTime.now().subtract(const Duration(days: 5));
    when(() => repository.buscarHistoricoAnamneses()).thenAnswer(
      (_) async => [
        AnamneseHistoricoItem(
          id: 'a1',
          dataPreenchimento: recente,
          objetivoCodigo: 'manter_peso',
          statusVigencia: 'ativo',
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Revisão disponível agora'), findsNothing);
    expect(find.textContaining('Próxima revisão disponível em'), findsOneWidget);
  });

  // RELATÓRIO 20261016_0005 (item 2) — o card deixa de ser inerte: toca e
  // abre o detalhe 100% leitura daquela anamnese específica.
  testWidgets('tocar num card navega para AnamneseDetalhesPage com o id correto', (tester) async {
    when(() => repository.buscarHistoricoAnamneses()).thenAnswer(
      (_) async => [
        AnamneseHistoricoItem(
          id: 'anamnese-xyz',
          dataPreenchimento: DateTime.now(),
          objetivoCodigo: 'manter_peso',
          statusVigencia: 'ativo',
        ),
      ],
    );
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manter peso'));
    // A tela de detalhe usa seu próprio AnamneseRepository por padrão
    // quando nenhum é injetado (igual ao uso real a partir daqui) — não
    // há Supabase inicializado neste arquivo de teste, mas a tentativa de
    // acesso falha de forma síncrona e é capturada pelo try/catch de
    // `_carregar` (vira estado de erro), então pumpAndSettle termina
    // normalmente; aqui só interessa confirmar QUE a navegação aconteceu
    // com o id certo.
    await tester.pumpAndSettle();

    final detalhePage = tester.widget<AnamneseDetalhesPage>(find.byType(AnamneseDetalhesPage));
    expect(detalhePage.anamneseId, 'anamnese-xyz');
  });
}
