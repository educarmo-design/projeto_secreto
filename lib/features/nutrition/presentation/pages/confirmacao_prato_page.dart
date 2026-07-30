import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/prato_refeicao_extracao_model.dart';
import '../controllers/confirmacao_prato_controller.dart';

/// Tela de Confirmação do Prato (F10 Passo 3, Parte 11.3 — "IA estima +
/// usuário edita"): recebe a extração já calculada pelo backend
/// ([PratoRefeicaoExtracaoModel]) e deixa o usuário revisar antes de
/// qualquer gravação. "Completa funcionalmente, crua visualmente" (Parte 8):
/// todo botão (editar quantidade, remover, confirmar) funciona de ponta a
/// ponta; nenhum polimento visual além do mínimo (`Card`/`ListTile`).
///
/// Nunca grava sozinha — [_confirmar] só imprime o payload revisado no
/// console (persistir é escopo do F34).
class ConfirmacaoPratoPage extends StatefulWidget {
  const ConfirmacaoPratoPage({super.key, required this.extracao, this.controller});

  final PratoRefeicaoExtracaoModel extracao;

  /// Injetável em teste — mesmo padrão de [GerirVinculosPage]/[ManualFoodSearchPage].
  final ConfirmacaoPratoController? controller;

  @override
  State<ConfirmacaoPratoPage> createState() => _ConfirmacaoPratoPageState();
}

class _ConfirmacaoPratoPageState extends State<ConfirmacaoPratoPage> {
  late final ConfirmacaoPratoController _controller =
      widget.controller ?? ConfirmacaoPratoController(widget.extracao);
  late final bool _controllerEhProprio = widget.controller == null;

  @override
  void dispose() {
    if (_controllerEhProprio) _controller.dispose();
    super.dispose();
  }

  void _confirmar() {
    final payload = _controller.payloadRevisado();
    // Critério de Aceite #6: gravação real é escopo do F34 — por ora, só
    // registra o payload final (já revisado pelo usuário) no console.
    debugPrint('ConfirmacaoPratoPage — payload revisado (F34 grava): $payload');
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('confirmacao_prato.title'))),
      body: SafeArea(
        child: ValueListenableBuilder<ConfirmacaoPratoState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            return Column(
              children: [
                if (state.possivelFotoDeTela) const _AvisoPossivelFotoDeTela(),
                Expanded(child: _buildLista(context, state)),
                _TotaisBar(state: state),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: state.itens.isEmpty ? null : _confirmar,
                    child: Text(i18n.tr('confirmacao_prato.confirm_button')),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLista(BuildContext context, ConfirmacaoPratoState state) {
    if (state.itens.isEmpty && state.itensNaoReconhecidos.isEmpty) {
      return Center(child: Text(i18n.tr('confirmacao_prato.empty_state')));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final item in state.itens)
          _ItemPratoTile(
            item: item,
            onIncrementar: () => _controller.incrementar(item.chave),
            onDecrementar: () => _controller.decrementar(item.chave),
            onRemover: () => _controller.remover(item.chave),
          ),
        if (state.itensNaoReconhecidos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            i18n.tr('confirmacao_prato.nao_reconhecidos_title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final item in state.itensNaoReconhecidos)
            _ItemNaoReconhecidoTile(item: item),
        ],
      ],
    );
  }
}

class _AvisoPossivelFotoDeTela extends StatelessWidget {
  const _AvisoPossivelFotoDeTela();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Text(
        i18n.tr('confirmacao_prato.possivel_foto_de_tela'),
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _ItemPratoTile extends StatelessWidget {
  const _ItemPratoTile({
    required this.item,
    required this.onIncrementar,
    required this.onDecrementar,
    required this.onRemover,
  });

  final ItemPratoEditavel item;
  final VoidCallback onIncrementar;
  final VoidCallback onDecrementar;
  final VoidCallback onRemover;

  String _formatarQuantidade(double quantidade) =>
      quantidade % 1 == 0 ? quantidade.toStringAsFixed(0) : quantidade.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final original = item.original;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    original.nomeCasado,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: i18n.tr('confirmacao_prato.remove_item'),
                  onPressed: onRemover,
                ),
              ],
            ),
            if (original.nomeCasado != original.nomeIdentificado)
              Text(
                i18n.tr(
                  'confirmacao_prato.identificado_como',
                  params: {'nome': original.nomeIdentificado},
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              i18n.tr(
                'confirmacao_prato.confianca',
                params: {'percentual': (original.confianca * 100).round().toString()},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: i18n.tr('confirmacao_prato.decrement'),
                      onPressed: onDecrementar,
                    ),
                    Text('${_formatarQuantidade(item.quantidadeAtual)} ${original.medida}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: i18n.tr('confirmacao_prato.increment'),
                      onPressed: onIncrementar,
                    ),
                  ],
                ),
                Text(
                  i18n.tr('confirmacao_prato.macros_resumo', params: {
                    'calorias': item.calorias.toStringAsFixed(0),
                    'proteinas': item.proteinasG.toStringAsFixed(1),
                    'carboidratos': item.carboidratosG.toStringAsFixed(1),
                    'gorduras': item.gordurasG.toStringAsFixed(1),
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemNaoReconhecidoTile extends StatelessWidget {
  const _ItemNaoReconhecidoTile({required this.item});

  final ItemPratoNaoReconhecidoModel item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.help_outline),
      title: Text('${item.nome} (${item.medida})'),
      subtitle: Text(i18n.tr('confirmacao_prato.motivo.${item.motivo}')),
    );
  }
}

class _TotaisBar extends StatelessWidget {
  const _TotaisBar({required this.state});

  final ConfirmacaoPratoState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        i18n.tr('confirmacao_prato.totais', params: {
          'calorias': state.totalCalorias.toStringAsFixed(0),
          'proteinas': state.totalProteinasG.toStringAsFixed(1),
          'carboidratos': state.totalCarboidratosG.toStringAsFixed(1),
          'gorduras': state.totalGordurasG.toStringAsFixed(1),
        }),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}
