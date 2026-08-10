import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/health_payload_model.dart';
import '../../data/repositories/telemetria_historico_repository.dart';
import '../../data/services/health_sync_service.dart';
import '../controllers/sync_ui_controller.dart';

/// N19 — Tela de Histórico de Telemetria + painel de debug.
///
/// Duas razões de existir, ambas do RELATÓRIO 20260809:
///   1. **Prova visual e independente** de que a persistência do N17/N18
///      (upsert idempotente em `metricas_saude_diarias`) realmente
///      funciona — sem precisar abrir o painel do Supabase toda vez.
///   2. **Válvula de escape de teste**: os 2 botões no topo disparam
///      [HealthSyncService.sincronizarDeltaDiario]/[carregarHistoricoInicial]
///      na hora, contornando o comportamento automático (sync ao abrir o
///      app / conectar wearable pela primeira vez) — pedido explícito do
///      fundador para conseguir reproduzir/testar sem depender de quando
///      esses gatilhos automáticos decidem rodar.
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — sem gráfico, sem paginação bonita, só uma lista direta.
/// A única coisa que não é crua de propósito é a fonte do dado: a lista
/// SEMPRE recarrega do Supabase (nunca do resultado em memória do botão de
/// debug) depois de qualquer ação — ver [_recarregarDoBanco] — porque o
/// ponto inteiro desta tela é prova de persistência no banco, não prova de
/// que a leitura do Health Connect funcionou (isso já era visível antes).
class HistoricoTelemetriaPage extends StatefulWidget {
  const HistoricoTelemetriaPage({
    super.key,
    TelemetriaHistoricoRepository? repository,
    SyncUiController? syncUiController,
  })  : _repository = repository,
        _syncUiController = syncUiController;

  final TelemetriaHistoricoRepository? _repository;
  final SyncUiController? _syncUiController;

  @override
  State<HistoricoTelemetriaPage> createState() =>
      _HistoricoTelemetriaPageState();
}

enum _CargaStatus { carregando, sucesso, erro }

class _HistoricoTelemetriaPageState extends State<HistoricoTelemetriaPage> {
  late final TelemetriaHistoricoRepository _repository =
      widget._repository ?? TelemetriaHistoricoRepository();
  late final SyncUiController _syncUiController =
      widget._syncUiController ?? SyncUiController();

  _CargaStatus _status = _CargaStatus.carregando;
  List<HealthPayloadModel> _linhas = const [];

  /// Só um dos dois botões de debug roda por vez — o outro fica desabilitado
  /// enquanto isso, pra não disparar duas leituras concorrentes do mesmo
  /// Health Connect.
  bool _debugRodando = false;

  @override
  void initState() {
    super.initState();
    _recarregarDoBanco();
  }

  @override
  void dispose() {
    _syncUiController.dispose();
    super.dispose();
  }

  /// SEMPRE um SELECT novo no Supabase — nunca reaproveita o retorno de
  /// [DeltaSyncResult.linhas] dos botões de debug. Ver doc de
  /// [TelemetriaHistoricoRepository] para o porquê.
  Future<void> _recarregarDoBanco() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final linhas = await _repository.buscarUltimosDias();
      if (!mounted) return;
      setState(() {
        _linhas = linhas;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  Future<void> _rodarDebug(
    Future<DeltaSyncResult> Function() acao,
  ) async {
    if (_debugRodando) return;
    setState(() => _debugRodando = true);

    final resultado = await acao();

    if (!mounted) return;
    setState(() => _debugRodando = false);

    final mensagem = resultado.isSuccess
        ? i18n.tr(
            'dashboard.historico_telemetria_debug_result',
            params: {'count': resultado.linhas.length.toString()},
          )
        : resultado.isOffline
            ? i18n.tr('dashboard.sync_offline_queued')
            : (resultado.errorMessage ?? i18n.tr('dashboard.health_sync_error'));

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem)));

