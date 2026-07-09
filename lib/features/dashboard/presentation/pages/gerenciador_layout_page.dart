import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/widget_layout_model.dart';
import '../controllers/layout_controller.dart';
import '../widgets/dynamic_widget_factory.dart';

/// Tela dedicada de gerenciamento do painel dinâmico — PRD Mestre,
/// microinterações: cada bloco do [WidgetLayoutModel] vira uma linha
/// arrastável (alça própria, o resto da linha não inicia o drag) com um
/// `Switch` para mostrar/ocultar. Toda mudança aqui passa por
/// [layoutController], a mesma instância que a aba Dashboard escuta — o que
/// já a atualiza instantaneamente, mesmo antes do usuário voltar para ela.
class GerenciadorLayoutPage extends StatefulWidget {
  const GerenciadorLayoutPage({super.key});

  @override
  State<GerenciadorLayoutPage> createState() => _GerenciadorLayoutPageState();
}

class _GerenciadorLayoutPageState extends State<GerenciadorLayoutPage> {
  @override
  void initState() {
    super.initState();
    layoutController.addListener(_onLayoutChanged);
  }

  @override
  void dispose() {
    layoutController.removeListener(_onLayoutChanged);
    super.dispose();
  }

  void _onLayoutChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final layout = layoutController.layout;

    return Theme(
      data: getDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(title: Text(i18n.tr('dashboard.reorder_title'))),
        body: layout == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(
                      i18n.tr('dashboard.reorder_subtitle'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      buildDefaultDragHandles: false,
                      itemCount: layout.ordem.length,
                      onReorderItem: layoutController.atualizarOrdemBlocos,
                      proxyDecorator: _proxyDecorator,
                      itemBuilder: (context, index) {
                        final id = layout.ordem[index];
                        return _BlocoLayoutTile(
                          key: ValueKey(id),
                          index: index,
                          id: id,
                          ativo: layout.isAtivo(id),
                          onChanged: (ativo) => layoutController
                              .alternarVisibilidadeBloco(id.id, ativo),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Feedback visual sutil enquanto o card é arrastado: leve escala +
  /// sombra crescente, interpolados pela própria animação que o
  /// [ReorderableListView] já fornece — sem precisar de um
  /// `AnimationController` adicional.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        final elevation = lerpDouble(0, 12, t)!;
        final scale = lerpDouble(1, 1.03, t)!;
        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: elevation,
            shadowColor: Colors.black87,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Uma linha do gerenciador: alça de arrastar, título/descrição do card e
/// um `Switch` de visibilidade. Blocos ocultos ficam com opacidade
/// reduzida — reforço visual imediato de "isto está desligado", sem
/// precisar ler o estado do switch.
class _BlocoLayoutTile extends StatelessWidget {
  const _BlocoLayoutTile({
    super.key,
    required this.index,
    required this.id,
    required this.ativo,
    required this.onChanged,
  });

  final int index;
  final DashboardWidgetId id;
  final bool ativo;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: ativo ? 1.0 : 0.55,
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 4, right: 16),
            leading: ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.drag_indicator, color: AppColors.mutedText),
              ),
            ),
            title: Text(
              i18n.tr(DashboardWidgetFactory.titleKeyFor(id)),
              style: const TextStyle(
                color: AppColors.lightText,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              i18n.tr(DashboardWidgetFactory.descriptionKeyFor(id)),
              style: const TextStyle(color: AppColors.mutedText, fontSize: 12),
            ),
            trailing: Switch(
              value: ativo,
              activeThumbColor: AppColors.primaryGold,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}
