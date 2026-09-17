import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';

/// RELATÓRIO 20260917 — modal vermelho (Trava ANVISA / Hard Block) de
/// `validar_e_salvar_meta` (N08), extraído de `meta_bem_estar_page.dart`
/// pra ser reaproveitado por qualquer tela que grave uma meta
/// (`MetaBemEstarPage` e, a partir desta tarefa, a Seção B de
/// `ResultadoMotorMetabolicoPage`) — mesmo texto/aparência nas duas, sem
/// duplicar o `switch` de motivo→texto em dois arquivos.
Future<void> mostrarModalBloqueioMeta(BuildContext context, MetaBloqueadaException erro) async {
  final titulo = switch (erro.motivo) {
    MotivoBloqueioN08.travaClinica => i18n.tr('nutricao.meta_bloqueio_clinico_titulo'),
    MotivoBloqueioN08.prioridadeProfissional => i18n.tr('nutricao.meta_bloqueio_profissional_titulo'),
    MotivoBloqueioN08.carenciaMensal => i18n.tr('nutricao.meta_bloqueio_carencia_titulo'),
    MotivoBloqueioN08.outro => i18n.tr('nutricao.meta_save_error'),
  };
  final mensagem = switch (erro.motivo) {
    MotivoBloqueioN08.travaClinica => i18n.tr('nutricao.meta_bloqueio_clinico_mensagem'),
    MotivoBloqueioN08.prioridadeProfissional => i18n.tr('nutricao.meta_bloqueio_profissional_mensagem'),
    MotivoBloqueioN08.carenciaMensal => i18n.tr('nutricao.meta_bloqueio_carencia_mensagem'),
    MotivoBloqueioN08.outro => erro.mensagemOriginal,
  };

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.block, color: AppColors.error, size: 32),
      title: Text(titulo, style: const TextStyle(color: AppColors.error)),
      content: Text(mensagem),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(i18n.tr('nutricao.meta_bloqueio_confirmar')),
        ),
      ],
    ),
  );
}