    // Recarrega do banco mesmo em erro/offline — se alguma linha anterior
    // já tivesse sido gravada (ex.: só uma parte do lote falhou), a lista
    // reflete o estado real do servidor, não o que este botão específico
    // conseguiu ou não fazer agora.
    await _recarregarDoBanco();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.tr('dashboard.historico_telemetria_title')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                i18n.tr('dashboard.historico_telemetria_subtitle'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _PainelDebug(
                rodando: _debugRodando,
                onForcarSyncHoje: () =>
                    _rodarDebug(_syncUiController.forcarSincronizacaoAtleta),
                onForcarCarga30Dias: () => _rodarDebug(
                  _syncUiController.conectarWearablePelaPrimeiraVez,
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

  Widget _buildCorpo(BuildContext context) {
    switch (_status) {
      case _CargaStatus.carregando:
        return const Center(child: CircularProgressIndicator());
      case _CargaStatus.erro:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              i18n.tr('dashboard.historico_telemetria_error'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.error),
            ),
          ),
        );
      case _CargaStatus.sucesso:
        if (_linhas.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                i18n.tr('dashboard.historico_telemetria_empty'),
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
          itemCount: _linhas.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _LinhaTelemetria(payload: _linhas[index]),
        );
    }
  }
}

/// Os 2 botões de debug pedidos pelo fundador — em destaque de propósito
/// (cor de alerta, maiúsculas), pra deixar claro que não são o fluxo normal
/// do app, são uma válvula de escape de teste.
class _PainelDebug extends StatelessWidget {
  const _PainelDebug({
    required this.rodando,
    required this.onForcarSyncHoje,
    required this.onForcarCarga30Dias,
  });

