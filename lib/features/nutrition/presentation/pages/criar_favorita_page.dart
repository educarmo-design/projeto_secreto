import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/alimento_encontrado_model.dart';
import '../../data/models/favorita_model.dart';
import '../../data/repositories/favoritas_repository.dart';
import '../controllers/food_search_controller.dart';
import '../widgets/dialogo_nome_tipo_favorita.dart';

/// Um alimento buscado + a quantidade escolhida pelo usuário NESTA tela —
/// os macros vêm de `alimentos_referencia` (por 100g, mesma tabela TACO que
/// `search-food` já consulta) e são recalculados localmente por regra de
/// três simples (mesma ideia de `ItemPratoEditavel.gramasEstimados`, mas sem
/// depender de uma extração de IA prévia: aqui o usuário monta a favorita
/// escolhendo os alimentos ele mesmo).
@immutable
class _ItemSelecionado {
  const _ItemSelecionado({required this.alimento, required this.gramas});

  final AlimentoEncontradoModel alimento;
  final double gramas;

  double get calorias => alimento.caloriasKcal100g * gramas / 100;
  double get proteinasG => alimento.proteinasG100g * gramas / 100;
  double get carboidratosG => alimento.carboidratosG100g * gramas / 100;
  double get gordurasG => alimento.gordurasG100g * gramas / 100;

  _ItemSelecionado comGramas(double novasGramas) =>
      _ItemSelecionado(alimento: alimento, gramas: novasGramas);
}

/// RELATÓRIO 20260823 — 1º gap encontrado pelo fundador testando: a tela de
/// Favoritas em si não tinha NENHUM jeito de criar uma favorita nova, só o
/// botão ⭐ de `ConfirmacaoPratoPage` (que exige fotografar/confirmar um
/// prato antes). Esta tela cobre o caso de montar uma favorita do zero,
/// digitando os alimentos — reaproveita a Busca Manual de Alimentos
/// (`FoodSearchController`/`search-food`, Adendo v5.1 §A.3/§C.3) em vez de
/// duplicar a busca, e produz o MESMO formato de payload que
/// `ConfirmacaoPratoController.payloadRevisado()` gera, então
/// `FavoritaModel`/`ConfirmacaoPratoPage` (modo edição) tratam esta
/// favorita exatamente como uma vinda de foto — nenhum caminho especial.
class CriarFavoritaPage extends StatefulWidget {
  const CriarFavoritaPage({
    super.key,
    FoodSearchController? searchController,
    FavoritasRepository? favoritasRepository,
  })  : _searchController = searchController,
        _favoritasRepository = favoritasRepository;

  final FoodSearchController? _searchController;
  final FavoritasRepository? _favoritasRepository;

  @override
  State<CriarFavoritaPage> createState() => _CriarFavoritaPageState();
}

class _CriarFavoritaPageState extends State<CriarFavoritaPage> {
  late final FoodSearchController _searchController =
      widget._searchController ?? FoodSearchController();
  late final bool _searchControllerEhProprio = widget._searchController == null;
  late final FavoritasRepository _favoritasRepository =
      widget._favoritasRepository ?? FavoritasRepository();
  final TextEditingController _campoBusca = TextEditingController();

  List<_ItemSelecionado> _itensSelecionados = const [];
  bool _salvando = false;

  @override
  void dispose() {
    if (_searchControllerEhProprio) _searchController.dispose();
    _campoBusca.dispose();
    super.dispose();
  }

  void _buscar() => _searchController.buscar(_campoBusca.text);

  /// Tocar num resultado já existente na lista soma +100g em vez de criar
  /// uma linha duplicada — evita "Arroz branco" aparecer duas vezes só
  /// porque o usuário tocou duas vezes sem perceber.
  void _adicionarItem(AlimentoEncontradoModel alimento) {
    setState(() {
      final indiceExistente =
          _itensSelecionados.indexWhere((item) => item.alimento.id == alimento.id);
      if (indiceExistente == -1) {
        _itensSelecionados = [
          ..._itensSelecionados,
          _ItemSelecionado(alimento: alimento, gramas: 100),
        ];
      } else {
        _itensSelecionados = [
          for (var i = 0; i < _itensSelecionados.length; i++)
            i == indiceExistente
                ? _itensSelecionados[i].comGramas(_itensSelecionados[i].gramas + 100)
                : _itensSelecionados[i],
        ];
      }
    });
  }

  void _ajustarGramas(int indice, double delta) {
    setState(() {
      final atual = _itensSelecionados[indice];
      final novasGramas = atual.gramas + delta;
      if (novasGramas < 10) return; // mesmo piso de "quantidade mínima" do F10 Passo 3
      _itensSelecionados = [
        for (var i = 0; i < _itensSelecionados.length; i++)
          i == indice ? atual.comGramas(novasGramas) : _itensSelecionados[i],
      ];
    });
  }

