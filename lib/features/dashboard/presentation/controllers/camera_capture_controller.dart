import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../nutrition/data/models/prato_refeicao_extracao_model.dart';
import '../../data/models/health_payload_model.dart';

/// Só liga a exposição do erro real na própria tela — nunca a mensagem
/// genérica escondendo qual exceção de fato aconteceu. `kDebugMode` cobre
/// `flutter run`/debug build; `AppConfig.debugMode` cobre o flavor de
/// homolog rodando em release (`--dart-define=DEBUG_MODE=true`). Em
/// produção (nenhum dos dois), o usuário só vê a mensagem amigável — o
/// detalhe técnico ainda assim é sempre registrado via [debugPrint].
bool get _podeExibirDetalheTecnico => kDebugMode || AppConfig.debugMode;

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
/// read by the server-side AI extraction step — plus [pratoRefeicao] and
/// [rotulo], which reuse the exact same zero-storage live-capture pipeline
/// for a photo of a meal (macro estimation) or a packaged product's
/// nutrition facts label (OCR transcription, not estimation) from the
/// customizable dashboard's "Câmera Nutricional" card instead of a device
/// display.
enum TipoAparelho { glicosimetro, pressaoArterial, balanca, pratoRefeicao, rotulo }

@immutable
class CameraCaptureState {
  final CameraCaptureStatus status;

  /// Structured, normalized reading(s) extracted by the server-side AI
  /// from the captured photo — see [HealthPayloadModel]. Whichever of the
  /// tracked biological/clinical parameters (heart rate, blood pressure,
  /// glucose, weight, ...) were visible on the device's display come back
  /// here as typed values, not a loose untyped map. Populated for every
  /// [TipoAparelho] except [TipoAparelho.pratoRefeicao]/[TipoAparelho.rotulo]
  /// — see [rawResult].
  final HealthPayloadModel? extractedData;

  /// F10 Passo 3 — the already-server-calculated response for a
  /// [TipoAparelho.pratoRefeicao] capture (matched food items + deterministic
  /// macros from `alimentos_referencia`, per item), parsed into a typed
  /// model so [ConfirmacaoPratoPage] can render/edit it instead of a raw
  /// JSON dump. Strict parsing ([PratoRefeicaoExtracaoModel.fromJson] throws
  /// [FormatException] on a malformed shape) — a bad response here is a
  /// contract bug, not an uncertain AI reading, so it flows into the same
  /// `on FormatException` handling as any other parse failure (Regra 0.15).
  final PratoRefeicaoExtracaoModel? pratoExtraido;

  /// F10 Passo 2 (Adendo v5.1 A.8.3) — the already-transcribed JSON for a
  /// [TipoAparelho.rotulo] capture (porção/macros/ingredientes lidos direto
  /// do rótulo impresso — OCR, não estimativa). [HealthPayloadModel] is
  /// deliberately NOT reused: its own doc comment states it's a strict "one
  /// property = one fixed column of `metricas_saude_diarias`" model with no
  /// generic bag, and a nutrition label's several fields don't fit that
  /// shape. Per Adendo v5.1 §B ("validação = completa funcionalmente, crua
  /// visualmente"), this raw JSON is shown as-is by [CameraCaptureView] — no
  /// typed confirmation screen yet (unlike [pratoExtraido]).
  final Map<String, dynamic>? rawResult;

  final String? errorMessage;

  /// Classe da exceção real + mensagem técnica (nunca dado da foto/paciente)
  /// — só populado quando [_podeExibirDetalheTecnico] é true. É o que
  /// impede um erro de código de se disfarçar de "servidor ocupado": o
  /// texto amigável em [errorMessage] continua o mesmo para o usuário final,
  /// mas quem está depurando (debug/homolog) vê exatamente o que aconteceu.
  final String? debugDetail;

