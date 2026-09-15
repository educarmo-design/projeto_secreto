import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
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
///
/// RELATÓRIO 20260915_0001 (UI de câmera unificada) — quando aberta com
/// [TipoAparelho.pratoRefeicao] OU [TipoAparelho.rotulo] (nunca para os 3
/// tipos de aparelho clínico), esta tela ganha um seletor de modo
/// "Prato"/"Rótulo" (estilo câmera nativa) logo acima do botão de disparo —
/// [widget.tipoAparelho] vira só o modo INICIAL; o modo de verdade em uso
/// (qual "intent" vai no `X-Tipo-Aparelho` e como a resposta é
/// interpretada) é [_tipoAtual], livremente alternável até o instante do
/// disparo. Ver [_modoDuplo]/[_mudarModo].
class CameraCaptureView extends StatefulWidget {
  const CameraCaptureView({super.key, required this.tipoAparelho});

  final TipoAparelho tipoAparelho;

  @override
  State<CameraCaptureView> createState() => _CameraCaptureViewState();
}

class _CameraCaptureViewState extends State<CameraCaptureView> {
  final CameraCaptureController _controller = CameraCaptureController();

  // RELATÓRIO 20260902_0001 (mitigação de latência, Regra 4) — depois de
  // 15s esperando a resposta do servidor (medição real em 20260901_0003:
  // o Gemini variou de ~2s a 43s+ na mesma chamada), troca a mensagem do
  // spinner por um aviso de que ainda está tentando — sem trocar o
  // spinner em si nem reiniciar a animação, só o texto embaixo dele.
  static const Duration _esperaParaAvisoDemora = Duration(seconds: 15);
  Timer? _timerAvisoDemora;
  bool _mostrarAvisoDemora = false;

  // RELATÓRIO 20260915_0001 — modo de captura EM USO (o que de fato vai
  // pro backend/parsing), separado do modo inicial ([widget.tipoAparelho])
  // pra poder ser trocado livremente pelo seletor sem reconstruir o
  // widget inteiro nem reinicializar a câmera (ver doc de
  // [CameraCaptureController.initializeCamera] sobre a resolução única
  // que torna isso possível).
  late TipoAparelho _tipoAtual = widget.tipoAparelho;

