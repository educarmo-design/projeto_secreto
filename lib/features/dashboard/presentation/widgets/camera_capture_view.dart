import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../nutrition/presentation/pages/confirmacao_prato_page.dart';
import '../../data/models/health_payload_model.dart';
import '../controllers/camera_capture_controller.dart';

/// Full-screen live camera capture for a Bluetooth-less device's display —
/// shared by [RegistrarMetricaPage] (device-type picker flow) and
/// [SeniorDashboardPage] (dedicated Balança/Pressão buttons), so the actual
/// capture/upload/zero-storage pipeline exists in exactly one place. Pops
/// with the extracted [HealthPayloadModel] on success, or `null` if the user
/// backs out. Exceptions:
/// - [TipoAparelho.pratoRefeicao] (F10 Passo 3): on success, this screen
///   **stays on the stack** (RELATÓRIO 20260827_0001 — was
///   [Navigator.pushReplacement] before; a real device bug where the
///   replacement route silently never built, no exception anywhere, made
///   `push` the safer choice: any future failure now leaves this screen
///   visible instead of vanishing) and pushes [ConfirmacaoPratoPage] on top.
///   Confirming there pops both screens; declining resets the camera so the
///   user can try again, same pattern as [GravarRefeicaoPage]/
///   [DescreverRefeicaoPage].
/// - [TipoAparelho.rotulo] (F10 Passo 2): still shows its server-transcribed
///   JSON crude/in-place (see [_buildRawResult]) — no typed confirmation
///   screen yet.
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
    _controller.initializeCamera(tipoAparelho: widget.tipoAparelho);
  }

  void _onStateChanged() {
    // RELATÓRIO 20260827_0001 — achado real via log pareado (device +
    // Edge Function, mesma execução, RELATÓRIO 20260825_0007): `mounted`
    // já foi confirmado `true` no instante exato desta chamada (log do
    // device mostrou "chamando pushReplacement (mounted=true)"), então
    // essa checagem aqui é HIGIENE (mesmo padrão dos outros 2 fluxos de
    // IA, `gravar_refeicao_page.dart`) — não é a correção presumida da
    // causa raiz, que continua sem ser 100% confirmada (o log mostrou que
    // `pushReplacement` foi chamado mas a tela de destino nunca chegou a
    // rodar `initState` — nenhuma exceção visível). Ainda assim, mounted
    // pode legitimamente virar `false` ENTRE duas notificações do mesmo
    // listener (ex.: usuário navegou pra trás enquanto media estava
    // processando `rótulo`/glicosímetro), e não tinha proteção nenhuma
    // pra isso antes.
    if (!mounted) return;
    if (_controller.value.isSuccess) {
      final prato = _controller.value.pratoExtraido;
      if (prato != null) {
        debugPrint(
          'DEBUG _onStateChanged: prato extraído com ${prato.itens.length} itens — chamando push (mounted=$mounted)',
        );
        // RELATÓRIO 20260827_0001 — trocado de `pushReplacement` pra
        // `push`: mantém esta tela de câmera na pilha em vez de
        // substituí-la imediatamente. Efeito: se a rota nova falhar em
        // construir por qualquer motivo, esta tela continua visível (em
        // vez de "sumir" deixando a anterior aparecer sozinha) — qualquer
        // problema futuro fica mais visível, não menos. Também dá pra
        // reagir ao retorno (`confirmado`), igual o padrão já usado em
        // texto/áudio (`gravar_refeicao_page.dart`).
        Navigator.of(context)
            .push<bool>(
              MaterialPageRoute<bool>(
                builder: (context) {
                  debugPrint(
                    'DEBUG _onStateChanged: builder de ConfirmacaoPratoPage executando',
                  );
                  return ConfirmacaoPratoPage(extracao: prato);
                },
              ),
            )
            .then((confirmado) {
          if (!mounted) return;
          if (confirmado == true) {
            Navigator.of(context).pop(_controller.value.extractedData);
          } else {
            // Usuário voltou de `ConfirmacaoPratoPage` sem confirmar (back
            // gesture/botão) — mesmo padrão de `GravarRefeicaoPage`: não
            // fecha esta tela sozinho, deixa tentar de novo. Reinicializa a
            // câmera porque o estado atual ainda é `success` (sem isso, o
            // usuário veria o spinner do `case success` do `_buildBody`
            // parado pra sempre, sem jeito nenhum de tirar outra foto).
            _controller.reset();
            _controller.initializeCamera(tipoAparelho: widget.tipoAparelho);
          }
        });
        return;
      }
      // Rótulo nutricional (Adendo v5.1 §B) ainda não tem tela de
      // confirmação bonita — o resultado (já transcrito pelo backend, A.8.3)
      // fica visível NESTA tela, crua, em vez de fechar com pop.
      if (widget.tipoAparelho == TipoAparelho.rotulo) {
        debugPrint(
          'F10 — resultado de rotulo: ${jsonEncode(_controller.value.rawResult)}',
        );
        setState(() {});
        return;
      }
      // Demais tipos (glicosímetro/pressão/balança): comportamento já
      // existente, fecham devolvendo o [HealthPayloadModel] típado.
      Navigator.of(context).pop(_controller.value.extractedData);
      return;
    }
    setState(() {});
  }

  // RELATÓRIO 20260827_0001 — `onPressed: state.isBusy ? null : _capturar`
  // (ver `_buildBody`) descartava o `Future<void>` retornado por
  // `_capturar` (Dart aceita `Future<void> Function()` onde se espera
  // `void Function()`, sem avisar) — qualquer exceção assíncrona que
  // escapasse dela desapareceria sem rastro nenhum, sem passar por nenhum
  // `catch`. `capturarEEnviar` já captura essencialmente tudo internamente
  // (nunca relança), então isto é defesa em profundidade — não a causa
  // raiz confirmada do bug (ver comentário em `_onStateChanged`) — mas
  // fecha um buraco real que existia: `unawaited()` sozinho só silencia o
  // lint, não adiciona tratamento nenhum; o `.catchError` abaixo é o que
  // de fato garante que uma exceção não vira um "Future sem handler"
  // silencioso.
  void _iniciarCaptura() {
    unawaited(
      _capturar().catchError((Object erro, StackTrace stackTrace) {
        debugPrint('CameraCaptureView: exceção não tratada em _capturar: $erro');
        debugPrint(stackTrace.toString());
      }),
    );
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
  /// nunca fez sentido para [TipoAparelho.pratoRefeicao]/[TipoAparelho.rotulo]
  /// — a câmera Nutricional do perfil Atleta reaproveitava o mesmo texto
  /// por engano.
  static String _chaveTituloAppBar(TipoAparelho tipo) {
    switch (tipo) {
      case TipoAparelho.pratoRefeicao:
        return 'dashboard.camera_option_prato_refeicao';
      case TipoAparelho.rotulo:
        return 'dashboard.camera_option_rotulo';
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
          onRetry: () =>
              _controller.initializeCamera(tipoAparelho: widget.tipoAparelho),
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
                  onPressed: state.isBusy ? null : _iniciarCaptura,
                  icon: const Icon(Icons.camera),
                  label: Text(i18n.tr('dashboard.camera_take_photo_button')),
                ),
              ),
            ),
          ],
        );

      case CameraCaptureStatus.success:
        final resultado = state.rawResult;
        if (resultado != null) {
          return _buildRawResult(resultado);
        }
        // Glicosímetro/balança/pressão: `_onStateChanged` já fez
        // `Navigator.pop` antes deste frame renderizar de fato — este
        // spinner só cobre o instante entre os dois. Prato de comida
        // (RELATÓRIO 20260827_0001: `push`, não mais `pop`/`pushReplacement`)
        // também passa por aqui brevemente, mas fica coberto pela tela de
        // confirmação empilhada por cima — nunca fica visível de verdade.
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
    }
  }

  /// F10 Passo 2 (Adendo v5.1 §B — "completa funcionalmente, crua
  /// visualmente"): mostra o JSON JÁ TRANSCRITO pelo backend para
  /// [TipoAparelho.rotulo] (porção/macros/ingredientes lidos do rótulo
  /// impresso, A.8.3) sem nenhum acabamento visual. Prato de comida não
  /// chega mais aqui — tem [ConfirmacaoPratoPage] própria (F10 Passo 3).
  Widget _buildRawResult(Map<String, dynamic> resultado) {
    const encoder = JsonEncoder.withIndent('  ');
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                encoder.convert(resultado),
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _controller.reset();
                      _controller.initializeCamera(tipoAparelho: widget.tipoAparelho);
                    },
                    child: Text(i18n.tr('dashboard.camera_retry_button')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(i18n.tr('dashboard.camera_confirm_button')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
