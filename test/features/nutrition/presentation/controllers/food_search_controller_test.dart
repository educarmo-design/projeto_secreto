import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/nutrition/data/models/alimento_encontrado_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/services/food_search_service.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/food_search_controller.dart';

void main() {
  AlimentoEncontradoModel alimento({
    String id = 'alimento-1',
    String nomeTaco = 'Carne bovina, patinho, cru',
    double similarity = 0.75,
  }) {
    return AlimentoEncontradoModel(
      id: id,
      nomeTaco: nomeTaco,
      aliases: const ['bifinho'],
      caloriasKcal100g: 130,
      proteinasG100g: 22,
      carboidratosG100g: 0,
      gordurasG100g: 4,
      similarity: similarity,
    );
  }

  test('estado inicial não fez busca nenhuma', () {
    final controller = FoodSearchController(
      service: _FakeService(resultado: const FoodSearchResult(success: true)),
      authHeadersProvider: () => const {},
    );

    expect(controller.value.buscaRealizada, false);
    expect(controller.value.carregando, false);
    expect(controller.value.resultados, isEmpty);
  });

  test('query vazia não chama o serviço e expõe erro local', () async {
    final fake = _FakeService(resultado: const FoodSearchResult(success: true));
    final controller = FoodSearchController(service: fake, authHeadersProvider: () => const {});

    await controller.buscar('   ');

    expect(fake.chamadas, isEmpty);
    expect(controller.value.erro, 'Digite algo para buscar.');
    expect(controller.value.buscaRealizada, false);
  });

  test('busca com sucesso preenche resultados e marca buscaRealizada', () async {
    final fake = _FakeService(
      resultado: FoodSearchResult(success: true, alimentos: [alimento()]),
    );
    final controller = FoodSearchController(service: fake, authHeadersProvider: () => const {});

    await controller.buscar('bifinho');

    expect(fake.chamadas.single, 'bifinho');
    expect(controller.value.resultados, hasLength(1));
    expect(controller.value.resultados.single.nomeTaco, 'Carne bovina, patinho, cru');
    expect(controller.value.buscaRealizada, true);
    expect(controller.value.erro, isNull);
    expect(controller.value.carregando, false);
  });

  test('busca sem resultados fica com lista vazia mas buscaRealizada true', () async {
    final fake = _FakeService(resultado: const FoodSearchResult(success: true));
    final controller = FoodSearchController(service: fake, authHeadersProvider: () => const {});

    await controller.buscar('sushi');

    expect(controller.value.resultados, isEmpty);
    expect(controller.value.buscaRealizada, true);
    expect(controller.value.erro, isNull);
  });

  test('falha do serviço expõe o erro e não deixa resultado velho', () async {
    final fake = _FakeService(
      resultado: const FoodSearchResult(success: false, errorMessage: 'Sessão expirada.'),
    );
    final controller = FoodSearchController(service: fake, authHeadersProvider: () => const {});

    await controller.buscar('bifinho');

    expect(controller.value.erro, 'Sessão expirada.');
    expect(controller.value.resultados, isEmpty);
    expect(controller.value.buscaRealizada, true);
    expect(controller.value.carregando, false);
  });

  test('termo é aparado (trim) antes de ser enviado', () async {
    final fake = _FakeService(resultado: const FoodSearchResult(success: true));
    final controller = FoodSearchController(service: fake, authHeadersProvider: () => const {});

    await controller.buscar('  bifinho  ');

    expect(fake.chamadas.single, 'bifinho');
  });
}

/// Fake em memória — mesmo espírito do `_FakeGateway` de
/// vinculos_controller_test.dart: nunca toca rede.
class _FakeService implements FoodSearchService {
  _FakeService({required this.resultado});

  final FoodSearchResult resultado;
  final List<String> chamadas = [];

  @override
  Future<FoodSearchResult> buscar({
    required String query,
    required Map<String, String> authHeaders,
  }) async {
    chamadas.add(query);
    return resultado;
  }
}
