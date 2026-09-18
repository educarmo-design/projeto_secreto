import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/anamnese_models.dart';

/// UX Global (RELATÓRIO 20260918_0001, RESTRIÇÃO explícita: "Adicionar
/// confirmação explícita — botão Confirmar ou OK — para recolher todas as
/// listas e bottom sheets") — abre um bottom sheet com checkboxes e só
/// aplica a seleção quando o usuário toca em "Confirmar" (ou descarta ao
/// fechar sem confirmar, mesmo padrão do `_ModalAdicionarAtividade` já
/// existente, que já tinha Confirmar/Cancelar). Devolve `null` se
/// cancelado/fechado sem confirmar.
Future<Set<String>?> abrirSeletorMultiplo({
  required BuildContext context,
  required String titulo,
  required List<CatalogoItem> itens,
  required Set<String> selecionadosIniciais,
}) {
  final selecionados = Set<String>.from(selecionadosIniciais);

  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          for (final item in itens)
                            CheckboxListTile(
                              value: selecionados.contains(item.id),
                              title: Text(item.nome),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (marcado) => setState(() {
                                if (marcado ?? false) {
                                  selecionados.add(item.id);
                                } else {
                                  selecionados.remove(item.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(i18n.tr('nutricao.seletor_multiplo_cancelar')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(selecionados),
                          child: Text(i18n.tr('nutricao.seletor_multiplo_confirmar')),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// Botão-resumo que abre o bottom sheet acima — mostra "N selecionado(s)"
/// (ou "Nenhuma selecionada") em vez de uma lista sempre expandida na
/// tela, e um botão "Editar seleção" — a parte "recolher" da restrição de
/// UX Global.
class ResumoSelecaoMultipla extends StatelessWidget {
  const ResumoSelecaoMultipla({
    super.key,
    required this.label,
    required this.quantidadeSelecionada,
    required this.onEditar,
  });

  final String label;
  final int quantidadeSelecionada;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                quantidadeSelecionada == 0
                    ? i18n.tr('nutricao.seletor_multiplo_nenhum_selecionado')
                    : i18n.tr('nutricao.seletor_multiplo_selecionados_resumo', params: {'quantidade': quantidadeSelecionada.toString()}),
              ),
            ),
            TextButton(onPressed: onEditar, child: Text(i18n.tr('nutricao.seletor_multiplo_editar'))),
          ],
        ),
      ],
    );
  }
}