  void _removerItem(int indice) {
    setState(() {
      _itensSelecionados = [
        for (var i = 0; i < _itensSelecionados.length; i++)
          if (i != indice) _itensSelecionados[i],
      ];
    });
  }

  Map<String, dynamic> _payload() {
    final itens = _itensSelecionados
        .map((item) => {
              'nome': item.alimento.nomeTaco,
              'nome_identificado': item.alimento.nomeTaco,
              'medida': 'g',
              'quantidade': item.gramas,
              'gramas_estimados': item.gramas,
              'calorias': item.calorias,
              'proteinas_g': item.proteinasG,
              'carboidratos_g': item.carboidratosG,
              'gorduras_g': item.gordurasG,
              // Escolhido diretamente pelo usuário na busca — sem IA
              // estimando nada aqui, confiança máxima (mesma convenção do
              // campo em ItemPratoExtraidoModel, que representa "confiança
              // do CASAMENTO com alimentos_referencia").
              'confianca': 1.0,
            })
        .toList();

    double somar(double Function(_ItemSelecionado) selecionar) =>
        _itensSelecionados.fold(0.0, (soma, item) => soma + selecionar(item));

    return {
      'itens': itens,
      'itens_nao_reconhecidos': const [],
      'totais': {
        'calorias': somar((item) => item.calorias),
        'proteinas_g': somar((item) => item.proteinasG),
        'carboidratos_g': somar((item) => item.carboidratosG),
        'gorduras_g': somar((item) => item.gordurasG),
      },
    };
  }

  Future<void> _salvar() async {
    final resultado = await showDialog<({TipoRefeicao tipo, String nome})>(
      context: context,
      builder: (context) => DialogoNomeTipoFavorita(
        titulo: i18n.tr('criar_favorita.salvar_dialog_title'),
      ),
    );
    if (resultado == null || !mounted) return;

    setState(() => _salvando = true);
    final salvo = await _favoritasRepository.salvar(
      nome: resultado.nome,
      tipoRefeicao: resultado.tipo,
      payloadJsonb: _payload(),
    );
    if (!mounted) return;
    setState(() => _salvando = false);

    if (salvo.success) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(i18n.tr('criar_favorita.salvar_sucesso'))),
        );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(salvo.errorMessage ?? i18n.tr('criar_favorita.salvar_erro')),
            backgroundColor: AppColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('criar_favorita.title'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
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
                    valueListenable: _searchController,
                    builder: (context, state, _) => FilledButton(
                      onPressed: state.carregando ? null : _buscar,
                      child: Text(i18n.tr('food_search.search_button')),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<FoodSearchState>(
                valueListenable: _searchController,
                builder: (context, state, _) => _buildResultadosBusca(context, state),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  i18n.tr(
                    'criar_favorita.itens_selecionados_title',
                    params: {'quantidade': _itensSelecionados.length.toString()},
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            Expanded(child: _buildItensSelecionados(context)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                i18n.tr('criar_favorita.totais', params: {
                  'calorias': _itensSelecionados
                      .fold(0.0, (soma, item) => soma + item.calorias)
                      .toStringAsFixed(0),
                }),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed:
                    (_itensSelecionados.isEmpty || _salvando) ? null : _salvar,
                child: _salvando
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(i18n.tr('confirmacao_prato.saving')),
                        ],
                      )
                    : Text(i18n.tr('criar_favorita.salvar_button')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultadosBusca(BuildContext context, FoodSearchState state) {
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
      itemBuilder: (context, index) {
        final alimento = state.resultados[index];
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
          trailing: IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: i18n.tr('criar_favorita.adicionar_item'),
            onPressed: () => _adicionarItem(alimento),
          ),
          onTap: () => _adicionarItem(alimento),
        );
      },
    );
  }

  Widget _buildItensSelecionados(BuildContext context) {
    if (_itensSelecionados.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            i18n.tr('criar_favorita.nenhum_item_selecionado'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.mutedText),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _itensSelecionados.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _itensSelecionados[index];
        return ListTile(
          title: Text(item.alimento.nomeTaco),
          subtitle: Text(
            i18n.tr('criar_favorita.item_subtitulo', params: {
              'gramas': item.gramas.toStringAsFixed(0),
              'calorias': item.calorias.toStringAsFixed(0),
            }),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: i18n.tr('confirmacao_prato.decrement'),
                onPressed: () => _ajustarGramas(index, -10),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: i18n.tr('confirmacao_prato.increment'),
                onPressed: () => _ajustarGramas(index, 10),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: i18n.tr('confirmacao_prato.remove_item'),
                onPressed: () => _removerItem(index),
              ),
            ],
          ),
        );
      },
    );
  }
}
