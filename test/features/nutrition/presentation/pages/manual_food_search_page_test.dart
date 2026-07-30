import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/alimento_encontrado_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/services/food_search_service.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/food_search_controller.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/manual_food_search_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  FoodSearchController controllerCom(FoodSearchResult resultado) {
    return FoodSearchController(
      service: _FakeService(resultado: resultado),
      authHeadersProvider: () => const {},
    );
  }

  Future<void> pumpPagina(WidgetTester tester, FoodSearchController controller) async {
    await tester.pumpWidget(
      MaterialApp(home: ManualFoodSearchPage(controller: controller)),
    );
    await tester.pump();
  }

  testWidgets('estado inicial mostra a dica de "digite algo"', (tester) async {
    await pumpPagina(tester, controllerCom(const FoodSearchResult(success: true)));

    expect(
      find.text('Digite algo e toque em Buscar para ver alimentos parecidos.'),
      findsOneWidget,
    );
  });

  testWidgets('digitar e tocar em Buscar mostra os resultados com macros', (tester) async {
    await pumpPagina(
      tester,
      controllerCom(
        const FoodSearchResult(
          success: true,
          alimentos: [
            AlimentoEncontradoModel(
              id: 'a1',
              nomeTaco: 'Carne bovina, patinho, cru',
              aliases: ['bifinho'],
              caloriasKcal100g: 130,
              proteinasG100g: 22,
              carboidratosG100g: 0,
              gordurasG100g: 4,
              similarity: 0.75,
            ),
          ],
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'bifinho');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('Carne bovina, patinho, cru'), findsOneWidget);
    expect(find.text('130 kcal · 22.0g prot · 0.0g carb · 4.0g gord (por 100g)'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('busca sem resultados mostra o empty state', (tester) async {
    await pumpPagina(tester, controllerCom(const FoodSearchResult(success: true)));

    await tester.enterText(find.byType(TextField), 'sushi');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('Nenhum alimento parecido foi encontrado.'), findsOneWidget);
  });

  testWidgets('erro do servidor é exibido em vez da lista', (tester) async {
    await pumpPagina(
      tester,
      controllerCom(const FoodSearchResult(success: false, errorMessage: 'Erro de conexão.')),
    );

    await tester.enterText(find.byType(TextField), 'bifinho');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('Erro de conexão.'), findsOneWidget);
  });

  testWidgets('enviar pelo teclado (onSubmitted) também dispara a busca', (tester) async {
    await pumpPagina(tester, controllerCom(const FoodSearchResult(success: true)));

    await tester.enterText(find.byType(TextField), 'sushi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Nenhum alimento parecido foi encontrado.'), findsOneWidget);
  });
}

class _FakeService implements FoodSearchService {
  _FakeService({required this.resultado});

  final FoodSearchResult resultado;

  @override
  Future<FoodSearchResult> buscar({
    required String query,
    required Map<String, String> authHeaders,
  }) async {
    return resultado;
  }
}
