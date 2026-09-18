import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/anamnese_models.dart';

/// Definição de um campo opcional extra do modal "Adicionar" (além do nome,
/// que é sempre obrigatório) — Blocos 9/10/11 (Medicamentos/Suplementos/
/// Exames) têm cada um uns 2-3 campos próprios além do nome.
class CampoExtra {
  final String chave;
  final String label;
  final TextInputType tipo;

  const CampoExtra({required this.chave, required this.label, this.tipo = TextInputType.text});
}

/// Bloco 9/10/11 — lista de cartões repetível genérica (Medicamentos,
/// Suplementos, Exames Laboratoriais compartilham a mesma forma). UX
/// Global: adicionar item abre um `AlertDialog` com Cancelar/Confirmar
/// explícitos (mesmo padrão já usado em `_ModalAdicionarAtividade`).
class ListaRepetivelWidget extends StatelessWidget {
  const ListaRepetivelWidget({
    super.key,
    required this.titulo,
    required this.vazioTexto,
    required this.addButtonTexto,
    required this.modalTitulo,
    required this.itens,
    required this.camposExtras,
    required this.onAdicionar,
    required this.onRemover,
    required this.habilitado,
  });

  final String titulo;
  final String vazioTexto;
  final String addButtonTexto;
  final String modalTitulo;
  final List<ItemRepetivel> itens;
  final List<CampoExtra> camposExtras;
  final ValueChanged<ItemRepetivel> onAdicionar;
  final ValueChanged<ItemRepetivel> onRemover;
  final bool habilitado;

  Future<void> _abrirModal(BuildContext context) async {
    final resultado = await showDialog<ItemRepetivel>(
      context: context,
      builder: (_) => _ModalAdicionarItem(titulo: modalTitulo, camposExtras: camposExtras),
    );
    if (resultado != null) onAdicionar(resultado);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleMedium),
        if (itens.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(vazioTexto, style: Theme.of(context).textTheme.bodySmall),
          )
        else
          for (final item in itens)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.nome),
              subtitle: item.campos.isEmpty
                  ? null
                  : Text(item.campos.entries.map((e) => '${e.key}: ${e.value}').join(' · ')),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: habilitado ? () => onRemover(item) : null,
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: habilitado ? () => _abrirModal(context) : null,
            icon: const Icon(Icons.add),
            label: Text(addButtonTexto),
          ),
        ),
      ],
    );
  }
}

class _ModalAdicionarItem extends StatefulWidget {
  const _ModalAdicionarItem({required this.titulo, required this.camposExtras});

  final String titulo;
  final List<CampoExtra> camposExtras;

  @override
  State<_ModalAdicionarItem> createState() => _ModalAdicionarItemState();
}

class _ModalAdicionarItemState extends State<_ModalAdicionarItem> {
  final _nomeController = TextEditingController();
  final Map<String, TextEditingController> _extrasControllers = {};
  String? _erroNome;

  @override
  void initState() {
    super.initState();
    for (final campo in widget.camposExtras) {
      _extrasControllers[campo.chave] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    for (final controller in _extrasControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _confirmar() {
    final nome = _nomeController.text.trim();
    if (nome.isEmpty) {
      setState(() => _erroNome = i18n.tr('nutricao.item_repetivel_modal_nome_obrigatorio'));
      return;
    }

    final campos = <String, String>{};
    for (final campo in widget.camposExtras) {
      final valor = _extrasControllers[campo.chave]?.text.trim() ?? '';
      if (valor.isNotEmpty) campos[campo.chave] = valor;
    }

    Navigator.of(context).pop(ItemRepetivel(nome: nome, campos: campos));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nomeController,
              decoration: InputDecoration(labelText: i18n.tr('nutricao.medicamentos_modal_nome_label'), errorText: _erroNome),
              onChanged: (_) {
                if (_erroNome != null) setState(() => _erroNome = null);
              },
            ),
            for (final campo in widget.camposExtras) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _extrasControllers[campo.chave],
                keyboardType: campo.tipo,
                decoration: InputDecoration(labelText: campo.label),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.tr('nutricao.item_repetivel_modal_cancel')),
        ),
        FilledButton(onPressed: _confirmar, child: Text(i18n.tr('nutricao.item_repetivel_modal_confirm'))),
      ],
    );
  }
}
