import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/services/health_sync_service.dart';

enum _TestePesoStatus { idle, carregando, sucesso, semDados, erro, precisaInstalar }

/// Tela crua de validação do pipeline Health Connect -> Peso (Adendo v5.1
/// §B: "validação = completa funcionalmente, crua visualmente" — sem
/// gráfico, sem histórico, só o dado bruto). Aberta via [Navigator.push] a
/// partir de Configurações, não uma rota do GoRouter — mesmo padrão de
/// [TesteFrequenciaCardiacaPage]/[CameraCaptureView]/`GerirVinculosPage`.
///
/// Reaproveita [HealthSyncService.lerPesoRecente] por inteiro — a mesma
/// checagem de instalação do Health Connect, o mesmo pedido de permissão
/// nativo (aqui, só `READ_WEIGHT`) e o mesmo tratamento de erro que
/// [HealthSyncService.sincronizarDeltaDiario] já usa em produção; esta tela
/// só chama, mostra o [HealthMetricPoint] mais recente cru, e para.
class TestePesoPage extends StatefulWidget {
  const TestePesoPage({super.key, HealthSyncService? service})
      : _service = service;

  final HealthSyncService? _service;

  @override
  State<TestePesoPage> createState() => _TestePesoPageState();
}

class _TestePesoPageState extends State<TestePesoPage> {
  late final HealthSyncService _service = widget._service ?? HealthSyncService();

  _TestePesoStatus _status = _TestePesoStatus.idle;
  HealthMetricPoint? _ultimaLeitura;
  String? _errorMessage;

  Future<void> _ler() async {
    setState(() => _status = _TestePesoStatus.carregando);

    final resultado = await _service.lerPesoRecente();

    if (!mounted) return;

    if (resultado.needsHealthConnectInstall) {
      setState(() {
        _status = _TestePesoStatus.precisaInstalar;
        _errorMessage = resultado.errorMessage;
      });
      return;
    }

    if (!resultado.granted) {
      setState(() {
        _status = _TestePesoStatus.erro;
        _errorMessage =
            resultado.errorMessage ?? i18n.tr('dashboard.health_sync_error');
      });
      return;
    }

    final ultima = HealthSyncService.ultimaLeituraOuNula(resultado.points);
    if (ultima == null) {
      setState(() => _status = _TestePesoStatus.semDados);
      return;
    }

    setState(() {
      _status = _TestePesoStatus.sucesso;
      _ultimaLeitura = ultima;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('dashboard.weight_test_title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                i18n.tr('dashboard.weight_test_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _status == _TestePesoStatus.carregando ? null : _ler,
                child: _status == _TestePesoStatus.carregando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(i18n.tr('dashboard.weight_test_button')),
              ),
              const SizedBox(height: 24),
              _buildResultado(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultado(BuildContext context) {
    switch (_status) {
      case _TestePesoStatus.idle:
      case _TestePesoStatus.carregando:
        return const SizedBox.shrink();

      case _TestePesoStatus.sucesso:
        final leitura = _ultimaLeitura!;
        return SelectableText(
          '${leitura.value.toStringAsFixed(1)} kg\n'
          'fonte: ${leitura.sourceApp.isEmpty ? "desconhecida" : leitura.sourceApp}\n'
          'registrado às: ${leitura.dateTo}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        );

      case _TestePesoStatus.semDados:
        return Text(i18n.tr('dashboard.weight_test_empty'));

      case _TestePesoStatus.precisaInstalar:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_errorMessage ?? i18n.tr('dashboard.health_connect_unavailable')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _service.instalarHealthConnect(),
              child: Text(i18n.tr('dashboard.health_connect_install_button')),
            ),
          ],
        );

      case _TestePesoStatus.erro:
        return Text(
          _errorMessage ?? i18n.tr('dashboard.health_sync_error'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        );
    }
  }
}
