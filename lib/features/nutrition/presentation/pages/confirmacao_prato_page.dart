import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/favorita_model.dart';
import '../../data/models/prato_refeicao_extracao_model.dart';
import '../../data/repositories/favoritas_repository.dart';
import '../controllers/confirmacao_prato_controller.dart';
import '../widgets/dialogo_nome_tipo_favorita.dart';

/// Identifica que esta tela está editando o CONTEÚDO de uma favorita já
/// salva (RELATÓRIO 20260823 — 2º gap encontrado pelo fundador testando:
/// "trocar tipo"/"excluir" existiam, editar itens/quantidades nunca tinha
/// sido implementado). Passado por [FavoritasPage] ao abrir uma favorita
/// para editar — muda o rótulo do botão de salvar e, principalmente,
/// redireciona [ConfirmacaoPratoController.confirmar] para
/// [FavoritasRepository.atualizarPayload] em vez de registrar uma refeição
/// nova em `coleta_diaria`. Reaproveita TODA a tela de edição de itens
/// (incrementar/decrementar/editar peso/remover) já construída para o F10
/// Passo 3 — o formato de [ConfirmacaoPratoController.payloadRevisado] é
/// exatamente o mesmo que [FavoritaModel.payloadJsonb] já usa.
class FavoritaEmEdicao {
  const FavoritaEmEdicao({required this.id});

  final String id;
}

/// Tela de Confirmação do Prato (F10 Passo 3 + F34, Parte 11.3 — "IA estima
/// + usuário edita"): recebe a extração já calculada pelo backend
/// ([PratoRefeicaoExtracaoModel]), deixa o usuário revisar, e ao confirmar
/// grava em `coleta_diaria` via [ConfirmacaoPratoController.confirmar].
/// "Completa funcionalmente, crua visualmente" (Parte 8): todo botão (editar
/// quantidade, remover, confirmar) funciona de ponta a ponta; nenhum
/// polimento visual além do mínimo (`Card`/`ListTile`).
class ConfirmacaoPratoPage extends StatefulWidget {
  const ConfirmacaoPratoPage({
    super.key,
    required this.extracao,
    this.controller,
    this.favoritaEmEdicao,
    FavoritasRepository? favoritasRepository,
  }) : _favoritasRepository = favoritasRepository;

  final PratoRefeicaoExtracaoModel extracao;

  /// Injetável em teste — mesmo padrão de [GerirVinculosPage]/[ManualFoodSearchPage].
  final ConfirmacaoPratoController? controller;

  /// Não-nulo quando esta tela está editando o CONTEÚDO de uma favorita já
  /// salva (ver doc de [FavoritaEmEdicao]) — [FavoritasPage] é quem passa
  /// isto ao abrir "Editar" no menu de uma favorita.
  final FavoritaEmEdicao? favoritaEmEdicao;

  final FavoritasRepository? _favoritasRepository;

  @override
  State<ConfirmacaoPratoPage> createState() => _ConfirmacaoPratoPageState();
}

class _ConfirmacaoPratoPageState extends State<ConfirmacaoPratoPage> {
  late final FavoritasRepository _favoritasRepository =
      widget._favoritasRepository ?? FavoritasRepository();
  late final ConfirmacaoPratoController _controller = widget.controller ??
      ConfirmacaoPratoController(
        widget.extracao,
        aoConfirmar: widget.favoritaEmEdicao == null
            ? null
            : (payload, _) => _favoritasRepository.atualizarPayload(
                  widget.favoritaEmEdicao!.id,
                  payload,
                ),
      );
  late final bool _controllerEhProprio = widget.controller == null;

  @override
  void dispose() {
    if (_controllerEhProprio) _controller.dispose();
    super.dispose();
  }

