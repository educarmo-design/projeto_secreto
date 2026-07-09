import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/health_payload_model.dart';
import '../../data/services/health_sync_service.dart';
import '../controllers/camera_capture_controller.dart';
import '../controllers/sync_ui_controller.dart';
import '../widgets/camera_capture_view.dart';
import '../widgets/health_payload_dialog.dart';

/// Mixed metric-registration entry point: either sync automatically from a
/// wearable/health app, or photograph a Bluetooth-less device's display for
/// AI extraction.
class RegistrarMetricaPage extends StatefulWidget {
  const RegistrarMetricaPage({super.key});

  @override
  State<RegistrarMetricaPage> createState() => _RegistrarMetricaPageState();
}

class _RegistrarMetricaPageState extends State<RegistrarMetricaPage> {
  final HealthSyncService _healthService = HealthSyncService();
  final SyncUiController _syncUiController = SyncUiController();

  bool _isSyncingWearable = false;
  HealthSyncResult? _wearableResult;

  @override
  void dispose() {
    _syncUiController.dispose();
    super.dispose();
  }

  Future<void> _handleSyncWearable() async {
    setState(() {
      _isSyncingWearable = true;
      _wearableResult = null;
    });

    final result = await _healthService.carregarHistoricoInicial();

    if (!mounted) return;
    setState(() {
      _isSyncingWearable = false;
      _wearableResult = result;
    });
  }

  Future<void> _handleInstallHealthConnect() async {
    await _healthService.instalarHealthConnect();
  }

  Future<void> _handleTakePhoto() async {
    final tipo = await showModalBottomSheet<TipoAparelho>(
      context: context,
      builder: (_) => const _DeviceTypeSheet(),
    );
    if (tipo == null || !mounted) return;

    final extracted = await Navigator.of(context).push<HealthPayloadModel?>(
      MaterialPageRoute(builder: (_) => CameraCaptureView(tipoAparelho: tipo)),
    );
    if (extracted != null && mounted) {
      await showExtractedDataDialog(context, extracted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('dashboard.registrar_metrica_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _SyncStatusCard(controller: _syncUiController),
            const SizedBox(height: 16),
            _OptionCard(
              icon: Icons.watch_outlined,
              title: i18n.tr('dashboard.sync_wearable_option'),
              description: i18n.tr('dashboard.sync_wearable_description'),
              isLoading: _isSyncingWearable,
              onTap: _isSyncingWearable ? null : _handleSyncWearable,
            ),
            if (_wearableResult != null) ...[
              const SizedBox(height: 8),
              _WearableResultBanner(
                result: _wearableResult!,
                onInstallHealthConnect: _handleInstallHealthConnect,
              ),
            ],
            const SizedBox(height: 16),
            _OptionCard(
              icon: Icons.camera_alt_outlined,
              title: i18n.tr('dashboard.camera_option'),
              description: i18n.tr('dashboard.camera_option_description'),
              onTap: _handleTakePhoto,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sincronização Oportunista entry point: shows the friendly last-sync
/// label and a manual "sync now" button that calls
/// [SyncUiController.forcarSincronizacaoAtleta] directly in foreground —
/// independent of the nightly `sync_diario_wearables` background task.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.controller});

  final SyncUiController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncUiState>(
      valueListenable: controller,
      builder: (context, state, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isLoading
                            ? i18n.tr('dashboard.sync_syncing')
                            : state.ultimaSincronizacaoLabel(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (state.isOffline || state.temPendentes) ...[
                        const SizedBox(height: 4),
                        Text(
                          state.temPendentes
                              ? i18n.tr(
                                  'dashboard.sync_pending_queue',
                                  params: {
                                    'count': state.pendentesNaFila.toString(),
                                  },
                                )
                              : (state.errorMessage ?? ''),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.error),
                        ),
                      ] else if (state.isError) ...[
                        const SizedBox(height: 4),
                        Text(
                          state.errorMessage ??
                              i18n.tr('dashboard.health_sync_error'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.error),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (state.isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: controller.forcarSincronizacaoAtleta,
                    child: Text(i18n.tr('dashboard.sync_force_button')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32, color: AppColors.primaryGold),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _WearableResultBanner extends StatelessWidget {
  const _WearableResultBanner({
    required this.result,
    required this.onInstallHealthConnect,
  });

  final HealthSyncResult result;
  final VoidCallback onInstallHealthConnect;

  @override
  Widget build(BuildContext context) {
    if (result.granted) {
      return Text(
        i18n.tr(
          'dashboard.health_sync_summary',
          params: {'count': result.points.length.toString()},
        ),
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.success),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.errorMessage ?? i18n.tr('dashboard.health_sync_error'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.error),
        ),
        if (result.needsHealthConnectInstall)
          TextButton(
            onPressed: onInstallHealthConnect,
            child: Text(i18n.tr('dashboard.health_connect_install_button')),
          ),
      ],
    );
  }
}

class _DeviceTypeSheet extends StatelessWidget {
  const _DeviceTypeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              i18n.tr('dashboard.device_type_label'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bloodtype_outlined),
            title: Text(i18n.tr('dashboard.device_type_glucose')),
            onTap: () =>
                Navigator.of(context).pop(TipoAparelho.glicosimetro),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(i18n.tr('dashboard.device_type_blood_pressure')),
            onTap: () =>
                Navigator.of(context).pop(TipoAparelho.pressaoArterial),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_weight_outlined),
            title: Text(i18n.tr('dashboard.device_type_scale')),
            onTap: () => Navigator.of(context).pop(TipoAparelho.balanca),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
