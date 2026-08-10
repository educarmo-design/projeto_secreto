import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/dashboard/data/models/health_payload_model.dart';

void main() {
  group('HealthPayloadModel.fromJson/toJson — fc_maxima (RELATÓRIO 20260810_0005)', () {
    // BUG desta tarefa: fc_maxima é gravado em metricas_saude_diarias desde
    // a tarefa anterior (HealthSyncService._mesclarPorDia), mas o campo
    // nunca foi adicionado a este model — TelemetriaHistoricoRepository lê
    // de volta via HealthPayloadModel.fromJson, então o valor era
    // descartado em silêncio antes de chegar na tela, mesmo com o SELECT
    // trazendo a coluna certinha do banco.
    test('fromJson lê fc_maxima da linha do banco', () {
      final payload = HealthPayloadModel.fromJson({
        'data_referencia': '2026-08-08',
        'fc_maxima': 172,
      });

      expect(payload.fcMaxima, 172);
    });

    test('toJson grava fc_maxima de volta quando presente', () {
      final payload = HealthPayloadModel(
        fcMaxima: 172,
        dateFrom: DateTime(2026, 8, 8),
        dateTo: DateTime(2026, 8, 8),
        source: 'wearable',
      );

      expect(payload.toJson()['fc_maxima'], 172);
    });

    test('fromJson sem fc_maxima na linha devolve null, não quebra', () {
      final payload = HealthPayloadModel.fromJson({
        'data_referencia': '2026-08-08',
      });

      expect(payload.fcMaxima, isNull);
    });
  });
}
