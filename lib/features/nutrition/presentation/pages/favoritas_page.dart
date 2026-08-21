import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/favorita_model.dart';
import '../../data/repositories/coleta_diaria_repository.dart';
import '../../data/repositories/favoritas_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

String _rotuloTipo(TipoRefeicao tipo) {
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

/// N13 (Documento Mestre v7.0, Parte V1.H) — "buscar nas favoritas" (uma
/// das 3 formas de registrar refeição, junto com foto/digitando) E
/// "manutenção no perfil (excluir/trocar tipo)" — a MESMA tela cobre as
/// duas, cada favorita tem um menu com as 3 ações (usar/trocar tipo/
/// excluir). Regra 14: lista crua, sem card bonito.
///
/// "Favorita salva com a medida customizada e volta pronta" (spec): usar
/// uma favorita chama [ColetaDiariaRepository.gravarRefeicao] direto com
/// [FavoritaModel.payloadJsonb] — sem recalcular nada, sem passar pela
/// câmera/IA de novo.
class FavoritasPage extends StatefulWidget {
  const FavoritasPage({
    super.key,
    FavoritasRepository? favoritasRepository,
    ColetaDiariaRepository? coletaDiariaRepository,
  })  : _favoritasRepository = favoritasRepository,
        _coletaDiariaRepository = coletaDiariaRepository;

  final FavoritasRepository? _favoritasRepository;
  final ColetaDiariaRepository? _coletaDiariaRepository;

  @override
  State<FavoritasPage> createState() => _FavoritasPageState();
}

class _FavoritasPageState extends State<FavoritasPage> {
  late final FavoritasRepository _favoritasRepository =
      widget._favoritasRepository ?? FavoritasRepository();
  late final ColetaDiariaRepository _coletaDiariaRepository =
      widget._coletaDiariaRepository ?? ColetaDiariaRepository();

  _CargaStatus _status = _CargaStatus.carregando;
  List<FavoritaModel> _favoritas = const [];
  TipoRefeicao? _filtro;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final favoritas = await _favoritasRepository.listar(tipoRefeicao: _filtro);
      if (!mounted) return;
      setState(() {
        _favoritas = favoritas;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  void _mostrarSnack(String mensagem, {required bool sucesso}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: sucesso ? AppColors.success : AppColors.error,
        ),
      );
  }

  Future<void> _usarFavorita(FavoritaModel favorita) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.tr('favoritas.usar_dialog_title')),
        content: Text(
          i18n.tr('favoritas.usar_dialog_content', params: {'nome': favorita.nome}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(i18n.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(i18n.tr('favoritas.usar_button')),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _processando = true);
    final resultado = await _coletaDiariaRepository.gravarRefeicao(
      payloadRevisado: favorita.payloadJsonb,
      confianca: null,
    );
    if (!mounted) return;
    setState(() => _processando = false);

    if (resultado.success) {
      _mostrarSnack(i18n.tr('favoritas.usar_sucesso'), sucesso: true);
      Navigator.of(context).pop(true); // avisa quem abriu (ex.: Dashboard) pra recarregar
    } else {
      _mostrarSnack(
        resultado.errorMessage ?? i18n.tr('favoritas.usar_erro'),
        sucesso: false,
      );
    }
  }

  Future<void> _trocarTipo(FavoritaModel favorita) async {
    final novoTipo = await showDialog<TipoRefeicao>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(i18n.tr('favoritas.trocar_tipo_dialog_title')),
        children: [
          for (final tipo in TipoRefeicao.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(tipo),
              child: Text(_rotuloTipo(tipo)),
            ),
        ],
      ),
    );
    if (novoTipo == null || novoTipo == favorita.tipoRefeicao || !mounted) return;

    final resultado = await _favoritasRepository.atualizarTipo(favorita.id, novoTipo);
    if (!mounted) return;
    if (resultado.success) {
      _mostrarSnack(i18n.tr('favoritas.trocar_tipo_sucesso'), sucesso: true);
      await _carregar();
    } else {
      _mostrarSnack(
        resultado.errorMessage ?? i18n.tr('favoritas.trocar_tipo_erro'),
        sucesso: false,
      );
    }
  }

  Future<void> _excluir(FavoritaModel favorita) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.tr('favoritas.excluir_dialog_title')),
        content: Text(
          i18n.tr('favoritas.excluir_dialog_content', params: {'nome': favorita.nome}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(i18n.tr('common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(i18n.tr('favoritas.excluir_button')),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final resultado = await _favoritasRepository.excluir(favorita.id);
    if (!mounted) return;
    if (resultado.success) {
      _mostrarSnack(i18n.tr('favoritas.excluir_sucesso'), sucesso: true);
      await _carregar();
    } else {
      _mostrarSnack(
        resultado.errorMessage ?? i18n.tr('favoritas.excluir_erro'),
        sucesso: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('favoritas.title'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chipFiltro(null, i18n.tr('favoritas.filtro_todas')),
                    for (final tipo in TipoRefeicao.values)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _chipFiltro(tipo, _rotuloTipo(tipo)),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildCorpo(context)),
          ],
        ),
      ),
    );
  }

  Widget _chipFiltro(TipoRefeicao? tipo, String rotulo) {
    return ChoiceChip(
      label: Text(rotulo),
      selected: _filtro == tipo,
      onSelected: (_) {
        setState(() => _filtro = tipo);
        _carregar();
      },
    );
  }

  Widget _buildCorpo(BuildContext context) {
    if (_processando) return const Center(child: CircularProgressIndicator());
    switch (_status) {
      case _CargaStatus.carregando:
        return const Center(child: CircularProgressIndicator());
      case _CargaStatus.erro:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  i18n.tr('favoritas.load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _carregar, child: Text(i18n.tr('favoritas.retry_button'))),
              ],
            ),
          ),
        );
      case _CargaStatus.sucesso:
        if (_favoritas.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                i18n.tr('favoritas.empty_state'),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _favoritas.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final favorita = _favoritas[index];
            return ListTile(
              title: Text(favorita.nome),
              subtitle: Text(
                i18n.tr('favoritas.subtitulo', params: {
                  'tipo': _rotuloTipo(favorita.tipoRefeicao),
                  'calorias': favorita.caloriasTotais?.toStringAsFixed(0) ?? '—',
                  'itens': favorita.quantidadeItens.toString(),
                }),
              ),
              onTap: () => _usarFavorita(favorita),
              trailing: PopupMenuButton<String>(
                onSelected: (acao) {
                  if (acao == 'trocar_tipo') _trocarTipo(favorita);
                  if (acao == 'excluir') _excluir(favorita);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'trocar_tipo',
                    child: Text(i18n.tr('favoritas.trocar_tipo_button')),
                  ),
                  PopupMenuItem(
                    value: 'excluir',
                    child: Text(i18n.tr('favoritas.excluir_button')),
                  ),
                ],
              ),
            );
          },
        );
    }
  }
}
