import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../data/models/alimento_encontrado_model.dart';
import '../../data/services/food_search_service.dart';

@immutable
class FoodSearchState {
  final List<AlimentoEncontradoModel> resultados;
  final bool carregando;
  final String? erro;

  /// Distingue "ainda não buscou nada" (mostra a dica inicial) de "buscou e
  /// não achou nada" (mostra o empty state de resultado vazio) — os dois
  /// têm `resultados` vazia, mas a mensagem certa é diferente.
  final bool buscaRealizada;

  const FoodSearchState({
    this.resultados = const [],
    this.carregando = false,
    this.erro,
    this.buscaRealizada = false,
  });
}

/// Orquestra a Busca Manual de Alimentos (Adendo v5.1 §A.3/§C.3): envia o
/// termo digitado para `search-food` e expõe os alimentos mais próximos por
/// similaridade de embedding. Mesma forma de [VinculosController]: o gateway
/// e a proveniência do header de auth são injetáveis, para os testes
/// trocarem por fakes sem montar um `SupabaseClient`/servidor de verdade.
class FoodSearchController extends ValueNotifier<FoodSearchState> {
  FoodSearchController({
    FoodSearchService? service,
    Map<String, String> Function()? authHeadersProvider,
  })  : _service = service ?? FoodSearchService(),
        _authHeadersProvider = authHeadersProvider ?? _authHeadersFromSupabase,
        super(const FoodSearchState());

  final FoodSearchService _service;
  final Map<String, String> Function() _authHeadersProvider;

  static Map<String, String> _authHeadersFromSupabase() {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Future<void> buscar(String query) async {
    final termo = query.trim();
    if (termo.isEmpty) {
      value = const FoodSearchState(erro: 'Digite algo para buscar.');
      return;
    }

    value = const FoodSearchState(carregando: true);

    final resultado = await _service.buscar(
      query: termo,
      authHeaders: _authHeadersProvider(),
    );

    if (!resultado.success) {
      value = FoodSearchState(
        erro: resultado.errorMessage ?? 'Erro desconhecido.',
        buscaRealizada: true,
      );
      return;
    }

    value = FoodSearchState(resultados: resultado.alimentos, buscaRealizada: true);
  }
}
