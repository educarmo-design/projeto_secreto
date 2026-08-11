import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/models/treino_model.dart';
import 'package:atleta_gamificacao/features/dashboard/data/repositories/treinos_historico_repository.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/pages/historico_treinos_page.dart';

class _MockRepository extends Mock implements TreinosHistoricoRepository {}

TreinoModel _treino({
  String id = 'treino-1',
  String tipoAtividadeCodigo = 'RUNNING',
  String? nomeExibicao = 'Corrida',
  required DateTime inicio,
  required DateTime fim,
  double? distanciaMetros,
  double? energiaQueimadaKcal,
  int? fcMedia,
  int? fcMinima,
  int? fcMaxima,
}) {
  return TreinoModel(
    id: id,
    tipoAtividadeCodigo: tipoAtividadeCodigo,
    tipoAtividadeNomeExibicao: nomeExibicao,
    inicioAtividade: inicio,
    fimAtividade: fim,
    distanciaMetros: distanciaMetros,
    energiaQueimadaKcal: energiaQueimadaKcal,
    fcMedia: fcMedia,
    fcMinima: fcMinima,
    fcMaxima: fcMaxima,
  );
}

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
    return MaterialApp(home: HistoricoTreinosPage(repository: repository));
  }

  testWidgets('carrega e mostra os treinos com modalidade, duração, distância, calorias e as 3 FCs', (tester) async {
    when(() => repository.buscarUltimosTreinos()).thenAnswer(
      (_) async => [
        _treino(
          inicio: DateTime(2026, 7, 8, 7),
          fim: DateTime(2026, 7, 8, 7, 45),
          distanciaMetros: 8000,
          energiaQueimadaKcal: 450,
          fcMedia: 155,
          fcMinima: 130,
          fcMaxima: 172,
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Corrida'), findsOneWidget);
    expect(find.textContaining('Duração: 45min'), findsOneWidget);
    expect(find.textContaining('Distância: 8.00 km'), findsOneWidget);
    expect(find.textContaining('Calorias: 450 kcal'), findsOneWidget);
    expect(find.textContaining('FC média: 155 bpm'), findsOneWidget);
    expect(find.textContaining('FC mín.: 130 bpm'), findsOneWidget);
    expect(find.textContaining('FC máx.: 172 bpm'), findsOneWidget);
  });

  testWidgets('sem nome de exibição no embed, cai pro código cru', (tester) async {
    when(() => repository.buscarUltimosTreinos()).thenAnswer(
      (_) async => [
        _treino(
          nomeExibicao: null,
          tipoAtividadeCodigo: 'RUNNING',
          inicio: DateTime(2026, 7, 8, 7),
          fim: DateTime(2026, 7, 8, 7, 30),
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('RUNNING'), findsOneWidget);
  });

  testWidgets('duração maior que 1h formata como "1h 20min"', (tester) async {
    when(() => repository.buscarUltimosTreinos()).thenAnswer(
      (_) async => [
        _treino(inicio: DateTime(2026, 7, 8, 7), fim: DateTime(2026, 7, 8, 8, 20)),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Duração: 1h 20min'), findsOneWidget);
  });

  testWidgets('lista vazia mostra o empty state', (tester) async {
    when(() => repository.buscarUltimosTreinos()).thenAnswer((_) async => const []);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum treino sincronizado ainda.'), findsOneWidget);
  });

  testWidgets('erro no SELECT mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarUltimosTreinos()).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar o histórico de treinos.'), findsOneWidget);
  });
}
