import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/health_payload_model.dart';
import '../controllers/camera_capture_controller.dart';

/// Full-screen live camera capture for a Bluetooth-less device's display —
/// shared by [RegistrarMetricaPage] (device-type picker flow) and
/// [SeniorDashboardPage] (dedicated Balança/Pressão buttons), so the actual
/// capture/upload/zero-storage pipeline exists in exactly one place. Pops
/// with the extracted [HealthPayloadModel] on success, or `null` if the user
/// backs out.
class CameraCaptureView extends StatefulWidget {
  const CameraCaptureView({super.key, required this.tipoAparelho});

  final TipoAparelho tipoAparelho;

  @override
  State<CameraCaptureView> createState() => _CameraCaptureViewState();
}

class _CameraCaptureViewState extends State<CameraCaptureView> {
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
        title: Text(i18n.tr(_chaveTituloAppBar(widget.tipoAparelho))),
      ),
      body: _buildBody(state),
    );
  }

  /// Título da tela varia por [TipoAparelho]: "Tirar Foto do Visor do
  /// Aparelho" descreve corretamente o glicosímetro/pressão/balança, mas
  /// nunca fez sentido para [TipoAparelho.pratoRefeicao] — a câmera
  /// Nutricional do perfil Atleta reaproveitava o mesmo texto por engano.
  static String _chaveTituloAppBar(TipoAparelho tipo) {
    switch (tipo) {
      case TipoAparelho.pratoRefeicao:
        return 'dashboard.camera_option_prato_refeicao';
      case TipoAparelho.glicosimetro:
      case TipoAparelho.pressaoArterial:
      case TipoAparelho.balanca:
        return 'dashboard.camera_option';
    }
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
          debugDetail: state.debugDetail,
        );

      case CameraCaptureStatus.error:
        return _buildMessage(
          state.errorMessage ?? i18n.tr('dashboard.camera_error'),
          onRetry: _controller.initializeCamera,
          debugDetail: state.debugDetail,
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

  Widget _buildMessage(String message, {VoidCallback? onRetry, String? debugDetail}) {
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
            // Só aparece em build de debug/homolog (ver _podeExibirDetalheTecnico
            // no controller) — nunca em produção. É o erro real por trás da
            // mensagem amigável acima, para quem está depurando.
            if (debugDetail != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  debugDetail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
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
