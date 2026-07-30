import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/services/health_sync_service.dart';

enum _TesteSonoStatus { idle, carregando, sucesso, semDados, erro, precisaInstalar }

/// Tela crua de validação do pipeline Health Connect -> Sono (Adendo v5.1
/// §B: "validação = completa funcionalmente, crua visualmente" — sem
/// gráfico, sem histórico bonito, só a lista bruta). Aberta via
/// [Navigator.push] a partir de Configurações, não uma rota do GoRouter —
/// mesmo padrão de [TesteFrequenciaCardiacaPage]/[TestePesoPage].
///
/// Existe para responder uma dúvida específica: um backfill de histórico
/// falhou para uma balança de terceiros — esta tela isola se o problema é o
/// pipeline de leitura deste app ou o app da balança, lendo sessões de sono
/// de um Garmin já sincronizado (histórico contínuo e confiável) como
/// referência conhecida-boa. Por isso mostra a LISTA inteira de noites
/// encontradas na janela, não só a mais recente (diferente de
/// [TesteFrequenciaCardiacaPage]/[TestePesoPage], que mostram um valor só).
class TesteSonoPage extends StatefulWidget {
  const TesteSonoPage({super.key, HealthSyncService? service}) : _service = service;

  final HealthSyncService? _service;

  @override
  State<TesteSonoPage> createState() => _TesteSonoPageState();
}

class _TesteSonoPageState extends State<TesteSonoPage> {
  late final HealthSyncService _service = widget._service ?? HealthSyncService();

  _TesteSonoStatus _status = _TesteSonoStatus.idle;
  List<HealthMetricPoint> _sessoes = const [];
  String? _errorMessage;

  Future<void> _ler() async {
    setState(() => _status = _TesteSonoStatus.carregando);

    final resultado = await _service.lerSonoRecente();

    if (!mounted) return;

    if (resultado.needsHealthConnectInstall) {
      setState(() {
        _status = _TesteSonoStatus.precisaInstalar;
        _errorMessage = resultado.errorMessage;
      });
      return;
    }

    if (!resultado.granted) {
      setState(() {
        _status = _TesteSonoStatus.erro;
        _errorMessage =
            resultado.errorMessage ?? i18n.tr('dashboard.health_sync_error');
      });
      return;
    }

    if (resultado.points.isEmpty) {
      setState(() => _status = _TesteSonoStatus.semDados);
      return;
    }

    final ordenadas = [...resultado.points]
      ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));

    setState(() {
      _status = _TesteSonoStatus.sucesso;
      _sessoes = ordenadas;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('dashboard.sleep_test_title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                i18n.tr('dashboard.sleep_test_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _status == _TesteSonoStatus.carregando ? null : _ler,
                child: _status == _TesteSonoStatus.carregando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(i18n.tr('dashboard.sleep_test_button')),
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildResultado(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultado(BuildContext context) {
    switch (_status) {
      case _TesteSonoStatus.idle:
      case _TesteSonoStatus.carregando:
        return const SizedBox.shrink();

      case _TesteSonoStatus.sucesso:
        return ListView.separated(
          itemCount: _sessoes.length,
          separatorBuilder: (_, __) => const Divider(height: 24),
          itemBuilder: (context, index) {
            final sessao = _sessoes[index];
            final duracao = sessao.dateTo.difference(sessao.dateFrom);
            final horas = duracao.inHours;
            final minutos = duracao.inMinutes.remainder(60);
            return SelectableText(
              'início: ${sessao.dateFrom}\n'
              'fim: ${sessao.dateTo}\n'
              'duração: ${horas}h${minutos.toString().padLeft(2, '0')}\n'
              'fonte: ${sessao.sourceApp.isEmpty ? "desconhecida" : sessao.sourceApp}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            );
          },
        );

      case _TesteSonoStatus.semDados:
        return Text(i18n.tr('dashboard.sleep_test_empty'));

      case _TesteSonoStatus.precisaInstalar:
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

      case _TesteSonoStatus.erro:
        return Text(
          _errorMessage ?? i18n.tr('dashboard.health_sync_error'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
        );
    }
  }
}
