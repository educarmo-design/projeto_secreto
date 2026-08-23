import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/alimento_encontrado_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/favorita_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/favoritas_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/data/services/food_search_service.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/food_search_controller.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/criar_favorita_page.dart';

class _MockFavoritasRepository extends Mock implements FavoritasRepository {}

class _FakeService implements FoodSearchService {
  _FakeService({required this.resultado});

  final FoodSearchResult resultado;

  @override
  Future<FoodSearchResult> buscar({
    required String query,
    required Map<String, String> authHeaders,
  }) async =>
      resultado;
}

const _arroz = AlimentoEncontradoModel(
  id: 'a1',
  nomeTaco: 'Arroz branco cozido',
  aliases: ['arroz'],
  caloriasKcal100g: 130,
  proteinasG100g: 2.5,
  carboidratosG100g: 28,
  gordurasG100g: 0.2,
  similarity: 0.9,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(TipoRefeicao.almoco);
  });

  late _MockFavoritasRepository favoritasRepository;

  setUp(() {
    favoritasRepository = _MockFavoritasRepository();
  });

  FoodSearchController controllerCom(FoodSearchResult resultado) {
    return FoodSearchController(
      service: _FakeService(resultado: resultado),
      authHeadersProvider: () => const {},
    );
  }

  Future<void> pumpPagina(
    WidgetTester tester, {
    FoodSearchResult resultado = const FoodSearchResult(success: true, alimentos: [_arroz]),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CriarFavoritaPage(
          searchController: controllerCom(resultado),
          favoritasRepository: favoritasRepository,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> buscarArroz(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'arroz');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
  }

  testWidgets('tocar num resultado adiciona à lista de selecionados com 100g', (tester) async {
    await pumpPagina(tester);
    await buscarArroz(tester);

    expect(find.text('Itens selecionados (0)'), findsOneWidget);

    await tester.tap(find.text('Arroz branco cozido'));
    await tester.pumpAndSettle();

    expect(find.text('Itens selecionados (1)'), findsOneWidget);
    expect(find.text('100g · 130 kcal'), findsOneWidget);
  });

  testWidgets('tocar de novo no mesmo alimento soma +100g em vez de duplicar', (tester) async {
    await pumpPagina(tester);
    await buscarArroz(tester);

    await tester.tap(find.text('Arroz branco cozido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Arroz branco cozido').first);
    await tester.pumpAndSettle();

    expect(find.text('Itens selecionados (1)'), findsOneWidget); // ainda 1 linha
    expect(find.text('200g · 260 kcal'), findsOneWidget);
  });

  testWidgets('+/- ajustam 10g por vez, sem passar do piso de 10g', (tester) async {
    await pumpPagina(tester);
    await buscarArroz(tester);
    await tester.tap(find.text('Arroz branco cozido'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('90g · 117 kcal'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.tap(find.byIcon(Icons.add_circle_outline).last);
    await tester.pumpAndSettle();
    expect(find.text('110g · 143 kcal'), findsOneWidget);
  });

  testWidgets('remover item esvazia a lista e desabilita Salvar favorita', (tester) async {
    await pumpPagina(tester);
    await buscarArroz(tester);
    await tester.tap(find.text('Arroz branco cozido'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Itens selecionados (0)'), findsOneWidget);
    final botao = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar favorita'));
    expect(botao.onPressed, isNull);
  });

  testWidgets('salvar com nome e tipo válidos chama FavoritasRepository.salvar com o payload certo',
      (tester) async {
    when(() => favoritasRepository.salvar(
          nome: any(named: 'nome'),
          tipoRefeicao: any(named: 'tipoRefeicao'),
          payloadJsonb: any(named: 'payloadJsonb'),
        )).thenAnswer((_) async => const ColetaDiariaResult(success: true));

    late bool? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            resultado = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CriarFavoritaPage(
                  searchController: controllerCom(
                    const FoodSearchResult(success: true, alimentos: [_arroz]),
                  ),
                  favoritasRepository: favoritasRepository,
                ),
              ),
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await buscarArroz(tester);
    await tester.tap(find.text('Arroz branco cozido'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar favorita'));
    await tester.pumpAndSettle();

    expect(find.text('Nome e tipo da favorita'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Arroz do almoço');
    await tester.tap(find.widgetWithText(RadioListTile<TipoRefeicao>, 'Almoço'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    final captura = verify(() => favoritasRepository.salvar(
          nome: 'Arroz do almoço',
          tipoRefeicao: TipoRefeicao.almoco,
          payloadJsonb: captureAny(named: 'payloadJsonb'),
        )).captured.single as Map<String, dynamic>;

    expect((captura['itens'] as List).length, 1);
    final item = (captura['itens'] as List).single as Map<String, dynamic>;
    expect(item['nome'], 'Arroz branco cozido');
    expect(item['gramas_estimados'], 100.0);
    expect(item['calorias'], 130.0);
    expect((captura['totais'] as Map)['calorias'], 130.0);
    expect(resultado, isTrue);
  });

  testWidgets('falha ao salvar mostra erro e não sai da tela', (tester) async {
    when(() => favoritasRepository.salvar(
          nome: any(named: 'nome'),
          tipoRefeicao: any(named: 'tipoRefeicao'),
          payloadJsonb: any(named: 'payloadJsonb'),
        )).thenAnswer(
      (_) async => const ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível criar a favorita. Tente novamente.',
      ),
    );

    await pumpPagina(tester);
    await buscarArroz(tester);
    await tester.tap(find.text('Arroz branco cozido'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar favorita'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'x');
    await tester.tap(find.widgetWithText(RadioListTile<TipoRefeicao>, 'Almoço'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível criar a favorita. Tente novamente.'), findsOneWidget);
    expect(find.text('Criar Favorita'), findsOneWidget); // ainda na tela
  });
}