  /// Seletor só aparece (e só faz sentido) quando o ponto de entrada foi
  /// "Prato" ou "Rótulo" — os 3 tipos de aparelho clínico (glicosímetro/
  /// pressão/balança) continuam com fluxo de captura único, sem seletor
  /// nenhum poluindo a tela (Regra 4 — "design clean" pedido na tarefa).
  bool get _modoDuplo =>
      widget.tipoAparelho == TipoAparelho.pratoRefeicao ||
      widget.tipoAparelho == TipoAparelho.rotulo;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
    _controller.initializeCamera(tipoAparelho: _tipoAtual);
  }

  /// Chamado a cada notificação do controller — liga o timer só na
  /// transição PRA `uploading` (o `value =` de `capturarEEnviar` acontece
  /// uma única vez ao entrar em upload, então isto nunca reinicia o timer
  /// repetidamente enquanto espera) e desliga assim que sai desse estado
  /// (sucesso, erro, ou uma nova captura começando do zero).
  void _gerenciarTimerAvisoDemora() {
    final emUpload = _controller.value.status == CameraCaptureStatus.uploading;
    if (emUpload) {
      _timerAvisoDemora ??= Timer(_esperaParaAvisoDemora, () {
        if (!mounted) return;
        setState(() => _mostrarAvisoDemora = true);
      });
    } else {
      _timerAvisoDemora?.cancel();
      _timerAvisoDemora = null;
      _mostrarAvisoDemora = false;
    }
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
    _gerenciarTimerAvisoDemora();
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
            _controller.initializeCamera(tipoAparelho: _tipoAtual);
          }
        });
        return;
      }
      // Rótulo nutricional (Adendo v5.1 §B) ainda não tem tela de
      // confirmação bonita — o resultado (já transcrito pelo backend, A.8.3)
      // fica visível NESTA tela, crua, em vez de fechar com pop.
      if (_tipoAtual == TipoAparelho.rotulo) {
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
      // Snapshot de `_tipoAtual` no instante do disparo — o `Future` que
      // `capturarEEnviar` devolve usa este valor até o fim (envia no
      // header E decide como interpretar a resposta), imune a qualquer
      // troca de modo que aconteça DEPOIS (o seletor já fica desabilitado
      // durante `isBusy`, mas isto é a garantia de verdade).
      tipoAparelho: _tipoAtual,
      headers: {
        'apikey': AppConfig.supabaseAnonKey,
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
      },
    );
  }

  /// Troca o modo ativo — chamada só pelo seletor, só quando a câmera não
  /// está ocupada (capturando/enviando; o próprio seletor já fica
  /// desabilitado nesse período, ver [_buildSeletorModo]). Puramente
  /// `setState`: nenhuma chamada ao controller, nenhuma reinicialização de
  /// câmera — é exatamente isso que torna a troca instantânea (RESTRIÇÃO
  /// da tarefa), possível porque as duas resoluções foram unificadas (ver
  /// doc de [CameraCaptureController.initializeCamera]).
  void _mudarModo(TipoAparelho novoTipo) {
    if (novoTipo == _tipoAtual) return;
    setState(() => _tipoAtual = novoTipo);
  }

  @override
  void dispose() {
    _timerAvisoDemora?.cancel();
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
        // RELATÓRIO 20260915_0001 — reage a `_tipoAtual`, não mais ao modo
        // fixo de entrada: o título acompanha o seletor.
        title: Text(i18n.tr(_chaveTituloAppBar(_tipoAtual))),
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

  /// RELATÓRIO 20260902_0001 — texto do overlay de espera: `capturing`
  /// nunca troca (é quase instantâneo, o obturador não passa de 15s);
  /// `uploading` troca pro aviso de demora só depois do timer disparar
  /// (`_mostrarAvisoDemora`), nunca antes.
  String _textoDoOverlay(CameraCaptureState state) {
    if (state.status == CameraCaptureStatus.capturing) {
      return i18n.tr('dashboard.camera_capturing');
    }
    return _mostrarAvisoDemora
        ? i18n.tr('dashboard.camera_uploading_demora')
        : i18n.tr('dashboard.camera_uploading');
  }

  /// RELATÓRIO 20260915_0001 — seletor de modo "Prato"/"Rótulo", estilo
  /// câmera nativa (pill com 2 segmentos, o selecionado destacado). Só
  /// construído quando [_modoDuplo] (verificado pelo chamador) — cor de
  /// destaque reaproveita [AppColors.primaryGold], já usada em outros
  /// pontos do app (ex.: `escolher_metodo_refeicao_page.dart`), pra ficar
  /// visualmente consistente com o resto do produto em vez de importar um
  /// widget Cupertino isolado (o app inteiro é Material).
  Widget _buildSeletorModo(CameraCaptureState state) {
    return Opacity(
      // Mesmo tratamento visual do botão de disparo (`FilledButton` já
      // esmaece sozinho com `onPressed: null`) — este seletor usa
      // `GestureDetector`, que não esmaece sozinho, então replica o mesmo
      // sinal "desabilitado" explicitamente enquanto captura/envia está
      // em andamento (nunca troca de modo no meio de um disparo).
      opacity: state.isBusy ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSegmentoModo(
              tipo: TipoAparelho.pratoRefeicao,
              labelKey: 'dashboard.camera_modo_prato',
              icon: Icons.restaurant,
              busy: state.isBusy,
            ),
            _buildSegmentoModo(
              tipo: TipoAparelho.rotulo,
              labelKey: 'dashboard.camera_modo_rotulo',
              icon: Icons.receipt_long,
              busy: state.isBusy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentoModo({
    required TipoAparelho tipo,
    required String labelKey,
    required IconData icon,
    required bool busy,
  }) {
    final selecionado = _tipoAtual == tipo;
    return GestureDetector(
      onTap: busy ? null : () => _mudarModo(tipo),
      // `AnimatedContainer` — a troca de fundo (destaque dourado) desliza
      // suavemente em vez de "piscar" de um estado pro outro (Regra 4),
      // sem nenhuma reconstrução de câmera por trás (troca só de estado
      // local, ver doc de [_mudarModo]).
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selecionado ? AppColors.primaryGold : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selecionado ? Colors.black : Colors.white),
            const SizedBox(width: 6),
            Text(
              i18n.tr(labelKey),
              style: TextStyle(
                color: selecionado ? Colors.black : Colors.white,
                fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
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
          debugDetail: state.debugDetail,
        );

      case CameraCaptureStatus.error:
        return _buildMessage(
          state.errorMessage ?? i18n.tr('dashboard.camera_error'),
          onRetry: () => _controller.initializeCamera(tipoAparelho: _tipoAtual),
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
                      // `const` — nunca reconstruído quando só o texto
                      // abaixo troca; a animação do spinner não interrompe
                      // nem reinicia (Regra 4).
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      // RELATÓRIO 20260902_0001 — `AnimatedSwitcher` faz a
                      // troca pro aviso de demora (15s) com um crossfade
                      // curto em vez de substituir o texto de uma vez
                      // ("sem piscar", Regra 4). `capturing` nunca aciona
                      // isto (upload é o único estado que arma o timer).
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _textoDoOverlay(state),
                          key: ValueKey(_textoDoOverlay(state)),
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // RELATÓRIO 20260915_0001 — seletor de modo, só quando
                    // esta tela foi aberta como Prato/Rótulo (nunca pros 3
                    // tipos de aparelho clínico). "Logo acima do botão de
                    // disparo", igual pedido na tarefa.
                    if (_modoDuplo) ...[
                      _buildSeletorModo(state),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: state.isBusy ? null : _iniciarCaptura,
                      icon: const Icon(Icons.camera),
                      label: Text(i18n.tr('dashboard.camera_take_photo_button')),
                    ),
                  ],
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
                      _controller.initializeCamera(tipoAparelho: _tipoAtual);
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
