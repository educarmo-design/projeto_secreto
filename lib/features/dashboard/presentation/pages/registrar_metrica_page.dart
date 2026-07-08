import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/health_payload_model.dart';
import '../../data/services/health_sync_service.dart';
import '../controllers/camera_capture_controller.dart';
import '../controllers/sync_ui_controller.dart';

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
      MaterialPageRoute(builder: (_) => _CameraCaptureView(tipoAparelho: tipo)),
    );
    if (extracted != null && mounted) {
      _showExtractedDataDialog(extracted);
    }
  }

  void _showExtractedDataDialog(HealthPayloadModel payload) {
    showDialog<void>(
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

/// Full-screen live camera capture, pushed from [RegistrarMetricaPageState].
/// Pops with the extracted-data JSON on success, or `null` if the user
/// backs out.
class _CameraCaptureView extends StatefulWidget {
  const _CameraCaptureView({required this.tipoAparelho});

  final TipoAparelho tipoAparelho;

  @override
  State<_CameraCaptureView> createState() => _CameraCaptureViewState();
}

class _CameraCaptureViewState extends State<_CameraCaptureView> {
  final CameraCaptureController _controller = CameraCaptureController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
    _controller.initializeCamera();
  }

  void _onStateChanged() {
    if (_controller.value.isSuccess) {
      Navigator.of(context).pop(_controller.value.extractedData);
      return;
    }
    setState(() {});
  }

  Future<void> _capturar() async {
    final session = Supabase.instance.client.auth.currentSession;
    await _controller.capturarEEnviar(
      endpoint: Uri.parse(AppConfig.metricPhotoExtractionEndpoint),
      tipoAparelho: widget.tipoAparelho,
      headers: {
        'apikey': AppConfig.supabaseAnonKey,
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
      },
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.value;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(i18n.tr('dashboard.camera_option')),
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(CameraCaptureState state) {
    switch (state.status) {
      case CameraCaptureStatus.idle:
      case CameraCaptureStatus.initializing:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );

      case CameraCaptureStatus.permissionDenied:
        return _buildMessage(
          state.errorMessage ?? i18n.tr('dashboard.camera_permission_denied'),
        );

      case CameraCaptureStatus.error:
        return _buildMessage(
          state.errorMessage ?? i18n.tr('dashboard.camera_error'),
          onRetry: _controller.initializeCamera,
        );

      case CameraCaptureStatus.ready:
      case CameraCaptureStatus.capturing:
      case CameraCaptureStatus.uploading:
        final preview = _controller.cameraController;
        if (preview == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(preview),
            if (state.isBusy)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        state.status == CameraCaptureStatus.capturing
                            ? i18n.tr('dashboard.camera_capturing')
                            : i18n.tr('dashboard.camera_uploading'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: FilledButton.icon(
                  onPressed: state.isBusy ? null : _capturar,
                  icon: const Icon(Icons.camera),
                  label: Text(i18n.tr('dashboard.camera_take_photo_button')),
                ),
              ),
            ),
          ],
        );

      case CameraCaptureStatus.success:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
    }
  }

  Widget _buildMessage(String message, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: Text(i18n.tr('dashboard.camera_retry_button')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
