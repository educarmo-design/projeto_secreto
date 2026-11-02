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
    // RELATÓRIO 20261101_0002 — default "sem validade calculada ainda"
    // (mesma convenção do resto da classe); os testes da Próxima Revisão
    // sobrescrevem com uma data real.
    when(() => repository.buscarDataValidadeAnamnese()).thenAnswer((_) async => null);
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

  // RELATÓRIO 20261101_0002 (BUG CORRIGIDO) — a Próxima Revisão usava uma
  // régua própria (`dataPreenchimento + 30 dias`), a mesma divergência já
  // corrigida em [AnamneseSelfServicePage] (RELATÓRIO 20261101_0001):
  // ignorava `anamneses.data_validade` por completo. Agora usa a MESMA
  // [AnamneseValidadeStatus] do Dashboard — os testes abaixo trocam "dias
  // desde o preenchimento" por "data_validade no futuro/passado".
  testWidgets('lista as anamneses (data, peso/altura, objetivo, status) e destaca a próxima revisão — já vencida',
      (tester) async {
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
    when(() => repository.buscarDataValidadeAnamnese()).thenAnswer(
      (_) async => DateTime.now().subtract(const Duration(days: 5)),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    // data_validade já no passado — "disponível agora".
    expect(find.text('Revisão disponível agora'), findsOneWidget);

    expect(find.text('Ganhar massa muscular'), findsOneWidget);
    expect(find.text('79.3 kg · 178 cm'), findsOneWidget);
    expect(find.text('Atual'), findsOneWidget);

    expect(find.text('Perder peso'), findsOneWidget);
    expect(find.text('Sem peso/altura registrados'), findsOneWidget);
    expect(find.text('Anterior'), findsOneWidget);
  });

  testWidgets('data_validade ainda no futuro mostra a data exata da próxima revisão', (tester) async {
    when(() => repository.buscarHistoricoAnamneses()).thenAnswer(
      (_) async => [
        AnamneseHistoricoItem(
          id: 'a1',
          dataPreenchimento: DateTime.now().subtract(const Duration(days: 5)),
          objetivoCodigo: 'manter_peso',
          statusVigencia: 'ativo',
        ),
      ],
    );
    when(() => repository.buscarDataValidadeAnamnese()).thenAnswer(
      (_) async => DateTime.now().add(const Duration(days: 25)),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Revisão disponível agora'), findsNothing);
    expect(find.textContaining('Próxima revisão disponível em'), findsOneWidget);
  });

  // ACEITE literal da tarefa: Dashboard mostra "vencida", esta tela
  // reflete isso imediatamente, mesmo preenchida há poucos dias.
  testWidgets('data_validade no passado (Dashboard mostraria "vencida") sempre mostra "disponível agora"',
      (tester) async {
    when(() => repository.buscarHistoricoAnamneses()).thenAnswer(
      (_) async => [
        AnamneseHistoricoItem(
          id: 'a1',
          dataPreenchimento: DateTime.now().subtract(const Duration(days: 2)),
          objetivoCodigo: 'manter_peso',
          statusVigencia: 'ativo',
        ),
      ],
    );
    when(() => repository.buscarDataValidadeAnamnese()).thenAnswer(
      (_) async => DateTime.now().subtract(const Duration(days: 1)),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Revisão disponível agora'), findsOneWidget);
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
