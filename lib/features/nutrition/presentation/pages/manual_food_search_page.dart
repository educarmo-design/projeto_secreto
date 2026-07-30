import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/alimento_encontrado_model.dart';
import '../controllers/food_search_controller.dart';

/// Busca Manual de Alimentos (Adendo v5.1 §A.3/§C.3) — alternativa ao fluxo
/// de câmera para quando o usuário já sabe o nome do alimento e prefere
/// digitar. "Validação = completa funcionalmente, crua visualmente" (v5.1
/// §B): o `ListView` de resultados é um `ListTile` por alimento, sem
/// acabamento visual — a busca real (embedding + similaridade contra
/// `alimentos_referencia`) é o que importa agora.
class ManualFoodSearchPage extends StatefulWidget {
  const ManualFoodSearchPage({super.key, this.controller});

  /// Injetável em teste — mesmo padrão de [GerirVinculosPage].
  final FoodSearchController? controller;

  @override
  State<ManualFoodSearchPage> createState() => _ManualFoodSearchPageState();
}

class _ManualFoodSearchPageState extends State<ManualFoodSearchPage> {
  late final FoodSearchController _controller = widget.controller ?? FoodSearchController();
  late final bool _controllerEhProprio = widget.controller == null;
  final TextEditingController _campoBusca = TextEditingController();

  @override
  void dispose() {
    if (_controllerEhProprio) _controller.dispose();
    _campoBusca.dispose();
    super.dispose();
  }

  void _buscar() => _controller.buscar(_campoBusca.text);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('food_search.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _campoBusca,
                      decoration: InputDecoration(
                        hintText: i18n.tr('food_search.hint'),
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _buscar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<FoodSearchState>(
                    valueListenable: _controller,
                    builder: (context, state, _) => FilledButton(
                      onPressed: state.carregando ? null : _buscar,
                      child: Text(i18n.tr('food_search.search_button')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ValueListenableBuilder<FoodSearchState>(
                  valueListenable: _controller,
                  builder: (context, state, _) => _buildResultados(context, state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultados(BuildContext context, FoodSearchState state) {
    if (state.carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.erro != null) {
      return Center(
        child: Text(
          state.erro!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (!state.buscaRealizada) {
      return Center(child: Text(i18n.tr('food_search.idle_hint')));
    }
    if (state.resultados.isEmpty) {
      return Center(child: Text(i18n.tr('food_search.empty_state')));
    }
    return ListView.builder(
      itemCount: state.resultados.length,
      itemBuilder: (context, index) => _ResultadoTile(alimento: state.resultados[index]),
    );
  }
}

class _ResultadoTile extends StatelessWidget {
  const _ResultadoTile({required this.alimento});

  final AlimentoEncontradoModel alimento;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(alimento.nomeTaco),
      subtitle: Text(
        i18n.tr('food_search.result_subtitle', params: {
          'calorias': alimento.caloriasKcal100g.toStringAsFixed(0),
          'proteinas': alimento.proteinasG100g.toStringAsFixed(1),
          'carboidratos': alimento.carboidratosG100g.toStringAsFixed(1),
          'gorduras': alimento.gordurasG100g.toStringAsFixed(1),
        }),
      ),
      trailing: Text('${(alimento.similarity * 100).round()}%'),
    );
  }
}
