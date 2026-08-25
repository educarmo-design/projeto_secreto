import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import 'descrever_refeicao_page.dart';
import 'favoritas_page.dart';
import 'gravar_refeicao_page.dart';

/// RELATÓRIO 20260824_0003 — porta de entrada única do Registro de
/// Refeição (Documento Mestre): 4 métodos, um ícone cada. Alcançável pelo
/// botão novo na AppBar (ao lado do de hidratação) E pelo widget do
/// dashboard (`MetodosRegistroRefeicaoCard`) — os dois levam pra cá, essa
/// tela não se repete em dois lugares.
///
/// Métodos 1 (descrever) e 2 (falar) navegam pra suas próprias telas, que
/// terminam em `ConfirmacaoPratoPage` (igual à foto). Método 3
/// (favoritos) navega pra `FavoritasPage` já existente — usar uma
/// favorita agora também passa por revisão (RELATÓRIO 20260824_0003,
/// decisão do fundador: consistente com os outros 3 métodos). Método 4
/// (foto) é o único que precisa de algo do CHAMADOR (a câmera já é
/// orquestrada por `main_navigation_page.dart`/`CameraCaptureController`)
/// — por isso [onFotoPrato] é injetado, os outros 3 não precisam de nada
/// de fora.
class EscolherMetodoRefeicaoPage extends StatelessWidget {
  const EscolherMetodoRefeicaoPage({super.key, required this.onFotoPrato});

  final Future<void> Function() onFotoPrato;

  Future<void> _abrir(BuildContext context, Widget pagina) async {
    final registrado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => pagina),
    );
    if (registrado == true && context.mounted) {
      Navigator.of(context).pop(true); // avisa quem abriu esta tela pra recarregar
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('escolher_metodo_refeicao.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _MetodoTile(
                icon: Icons.edit_note,
                labelKey: 'escolher_metodo_refeicao.descrever',
                onTap: () => _abrir(context, const DescreverRefeicaoPage()),
              ),
              _MetodoTile(
                icon: Icons.mic_none,
                labelKey: 'escolher_metodo_refeicao.falar',
                onTap: () => _abrir(context, const GravarRefeicaoPage()),
              ),
              _MetodoTile(
                icon: Icons.star_outline,
                labelKey: 'escolher_metodo_refeicao.favoritos',
                onTap: () => _abrir(context, const FavoritasPage()),
              ),
              _MetodoTile(
                icon: Icons.camera_alt_outlined,
                labelKey: 'escolher_metodo_refeicao.fotografar',
                onTap: () async {
                  await onFotoPrato();
                  if (context.mounted) Navigator.of(context).pop(true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão grande com ícone — mesmo espírito "completo funcionalmente, cru
/// visualmente" dos outros cards deste projeto.
class _MetodoTile extends StatelessWidget {
  const _MetodoTile({required this.icon, required this.labelKey, required this.onTap});

  final IconData icon;
  final String labelKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: AppColors.primaryGold),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                i18n.tr(labelKey),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
