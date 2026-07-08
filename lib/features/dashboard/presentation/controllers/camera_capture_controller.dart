import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n_manager.dart';

enum CameraCaptureStatus {
  idle,
  initializing,
  ready,
  permissionDenied,
  capturing,
  uploading,
  success,
  error,
}

/// Physical, Bluetooth-less devices whose display can be photographed and
/// read by the server-side AI extraction step.
enum TipoAparelho { glicosimetro, pressaoArterial, balanca }

@immutable
class CameraCaptureState {
  final CameraCaptureStatus status;
  final Map<String, dynamic>? extractedData;
  final String? errorMessage;

  const CameraCaptureState({
    this.status = CameraCaptureStatus.idle,
    this.extractedData,
    this.errorMessage,
  });

  bool get isReady => status == CameraCaptureStatus.ready;
  bool get isBusy =>
      status == CameraCaptureStatus.capturing ||
      status == CameraCaptureStatus.uploading;
  bool get isPermissionDenied =>
      status == CameraCaptureStatus.permissionDenied;
  bool get isSuccess => status == CameraCaptureStatus.success;
  bool get isError => status == CameraCaptureStatus.error;
}

/// Drives the live-camera capture flow for physical devices without
/// Bluetooth (glucometer / blood-pressure monitor / scale).
///
/// Antifraude: there is deliberately no gallery entry point anywhere in
/// this controller — [initializeCamera] only ever opens the live device
/// camera via the `camera` plugin, never `image_picker` or any path that
/// could accept a pre-existing photo.
///
/// LGPD Zero Storage Pipeline: [capturarEEnviar] holds the captured frame
/// in memory only for the duration of the upload request, and deletes the
/// plugin's temp file the instant the server responds (success or not) —
/// see the `finally` block.
class CameraCaptureController extends ValueNotifier<CameraCaptureState> {
  CameraCaptureController({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        super(const CameraCaptureState());

  final http.Client _httpClient;
  CameraController? _cameraController;

  /// Exposed so the UI can build a `CameraPreview` once the state reaches
  /// [CameraCaptureStatus.ready]. Never null while ready.
  CameraController? get cameraController => _cameraController;

  static const Duration _uploadTimeout = Duration(seconds: 30);

  Future<void> initializeCamera() async {
    value = const CameraCaptureState(status: CameraCaptureStatus.initializing);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        value = CameraCaptureState(
          status: CameraCaptureStatus.error,
          errorMessage: i18n.tr('dashboard.camera_unavailable'),
        );
        return;
      }

      final lens = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        lens,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      _cameraController = controller;
      value = const CameraCaptureState(status: CameraCaptureStatus.ready);
    } on CameraException catch (e) {
      await _cameraController?.dispose();
      _cameraController = null;

      final code = e.code.toLowerCase();
      final isDenied = code.contains('denied') || code.contains('restricted');
      value = CameraCaptureState(
        status: isDenied
            ? CameraCaptureStatus.permissionDenied
            : CameraCaptureStatus.error,
        errorMessage: isDenied
            ? i18n.tr('dashboard.camera_permission_denied')
            : i18n.tr('dashboard.camera_error'),
      );
    }
  }

  /// Captures one frame from the live preview and uploads its raw bytes to
  /// [endpoint] (a server route that runs Gemini 2.5 Flash extraction and
  /// replies with the parsed metric as JSON).
  Future<void> capturarEEnviar({
    required Uri endpoint,
    required TipoAparelho tipoAparelho,
    Map<String, String> headers = const {},
  }) async {
    final controller = _cameraController;
    if (controller == null || !value.isReady) return;

    value = const CameraCaptureState(status: CameraCaptureStatus.capturing);
    XFile? capturedFile;

    try {
      capturedFile = await controller.takePicture();
      final bytes = await capturedFile.readAsBytes();

      value = const CameraCaptureState(status: CameraCaptureStatus.uploading);
      final response = await _httpClient
          .post(
            endpoint,
            headers: {
              ...headers,
              'Content-Type': 'application/octet-stream',
              'X-Tipo-Aparelho': tipoAparelho.name,
            },
            body: bytes,
          )
          .timeout(_uploadTimeout);

      if (response.statusCode != 200) {
        value = CameraCaptureState(
          status: CameraCaptureStatus.error,
          errorMessage: i18n.tr('dashboard.camera_upload_error'),
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      value = CameraCaptureState(
        status: CameraCaptureStatus.success,
        extractedData: decoded,
      );
    } on CameraException {
      value = CameraCaptureState(
        status: CameraCaptureStatus.error,
        errorMessage: i18n.tr('dashboard.camera_error'),
      );
    } on TimeoutException {
      value = CameraCaptureState(
        status: CameraCaptureStatus.error,
        errorMessage: i18n.tr('dashboard.camera_upload_error'),
      );
    } on http.ClientException {
      value = CameraCaptureState(
        status: CameraCaptureStatus.error,
        errorMessage: i18n.tr('dashboard.camera_upload_error'),
      );
    } on FormatException {
      value = CameraCaptureState(
        status: CameraCaptureStatus.error,
        errorMessage: i18n.tr('dashboard.camera_upload_error'),
      );
    } finally {
      // Zero Storage Pipeline: the captured frame is deleted from disk the
      // instant the round trip ends — success or not — so nothing about
      // the photo survives this method call beyond the extracted JSON.
      if (capturedFile != null) {
        try {
          await File(capturedFile.path).delete();
        } catch (_) {
          // Best-effort: the plugin's temp file already lives in a
          // volatile cache dir the OS may reclaim on its own.
        }
      }
    }
  }

  void reset() {
    value = const CameraCaptureState();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _httpClient.close();
    super.dispose();
  }
}