  final bool rodando;
  final VoidCallback onForcarSyncHoje;
  final VoidCallback onForcarCarga30Dias;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: rodando ? null : onForcarSyncHoje,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryOrange,
              side: const BorderSide(color: AppColors.primaryOrange),
            ),
            child: Text(
              rodando
                  ? i18n.tr('dashboard.historico_telemetria_debug_running')
                  : i18n.tr('dashboard.historico_telemetria_debug_force_today'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: rodando ? null : onForcarCarga30Dias,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryRed,
              side: const BorderSide(color: AppColors.primaryRed),
            ),
            child: Text(
              rodando
                  ? i18n.tr('dashboard.historico_telemetria_debug_running')
                  : i18n.tr('dashboard.historico_telemetria_debug_force_30_days'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// Uma linha crua por dia — todos os campos que
/// `metricas_saude_diarias`/[HealthPayloadModel] modelam, om formatação
/// mínima (só a data). Sem ícone bonito por campo, sem gráfico — Regra 14.
class _LinhaTelemetria extends StatelessWidget {
  const _LinhaTelemetria({required this.payload});

  final HealthPayloadModel payload;

  static const List<_CampoLabel> _campos = [
    _CampoLabel('Passos', _CampoTipo.passos),
    _CampoLabel('FC', _CampoTipo.frequenciaCardiaca),
    // FC Máxima/HRV/Água/IMC: RELATÓRIO 20260810_0005 — existiam desde a
    // tarefa anterior (metricas_saude_diarias.fc_maxima/agua_corporal/imc),
    // mas nunca apareciam aqui (BUG desta tarefa).
    _CampoLabel('FC máxima', _CampoTipo.fcMaxima),
    _CampoLabel('FC repouso', _CampoTipo.fcRepouso),
    _CampoLabel('HRV', _CampoTipo.hrvMedio),
    _CampoLabel('Peso (kg)', _CampoTipo.pesoKg),
    _CampoLabel('Água corporal (kg)', _CampoTipo.aguaCorporalKg),
    // "Massa magra" e "Gordura" aqui podem ser leitura direta do Health
    // Connect OU inferência cruzada de HealthSyncService.
    // _aplicarInferenciasCruzadas (RELATÓRIO 20260811130000) — o valor é o
    // mesmo campo/coluna nos dois casos, a tela não distingue a origem.
    _CampoLabel('Massa magra (kg)', _CampoTipo.massaMagraKg),
    _CampoLabel('Gordura (%)', _CampoTipo.percentualGordura),
    _CampoLabel('IMC', _CampoTipo.imc),
    // Sono total primeiro (o que a maioria quer ver de cara), depois o
    // detalhamento por estágio — RELATÓRIO 20260811 (decisão de produto:
    // aproveitar a riqueza de estágios do Garmin).
    _CampoLabel('Sono total (min)', _CampoTipo.minutosSono),
    _CampoLabel('Sono leve (min)', _CampoTipo.sonoLeveMinutos),
    _CampoLabel('Sono profundo (min)', _CampoTipo.sonoProfundoMinutos),
    _CampoLabel('Sono REM (min)', _CampoTipo.sonoRemMinutos),
    _CampoLabel('Acordado (min)', _CampoTipo.sonoAcordadoMinutos),
    _CampoLabel('Distância (m)', _CampoTipo.distanciaMetros),
  ];

  String? _valorFormatado(_CampoTipo tipo) {
    switch (tipo) {
      case _CampoTipo.passos:
        return payload.passos?.toString();
      case _CampoTipo.frequenciaCardiaca:
        return payload.frequenciaCardiaca?.toString();
      case _CampoTipo.fcMaxima:
        return payload.fcMaxima?.toString();
      case _CampoTipo.fcRepouso:
        return payload.fcRepouso?.toString();
      case _CampoTipo.hrvMedio:
        return payload.hrvMedio?.toStringAsFixed(1);
      case _CampoTipo.pesoKg:
        return payload.pesoKg?.toStringAsFixed(1);
      case _CampoTipo.aguaCorporalKg:
        return payload.aguaCorporalKg?.toStringAsFixed(1);
      case _CampoTipo.massaMagraKg:
        return payload.massaMagraKg?.toStringAsFixed(1);
      case _CampoTipo.percentualGordura:
        return payload.percentualGordura?.toStringAsFixed(1);
      case _CampoTipo.imc:
        return payload.imc?.toStringAsFixed(1);
      case _CampoTipo.minutosSono:
        return payload.minutosSono?.toString();
      case _CampoTipo.sonoLeveMinutos:
        return payload.sonoLeveMinutos?.toString();
      case _CampoTipo.sonoProfundoMinutos:
        return payload.sonoProfundoMinutos?.toString();
      case _CampoTipo.sonoRemMinutos:
        return payload.sonoRemMinutos?.toString();
      case _CampoTipo.sonoAcordadoMinutos:
        return payload.sonoAcordadoMinutos?.toString();
      case _CampoTipo.distanciaMetros:
        return payload.distanciaMetros?.toStringAsFixed(0);
    }
  }

  static String _dataFormatada(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final camposPreenchidos = _campos
        .map((c) => MapEntry(c, _valorFormatado(c.tipo)))
        .where((e) => e.value != null)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _dataFormatada(payload.dateFrom),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          if (camposPreenchidos.isEmpty)
            Text(
              '—',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.mutedText),
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final entry in camposPreenchidos)
                  Text(
                    '${entry.key.rotulo}: ${entry.value}',
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _CampoTipo {
  passos,
  frequenciaCardiaca,
  fcMaxima,
  fcRepouso,
  hrvMedio,
  pesoKg,
  aguaCorporalKg,
  massaMagraKg,
  percentualGordura,
  imc,
  minutosSono,
  sonoLeveMinutos,
  sonoProfundoMinutos,
  sonoRemMinutos,
  sonoAcordadoMinutos,
  distanciaMetros,
}

class _CampoLabel {
  const _CampoLabel(this.rotulo, this.tipo);
  final String rotulo;
  final _CampoTipo tipo;
}