  const CameraCaptureState({
    this.status = CameraCaptureStatus.idle,
    this.extractedData,
    this.pratoExtraido,
    this.rawResult,
    this.errorMessage,
    this.debugDetail,
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

  // RELATÓRIO 20260824_0001 — achado real em device: fotografar um prato
  // batia `TimeoutException` aos 30s (screenshot em docs/bugs/) porque o
  // servidor não tinha NENHUM retry num 503 transitório do Gemini (mesmo
  // erro "high demand" batido pela curadoria em massa do catálogo,
  // RELATÓRIO 20260823_0004) — o servidor agora retenta até 2x
  // (~4,5s de backoff, ver `MAX_TENTATIVAS_VISAO` em
  // extract-metric-photo/index.ts), então o cliente precisa de folga
  // pra não desistir ANTES do servidor terminar de retentar.
  static const Duration _uploadTimeout = Duration(seconds: 45);

  /// Adendo v5.1 A.4: "a resolução de envio é função do `tipo_captura`".
  /// Comida é barata (~512px, economiza token) porque a IA só precisa
  /// reconhecer FORMA/COR de alimentos; todos os demais tipos — visor de
  /// aparelho (glicosímetro/pressão/balança) E rótulo nutricional — ficam
  /// em [ResolutionPreset.medium] porque OCR (de dígito OU de texto
  /// impresso pequeno) não pode perder nitidez. A escolha acontece na
  /// CAPTURA (o `camera` plugin already grava o frame no tamanho do
  /// preset, nunca em alta resolução seguida de corte — Zero Storage nunca
  /// materializa um frame maior do que o necessário na RAM do device).
  Future<void> initializeCamera({required TipoAparelho tipoAparelho}) async {
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

      final preset = tipoAparelho == TipoAparelho.pratoRefeicao
          ? ResolutionPreset.low
          : ResolutionPreset.medium;
      final controller = CameraController(
        lens,
        preset,
        enableAudio: false,
      );
      await controller.initialize();

      _cameraController = controller;
      value = const CameraCaptureState(status: CameraCaptureStatus.ready);
    } on CameraException catch (e) {
      await _cameraController?.dispose();
      _cameraController = null;

      debugPrint('CameraCaptureController.initializeCamera: ${e.code} — ${e.description}');

      final code = e.code.toLowerCase();
      final isDenied = code.contains('denied') || code.contains('restricted');
      value = CameraCaptureState(
        status: isDenied
            ? CameraCaptureStatus.permissionDenied
            : CameraCaptureStatus.error,
        errorMessage: isDenied
            ? i18n.tr('dashboard.camera_permission_denied')
            : i18n.tr('dashboard.camera_error'),
        debugDetail: _podeExibirDetalheTecnico ? '${e.code}: ${e.description}' : null,
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
        // >=500: falha do lado do servidor/Gemini — "servidor ocupado" é a
        // leitura correta. 4xx é outra categoria (requisição rejeitada por
        // algo que o cliente enviou — imagem grande demais, tipo de
        // aparelho desconhecido, sessão expirada, leitura ilegível do
        // glicosímetro, etc.) e NUNCA deveria aparecer como "servidor
        // ocupado": mostra o texto que o próprio backend já devolve (em
        // "message" ou "error", ver _extrairMensagemErroBackend), que já é
        // específico e seguro de exibir (nunca inclui a foto nem dado do
        // usuário).
        final erroBackend = _extrairMensagemErroBackend(response.body);
        value = _estadoDeErro(
          mensagemAmigavel: response.statusCode >= 500
              ? i18n.tr('dashboard.camera_upload_error')
              : (erroBackend ?? i18n.tr('dashboard.camera_client_error')),
          detalheTecnico:
              'HTTP ${response.statusCode} em $endpoint — corpo: ${response.body}',
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      // Prato de comida (itens + macros determinísticos, A.2) — F10 Passo 3:
      // parseado para o modelo típado que [ConfirmacaoPratoPage] edita.
      // `PratoRefeicaoExtracaoModel.fromJson` lança FormatException numa
      // resposta malformada, capturada pelo `on FormatException` já
      // existente logo abaixo — mesmo caminho de erro de qualquer outro
      // parse ruim, com o detalhe técnico real exposto em debug (Regra 0.15).
      if (tipoAparelho == TipoAparelho.pratoRefeicao) {
        value = CameraCaptureState(
          status: CameraCaptureStatus.success,
          pratoExtraido: PratoRefeicaoExtracaoModel.fromJson(decoded),
        );
        return;
      }

      // Rótulo nutricional (porção/macros/ingredientes já transcritos do
      // rótulo impresso, A.8.3) — não é um HealthPayloadModel (vários campos
      // não cabem no modelo de colunas fixas) nem ainda tem tela de
      // confirmação típada como o prato (Adendo v5.1 §B): [CameraCaptureView]
      // exibe este JSON cru para o fundador conferir os números.
      if (tipoAparelho == TipoAparelho.rotulo) {
        value = CameraCaptureState(
          status: CameraCaptureStatus.success,
          rawResult: decoded,
        );
        return;
      }

      final payload = HealthPayloadModel.fromAiExtraction(
        decoded,
        tipoAparelho: tipoAparelho.name,
      );
      if (payload.isEmpty) {
        // JSON válido, HTTP 200 — a IA respondeu, só que nenhum dos campos
        // que este app sabe ler veio preenchido. Isso NÃO é "servidor
        // ocupado" (o servidor funcionou perfeitamente): a foto do visor não
        // deu pra ler (borrado/apagado). `pratoRefeicao`/`rotulo` nunca
        // chegam aqui — já retornaram acima com seu próprio parsing.
        value = _estadoDeErro(
          mensagemAmigavel: i18n.tr('dashboard.camera_no_data_extracted_error'),
          detalheTecnico:
              'HTTP 200 mas HealthPayloadModel.isEmpty — corpo: ${response.body}',
        );
        return;
      }

      value = CameraCaptureState(
        status: CameraCaptureStatus.success,
        extractedData: payload,
      );
    } on CameraException catch (e, stackTrace) {
      value = _estadoDeErro(
        mensagemAmigavel: i18n.tr('dashboard.camera_error'),
        detalheTecnico: '${e.code}: ${e.description}',
        excecao: e,
        stackTrace: stackTrace,
      );
    } on TimeoutException catch (e, stackTrace) {
      value = _estadoDeErro(
        mensagemAmigavel: i18n.tr('dashboard.camera_upload_error'),
        detalheTecnico: e.toString(),
        excecao: e,
        stackTrace: stackTrace,
      );
    } on http.ClientException catch (e, stackTrace) {
      value = _estadoDeErro(
        mensagemAmigavel: i18n.tr('dashboard.camera_upload_error'),
        detalheTecnico: e.toString(),
        excecao: e,
        stackTrace: stackTrace,
      );
    } on FormatException catch (e, stackTrace) {
      // Corpo da resposta não é o JSON esperado — bug de parsing (nosso ou
      // do servidor), não indisponibilidade de rede.
      value = _estadoDeErro(
        mensagemAmigavel: i18n.tr('dashboard.camera_parse_error'),
        detalheTecnico: e.toString(),
        excecao: e,
        stackTrace: stackTrace,
      );
    } catch (e, stackTrace) {
      // Qualquer exceção não prevista acima (TypeError de um `as` que
      // falhou, erro de render, null-check etc.) — antes desaparecia sem
      // rastro nenhum: `capturarEEnviar` não tinha `catch` genérico, e o
      // Future ficava com erro não tratado. Agora sempre vira um estado de
      // erro visível + log, nunca mais uma tela travada em "Analisando...".
      value = _estadoDeErro(
        mensagemAmigavel: i18n.tr('dashboard.camera_unexpected_error'),
        detalheTecnico: e.toString(),
        excecao: e,
        stackTrace: stackTrace,
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

  /// Ponto único que constrói um `CameraCaptureState` de erro: sempre
  /// registra o detalhe técnico completo no console (`debugPrint`, nunca
  /// omitido) e só ecoa esse mesmo detalhe em [CameraCaptureState.debugDetail]
  /// (visível na tela) quando [_podeExibirDetalheTecnico]. Garante que
  /// nenhum dos 6 pontos de erro em [capturarEEnviar] esqueça de logar —
  /// antes, alguns simplesmente descartavam a exceção capturada.
  CameraCaptureState _estadoDeErro({
    required String mensagemAmigavel,
    required String detalheTecnico,
    Object? excecao,
    StackTrace? stackTrace,
  }) {
    final classeExcecao = excecao?.runtimeType.toString();
    debugPrint(
      'CameraCaptureController: ${classeExcecao ?? 'erro'} — $detalheTecnico',
    );
    if (stackTrace != null) debugPrint(stackTrace.toString());

    return CameraCaptureState(
      status: CameraCaptureStatus.error,
      errorMessage: mensagemAmigavel,
      debugDetail: _podeExibirDetalheTecnico
          ? '${classeExcecao ?? 'HTTP'}: $detalheTecnico'
          : null,
    );
  }

  /// O backend (`extract-metric-photo`) devolve `{"error": "..."}` em toda
  /// resposta 4xx, mas o campo `error` tem DOIS formatos diferentes
  /// dependendo do caso: às vezes já é a frase pronta para o usuário (ex.:
  /// `{"error": "Imagem grande demais."}`), às vezes é um código de máquina
  /// em snake_case acompanhado de um `message` separado com o texto humano
  /// (ex.: `{"error": "leitura_ilegivel", "message": "Não consegui ler o
  /// visor com segurança..."}` — o caso do glicosímetro rejeitando uma
  /// leitura de baixa confiança). Preferir `message` quando presente cobre
  /// os dois formatos sem precisar decidir status a status qual é qual.
  String? _extrairMensagemErroBackend(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['message'] is String) return decoded['message'] as String;
        if (decoded['error'] is String) return decoded['error'] as String;
      }
    } catch (_) {
      // Corpo não é JSON (ex.: erro genérico do gateway) — sem mensagem
      // específica pra extrair, cai no fallback do chamador.
    }
    return null;
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
