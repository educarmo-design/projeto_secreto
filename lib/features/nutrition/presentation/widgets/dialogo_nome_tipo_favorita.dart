import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/favorita_model.dart';

String rotuloTipoRefeicao(TipoRefeicao tipo) {
  switch (tipo) {
    case TipoRefeicao.cafeDaManha:
      return i18n.tr('confirmacao_prato.tipo_refeicao_cafe_da_manha');
    case TipoRefeicao.almoco:
      return i18n.tr('confirmacao_prato.tipo_refeicao_almoco');
    case TipoRefeicao.lanche:
      return i18n.tr('confirmacao_prato.tipo_refeicao_lanche');
    case TipoRefeicao.jantar:
      return i18n.tr('confirmacao_prato.tipo_refeicao_jantar');
  }
}

/// Diálogo "nome + tipo de refeição" de uma favorita — nome e tipo SEMPRE
/// obrigatórios (spec N13: favoritas sempre categorizadas, nunca inferido do
/// primeiro item). Extraído de `ConfirmacaoPratoPage` (RELATÓRIO 20260821)
/// para reaproveitar aqui: usado tanto ao favoritar uma refeição já
/// confirmada quanto ao criar uma favorita do zero em [CriarFavoritaPage]
/// (RELATÓRIO 20260823) — mesma pergunta, dois pontos de entrada diferentes,
/// um só diálogo. `Navigator.pop` devolve `null` se cancelado, ou o par
/// (tipo, nome) se confirmado.
class DialogoNomeTipoFavorita extends StatefulWidget {
  const DialogoNomeTipoFavorita({super.key, this.titulo, this.nomeInicial, this.tipoInicial});

  /// Título do diálogo — por padrão o mesmo texto do botão ⭐ de
  /// `ConfirmacaoPratoPage`. Sobrescrito por [CriarFavoritaPage] com um
  /// texto mais adequado ao contexto ("nova favorita", não "salvar como").
  final String? titulo;

  final String? nomeInicial;
  final TipoRefeicao? tipoInicial;

  @override
  State<DialogoNomeTipoFavorita> createState() => _DialogoNomeTipoFavoritaState();
}

class _DialogoNomeTipoFavoritaState extends State<DialogoNomeTipoFavorita> {
  late final _nomeController = TextEditingController(text: widget.nomeInicial ?? '');
  late TipoRefeicao? _tipoSelecionado = widget.tipoInicial;

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nomeVazio = _nomeController.text.trim().isEmpty;
    return AlertDialog(
      title: Text(widget.titulo ?? i18n.tr('confirmacao_prato.favorita_dialog_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nomeController,
            decoration: InputDecoration(
              labelText: i18n.tr('confirmacao_prato.favorita_nome_label'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(i18n.tr('confirmacao_prato.favorita_tipo_label')),
          RadioGroup<TipoRefeicao>(
            groupValue: _tipoSelecionado,
            onChanged: (valor) => setState(() => _tipoSelecionado = valor),
            child: Column(
              children: [
                for (final tipo in TipoRefeicao.values)
                  RadioListTile<TipoRefeicao>(
                    contentPadding: EdgeInsets.zero,
                    value: tipo,
                    title: Text(rotuloTipoRefeicao(tipo)),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: (nomeVazio || _tipoSelecionado == null)
              ? null
              : () => Navigator.of(context).pop((
                    tipo: _tipoSelecionado!,
                    nome: _nomeController.text.trim(),
                  )),
          child: Text(i18n.tr('confirmacao_prato.favorita_save_button')),
        ),
      ],
    );
  }
}
