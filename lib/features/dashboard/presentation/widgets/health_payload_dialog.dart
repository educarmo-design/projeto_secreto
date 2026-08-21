import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../nutrition/data/repositories/coleta_diaria_repository.dart';
import '../../data/models/health_payload_model.dart';
import '../controllers/camera_capture_controller.dart' show TipoAparelho;

/// N15 (RELATÓRIO 20260820) — mapeia [TipoAparelho] pro `atributo` texto
/// livre de `coleta_diaria` (ver comentário de cabeçalho da migration F34).
/// `pratoRefeicao`/`rotulo` nunca chegam aqui — [mostrarDialogoConfirmarLeituraAparelho]
/// só é chamado pelos 3 tipos que produzem um [HealthPayloadModel] de
/// verdade (ver [CameraCaptureController]).
String _atributoParaTipoAparelho(TipoAparelho tipo) {
  switch (tipo) {
    case TipoAparelho.balanca:
      return 'balanca';
    case TipoAparelho.pressaoArterial:
      return 'pressao_arterial';
    case TipoAparelho.glicosimetro:
      return 'glicosimetro';
    case TipoAparelho.pratoRefeicao:
    case TipoAparelho.rotulo:
      throw ArgumentError(
        '$tipo nunca deveria chegar em mostrarDialogoConfirmarLeituraAparelho — '
        'esses 2 tipos têm fluxo de confirmação próprio, não produzem '
        'HealthPayloadModel.',
      );
  }
}

/// Diálogo de resultado de [CameraCaptureView] pra balança/pressão
/// arterial/glicosímetro — usado por [RegistrarMetricaPage],
/// [SeniorDashboardPage] e [MainNavigationPage] pra manter cópia/layout
/// idênticos em todo canto que uma foto de aparelho é extraída.
///
/// N15 — ACHADO REAL (RELATÓRIO 20260820, não suposição): até esta tarefa,
/// o botão "Confirmar" só dava `Navigator.pop()` — nenhuma chamada ao
/// Supabase em lugar nenhum. O dado extraído se perdia ao fechar o
/// diálogo, mesmo o usuário "confirmando". Agora, ao confirmar, grava em
/// `coleta_diaria` via [ColetaDiariaRepository.gravarLeituraAparelho] e
/// mostra um snack de sucesso/erro — mesmo padrão de feedback de
/// [RegistroHidratacaoPage].
Future<void> mostrarDialogoConfirmarLeituraAparelho(
  BuildContext context, {
  required HealthPayloadModel payload,
  required TipoAparelho tipoAparelho,
  ColetaDiariaRepository? repository,
}) async {
  final confirmado = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(i18n.tr('dashboard.camera_result_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: payload.camposPreenchidos
                .map((e) => Text('${e.key}: ${e.value}'))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(i18n.tr('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(i18n.tr('dashboard.camera_confirm_button')),
            ),
          ],
        ),
      ) ??
      false; // fechado pelo botão voltar/toque fora = mesmo que cancelar

  if (!confirmado || !context.mounted) return;

  final repo = repository ?? ColetaDiariaRepository();
  final resultado = await repo.gravarLeituraAparelho(
    payload: payload,
    atributo: _atributoParaTipoAparelho(tipoAparelho),
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          resultado.success
              ? i18n.tr('dashboard.camera_save_success')
              : (resultado.errorMessage ?? i18n.tr('dashboard.camera_save_error')),
        ),
        backgroundColor: resultado.success ? AppColors.success : AppColors.error,
      ),
    );
}
