import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/health_payload_model.dart';

/// Shared result dialog for a [HealthPayloadModel] extracted via
/// [CameraCaptureView] — used by both [RegistrarMetricaPage] and
/// [SeniorDashboardPage] so the confirm/cancel copy and layout stay
/// identical everywhere a device photo gets extracted.
Future<void> showExtractedDataDialog(
  BuildContext context,
  HealthPayloadModel payload,
) {
  return showDialog<void>(
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.tr('dashboard.camera_confirm_button')),
        ),
      ],
    ),
  );
}
