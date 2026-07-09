import 'package:flutter/foundation.dart';

import '../../data/models/widget_layout_model.dart';

/// Estado reativo do layout do painel dinâmico — única fonte de verdade
/// compartilhada entre a aba Dashboard ([MainNavigationPage]) e a tela de
/// gerenciamento ([GerenciadorLayoutPage]). As duas telas escutam a MESMA
/// instância ([layoutController]) em vez de cada uma carregar/persistir seu
/// próprio [WidgetLayoutModel] — é isso que faz uma mudança feita na tela de
/// gerenciamento (reordenar, mostrar/ocultar) aparecer instantaneamente no
/// Dashboard, mesmo antes do usuário voltar para ele.
class LayoutController extends ChangeNotifier {
  LayoutController() {
    _carregar();
  }

  WidgetLayoutModel? _layout;
  bool _isLoading = true;

  WidgetLayoutModel? get layout => _layout;
  bool get isLoading => _isLoading;

  Future<void> _carregar() async {
    _layout = await WidgetLayoutModel.carregar();
    _isLoading = false;
    notifyListeners();
  }

  /// Reordena sobre a lista canônica *completa* (todos os 8 blocos,
  /// visíveis ou não) — é o que [GerenciadorLayoutPage] usa, já que seu
  /// `ReorderableListView` mostra cada bloco do [WidgetLayoutModel], não só
  /// os ativos.
  ///
  /// Espera [newIndex] já ajustado para a remoção do item em [oldIndex] —
  /// a convenção do `onReorderItem` do Flutter (não a do `onReorder`
  /// legado, que exigia subtrair 1 manualmente).
  Future<void> atualizarOrdemBlocos(int oldIndex, int newIndex) async {
    final atual = _layout;
    if (atual == null) return;

    final novaOrdem = List<DashboardWidgetId>.from(atual.ordem);
    final id = novaOrdem.removeAt(oldIndex);
    novaOrdem.insert(newIndex, id);

    await _aplicar(atual.comOrdem(novaOrdem));
  }

  /// Reordena sobre a lista de blocos *visíveis* — é o que o próprio
  /// Dashboard usa, já que seu `ReorderableListView` só renderiza os cards
  /// ativos. Traduz os índices de volta para a ordem canônica completa,
  /// preservando a posição relativa de cada bloco oculto (ver
  /// [WidgetLayoutModel.visiveisEmOrdem]).
  Future<void> atualizarOrdemVisivel(int oldIndex, int newIndex) async {
    final atual = _layout;
    if (atual == null) return;

    final visiveis = List<DashboardWidgetId>.from(atual.visiveisEmOrdem);
    final id = visiveis.removeAt(oldIndex);
    visiveis.insert(newIndex, id);

    final novaOrdemCompleta = <DashboardWidgetId>[];
    var visivelIdx = 0;
    for (final idAtual in atual.ordem) {
      if (atual.isAtivo(idAtual)) {
        novaOrdemCompleta.add(visiveis[visivelIdx]);
        visivelIdx++;
      } else {
        novaOrdemCompleta.add(idAtual);
      }
    }

    await _aplicar(atual.comOrdem(novaOrdemCompleta));
  }

  /// Mostra/oculta um bloco pelo id de string fixo do PRD Mestre (ex.:
  /// `'status_streak_duolingo'`) — persiste e notifica de imediato, o que é
  /// o que faz o Dashboard atualizar instantaneamente sem precisar recarregar
  /// a tela ou esperar o usuário navegar de volta.
  Future<void> alternarVisibilidadeBloco(String widgetId, bool visivel) async {
    final atual = _layout;
    if (atual == null) return;

    final id = DashboardWidgetId.fromId(widgetId);
    if (id == null) return;

    await _aplicar(atual.comAtivo(id, visivel));
  }

  Future<void> _aplicar(WidgetLayoutModel novoLayout) async {
    _layout = novoLayout;
    notifyListeners();
    await novoLayout.salvar();
  }
}

/// Instância compartilhada — mesmo padrão de singleton de
/// [uiProfileSwitcher]/[cryptoStorage]/[supabaseManager] usado no resto do
/// app.
final layoutController = LayoutController();