  /// N13 (RELATÓRIO 20260821) — "marcar como favorita ao registrar
  /// (seleciona o tipo)": diálogo pede tipo de refeição + nome, salva
  /// [ConfirmacaoPratoController.payloadRevisado] inteiro (itens + totais)
  /// como está NAQUELE MOMENTO — inclui qualquer edição de quantidade/peso
  /// já feita, "com a medida customizada", como a spec pede. Independente
  /// de confirmar a refeição em si (o usuário pode favoritar sem
  /// registrar, ou registrar sem favoritar).
  Future<void> _salvarComoFavorita() async {
    final resultado = await showDialog<({TipoRefeicao tipo, String nome})>(
      context: context,
      builder: (context) => const DialogoNomeTipoFavorita(),
    );
    if (resultado == null || !mounted) return;

    final salvo = await _favoritasRepository.salvar(
      nome: resultado.nome,
      tipoRefeicao: resultado.tipo,
      payloadJsonb: _controller.payloadRevisado(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            salvo.success
                ? i18n.tr('confirmacao_prato.favorita_save_success')
                : (salvo.errorMessage ?? i18n.tr('confirmacao_prato.favorita_save_error')),
          ),
          backgroundColor: salvo.success ? AppColors.success : AppColors.error,
        ),
      );
  }

  /// F34: grava em `coleta_diaria` e só então sai da tela — o
  /// `SnackBar` de sucesso é mostrado ANTES do pop (senão o
  /// `ScaffoldMessenger` desta tela some junto com ela) e a navegação
  /// espera sua duração mínima, para o usuário realmente ver a confirmação
  /// em vez de "piscar". Em falha, a tela permanece — o erro (e, em debug,
  /// o detalhe técnico real) aparece via [_ErroSalvarBanner] e o usuário
  /// pode tentar de novo sem perder as edições.
  Future<void> _confirmar() async {
    final sucesso = await _controller.confirmar();
    if (!mounted || !sucesso) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.favoritaEmEdicao == null
              ? i18n.tr('confirmacao_prato.save_success')
              : i18n.tr('confirmacao_prato.favorita_atualizada_sucesso'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final editandoFavorita = widget.favoritaEmEdicao != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          editandoFavorita
              ? i18n.tr('confirmacao_prato.editar_favorita_title')
              : i18n.tr('confirmacao_prato.title'),
        ),
        // Botão ⭐ ("salvar como NOVA favorita") só faz sentido ao confirmar
        // uma refeição normal — editando o conteúdo de uma favorita já
        // existente, o botão "Salvar alterações" já sobrescreve ELA MESMA
        // (ver [FavoritaEmEdicao]); manter o ⭐ aqui criaria uma segunda
        // favorita duplicada em vez de atualizar a atual.
        actions: editandoFavorita
            ? null
            : [
                ValueListenableBuilder<ConfirmacaoPratoState>(
                  valueListenable: _controller,
                  builder: (context, state, _) => IconButton(
                    icon: const Icon(Icons.star_outline),
                    tooltip: i18n.tr('confirmacao_prato.favorita_button'),
                    onPressed: state.itens.isEmpty ? null : _salvarComoFavorita,
                  ),
                ),
              ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<ConfirmacaoPratoState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            return Column(
              children: [
                if (state.possivelFotoDeTela) const _AvisoPossivelFotoDeTela(),
                if (state.erroSalvar != null)
                  _ErroSalvarBanner(
                    mensagem: state.erroSalvar!,
                    debugDetalhe: state.debugDetalheErroSalvar,
                  ),
                Expanded(child: _buildLista(context, state)),
                _TotaisBar(state: state),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: (state.itens.isEmpty || state.salvando) ? null : _confirmar,
                    child: state.salvando
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
                        : Text(
                            editandoFavorita
                                ? i18n.tr('confirmacao_prato.salvar_alteracoes_button')
                                : i18n.tr('confirmacao_prato.confirm_button'),
                          ),
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
            controller: _controller,
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

class _ErroSalvarBanner extends StatelessWidget {
  const _ErroSalvarBanner({required this.mensagem, this.debugDetalhe});

  final String mensagem;
  final String? debugDetalhe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mensagem,
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          // Só aparece em build de debug/homolog (ver _podeExibirDetalheTecnico
          // no controller) — nunca em produção. Regra 0.15: o erro real por
          // trás da mensagem amigável acima, para quem está depurando.
          if (debugDetalhe != null) ...[
            const SizedBox(height: 6),
            Text(
              debugDetalhe!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemPratoTile extends StatefulWidget {
  const _ItemPratoTile({
    required this.item,
    required this.controller,
    required this.onIncrementar,
    required this.onDecrementar,
    required this.onRemover,
  });

  final ItemPratoEditavel item;
  final ConfirmacaoPratoController controller;
  final VoidCallback onIncrementar;
  final VoidCallback onDecrementar;
  final VoidCallback onRemover;

  @override
  State<_ItemPratoTile> createState() => _ItemPratoTileState();
}

class _ItemPratoTileState extends State<_ItemPratoTile> {
  String _formatarQuantidade(double quantidade) =>
      quantidade % 1 == 0 ? quantidade.toStringAsFixed(0) : quantidade.toStringAsFixed(1);

  void _mostrarDialogoEditarPeso(BuildContext context, ItemPratoEditavel item) {
    final controller = TextEditingController(
      text: (item.pesoPersonalizadoGramas ?? item.original.pesoTipicoGramas ?? 100).toStringAsFixed(0),
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(i18n.tr('confirmacao_prato.editar_peso')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Item: ${item.original.nomeIdentificado}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: i18n.tr('confirmacao_prato.peso_gramas'),
                suffix: const Text('g'),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: Text(i18n.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () {
              final novoGramas = double.tryParse(controller.text) ?? 100;
              widget.controller.editarPeso(item.chave, novoGramas);
              Navigator.of(context).pop();
            },
            child: Text(i18n.tr('common.save')),
          ),
        ],
      ),
    );
  }

  Widget _buildContenudoEstimado(BuildContext context, ItemPratoEditavel item) {
    final categoria = item.original.categoriaConsumo;
    final medidaPadraoQtd = item.original.medidaPadraoQtd?.toInt() ?? 0;
    final medidaPadraoNome = item.original.medidaPadraoNome ?? '';

    /// Renderização condicional baseada em categoria_consumo
    if (categoria == 'liquido_frio') {
      return _buildBotoesLiquidoFrio(context, item);
    } else if (categoria == 'liquido_quente') {
      return _buildBotoesLiquidoQuente(context, item);
    } else if (categoria == 'unidade' || categoria == 'fatia') {
      return _buildTextoUnidadeOuFatia(context, item, categoria, medidaPadraoQtd, medidaPadraoNome);
    } else {
      // null ou 'peso_livre' — fallback genérico
      return _buildAvisoGenericoComEdicao(context, item);
    }
  }

  /// Líquidos frios: água, suco, refrigerante, leite
  /// Oferece 3 tamanhos padrão: pequeno (200ml), médio (500ml), grande (700ml)
  Widget _buildBotoesLiquidoFrio(BuildContext context, ItemPratoEditavel item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tamanho do ${item.original.medidaPadraoNome ?? 'copo'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _botaoTamanho(context, item, 'Pequeno', 200),
              _botaoTamanho(context, item, 'Médio', 500),
              _botaoTamanho(context, item, 'Grande', 700),
              _botaoEditarCustomizado(context, item, 'ml'),
            ],
          ),
        ],
      ),
    );
  }

  /// Líquidos quentes: café, chá
  /// Oferece 2 tamanhos: xícara café (50ml), xícara chá (200ml)
  Widget _buildBotoesLiquidoQuente(BuildContext context, ItemPratoEditavel item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tamanho da ${item.original.medidaPadraoNome ?? 'xícara'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _botaoTamanho(context, item, 'Café (50ml)', 50),
              _botaoTamanho(context, item, 'Chá (200ml)', 200),
              _botaoEditarCustomizado(context, item, 'ml'),
            ],
          ),
        ],
      ),
    );
  }

  /// Unidades ou fatias: azeitona, presunto, queijo, etc.
  /// Exibe informação descritiva + opção de edição manual
  Widget _buildTextoUnidadeOuFatia(
    BuildContext context,
    ItemPratoEditavel item,
    String? categoria,
    int medidaPadraoQtd,
    String medidaPadraoNome,
  ) {
    final tipo = categoria == 'unidade' ? 'Unidade' : 'Fatia';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 $tipo${medidaPadraoNome.isNotEmpty ? ' ($medidaPadraoNome)' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (medidaPadraoQtd > 0)
                  Text(
                    '≈ ${medidaPadraoQtd}g',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => _mostrarDialogoEditarPeso(context, item),
            child: Text(
              i18n.tr('common.edit'),
              style: TextStyle(
                fontSize: 11,
                color: Colors.green.shade900,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fallback genérico: alimento sem categoria (null) ou peso_livre
  /// Aviso amarelo com opção de edição manual
  Widget _buildAvisoGenericoComEdicao(BuildContext context, ItemPratoEditavel item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.amber.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.tr('confirmacao_prato.quantidade_estimada_aviso'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.original.pesoTipicoGramas != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${i18n.tr('confirmacao_prato.peso_tipico')}: ${item.original.pesoTipicoGramas}g',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade800,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => _mostrarDialogoEditarPeso(context, item),
                        child: Text(
                          i18n.tr('common.edit'),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Botão rápido de tamanho (para líquidos)
  Widget _botaoTamanho(BuildContext context, ItemPratoEditavel item, String label, int qtd) {
    final isCustomizado = item.pesoPersonalizadoGramas == qtd.toDouble();
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: isCustomizado ? Colors.blue.shade200 : Colors.blue.shade100,
      ),
      onPressed: () {
        widget.controller.editarPeso(item.chave, qtd.toDouble());
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isCustomizado ? Colors.blue.shade900 : Colors.blue.shade700,
          fontWeight: isCustomizado ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  /// Botão "Customizar" para entrada manual
  Widget _botaoEditarCustomizado(BuildContext context, ItemPratoEditavel item, String unidade) {
    return OutlinedButton(
      onPressed: () => _mostrarDialogoEditarPeso(context, item),
      child: Text(
        'Customizar',
        style: TextStyle(fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            original.nomeIdentificado,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (original.quantidadeEstimada ?? false)
                            Text(
                              ' (${item.pesoPersonalizadoGramas?.toStringAsFixed(0) ?? original.pesoTipicoGramas ?? '?'}g ${item.pesoPersonalizadoGramas != null ? 'edit.' : 'est.'})',
                              style: TextStyle(
                                fontSize: 12,
                                color: item.pesoPersonalizadoGramas != null ? Colors.green.shade700 : Colors.amber.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      if (original.nomeCasado != original.nomeIdentificado)
                        Text(
                          original.nomeCasado,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: i18n.tr('confirmacao_prato.remove_item'),
                  onPressed: widget.onRemover,
                ),
              ],
            ),
            Text(
              i18n.tr(
                'confirmacao_prato.confianca',
                params: {'percentual': (original.confianca * 100).round().toString()},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (original.quantidadeEstimada ?? false) ...[
              const SizedBox(height: 8),
              _buildContenudoEstimado(context, item),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              spacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: i18n.tr('confirmacao_prato.decrement'),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      onPressed: widget.onDecrementar,
                    ),
                    Text('${_formatarQuantidade(item.quantidadeAtual)} ${original.medida}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: i18n.tr('confirmacao_prato.increment'),
                      iconSize: 20,
                      padding: EdgeInsets.zero,
                      onPressed: widget.onIncrementar,
                    ),
                  ],
                ),
                // RELATÓRIO 20260821 — ACHADO REAL: `Flexible` não pode ser
                // filho direto de `Wrap` (só de `Row`/`Column`/`Flex`) —
                // `Wrap` usa `WrapParentData`, `Flexible` exige
                // `FlexParentData`. Isso derrubava a tela INTEIRA com
                // "Incorrect use of ParentDataWidget" toda vez que este
                // card renderizava (confirmado isolando numa worktree
                // limpa do HEAD — bug pré-existente, não introduzido nesta
                // tarefa). `Text` direto: `Wrap` já dá a cada filho uma
                // constraint de largura própria, `overflow`/`maxLines`
                // continuam funcionando sem precisar de `Flexible`.
                Text(
                  i18n.tr('confirmacao_prato.macros_resumo', params: {
                    'calorias': item.calorias.toStringAsFixed(0),
                    'proteinas': item.proteinasG.toStringAsFixed(1),
                    'carboidratos': item.carboidratosG.toStringAsFixed(1),
                    'gorduras': item.gordurasG.toStringAsFixed(1),
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
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

// N13 (RELATÓRIO 20260821) — o diálogo "nome + tipo" de favorita foi
// extraído para DialogoNomeTipoFavorita (RELATÓRIO 20260823), reaproveitado
// também por CriarFavoritaPage. Ver widgets/dialogo_nome_tipo_favorita.dart.
