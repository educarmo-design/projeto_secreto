import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../nutrition/data/repositories/coleta_diaria_repository.dart';
import '../../../nutrition/presentation/pages/confirmacao_prato_page.dart';
import '../../data/models/health_payload_model.dart';
import '../../data/models/rotulo_extracao_model.dart';
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
/// - [TipoAparelho.rotulo] (F10 Passo 2): RELATÓRIO 20260916_0001 — ganhou
///   um card nutricional tipado e editável (ver [_buildResultadoRotulo]),
///   substituindo o JSON cru mostrado antes. "Confirmar" grava em
///   `coleta_diaria` via [ColetaDiariaRepository.gravarLeituraRotulo] com
///   os valores (possivelmente corrigidos pelo usuário) antes de fechar.
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
  const CameraCaptureView({
    super.key,
    required this.tipoAparelho,
    ColetaDiariaRepository? coletaDiariaRepository,
  }) : _coletaDiariaRepository = coletaDiariaRepository;

  final TipoAparelho tipoAparelho;

  /// Só usado pelo fluxo [TipoAparelho.rotulo] (ver [_confirmarRotulo]) —
  /// injeção de dependência mesmo padrão do resto do app, útil se este
  /// widget algum dia ganhar cobertura de teste (hoje não tem nenhuma: o
  /// `CameraController` do pacote `camera` não é mockável, achado já
  /// registrado nos RELATÓRIOS 20260827_0001/20260902_0001/20260915_0001).
  final ColetaDiariaRepository? _coletaDiariaRepository;

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

  late final ColetaDiariaRepository _coletaDiariaRepository =
      widget._coletaDiariaRepository ?? ColetaDiariaRepository();

  // RELATÓRIO 20260916_0001 — card nutricional editável do resultado de
  // rótulo (substitui o JSON cru). Os 4 controllers são preenchidos UMA vez
  // por captura (guarda em [_camposRotuloPreenchidos], resetado em
  // [_tentarNovamenteRotulo]) — sem isso, cada rebuild (ex.: o usuário
  // digitando) re-populariava os campos com o valor original, apagando a
  // edição em andamento.
  final _caloriasController = TextEditingController();
  final _proteinasController = TextEditingController();
  final _carboidratosController = TextEditingController();
  final _gordurasController = TextEditingController();
  RotuloExtracaoModel? _rotuloExtraido;
  bool _camposRotuloPreenchidos = false;
  bool _salvandoRotulo = false;

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
      // Rótulo nutricional (Adendo v5.1 §B) — RELATÓRIO 20260916_0001: o
      // resultado (já transcrito pelo backend, A.8.3) agora popula o card
      // nutricional editável ([_buildResultadoRotulo]) em vez de ficar cru.
      if (_tipoAtual == TipoAparelho.rotulo) {
        final decoded = _controller.value.rawResult;
        debugPrint('F10 — resultado de rotulo: ${jsonEncode(decoded)}');
        if (decoded != null && !_camposRotuloPreenchidos) {
          _rotuloExtraido = RotuloExtracaoModel.fromJson(decoded);
          _preencherCamposRotulo(_rotuloExtraido!);
          _camposRotuloPreenchidos = true;
        }
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
    _caloriasController.dispose();
    _proteinasController.dispose();
    _carboidratosController.dispose();
    _gordurasController.dispose();
    super.dispose();
  }

  void _preencherCamposRotulo(RotuloExtracaoModel extracao) {
    _caloriasController.text = extracao.caloriasKcal == null
        ? ''
        : _formatarNumero(extracao.caloriasKcal!, casasDecimais: 0);
    _proteinasController.text =
        extracao.proteinasG == null ? '' : _formatarNumero(extracao.proteinasG!);
    _carboidratosController.text =
        extracao.carboidratosG == null ? '' : _formatarNumero(extracao.carboidratosG!);
    _gordurasController.text =
        extracao.gordurasG == null ? '' : _formatarNumero(extracao.gordurasG!);
  }

  static String _formatarNumero(double valor, {int casasDecimais = 1}) {
    return valor == valor.truncateToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(casasDecimais);
  }

  void _tentarNovamenteRotulo() {
    _camposRotuloPreenchidos = false;
    _rotuloExtraido = null;
    _controller.reset();
    _controller.initializeCamera(tipoAparelho: _tipoAtual);
  }

  /// Grava a leitura em `coleta_diaria` com os valores ATUAIS dos campos —
  /// ou seja, com qualquer correção que o usuário tenha feito no card antes
  /// de tocar "Confirmar" (item 1b da tarefa: "permitindo que o usuário
  /// valide os dados antes de gravar no banco"). Fecha a tela só em caso de
  /// sucesso — uma falha de rede deixa o usuário tentar "Confirmar" de novo
  /// sem perder o que já digitou.
  Future<void> _confirmarRotulo() async {
    setState(() => _salvandoRotulo = true);

    double? paraDouble(TextEditingController controller) {
      final texto = controller.text.trim();
      if (texto.isEmpty) return null;
      return double.tryParse(texto.replaceAll(',', '.'));
    }

    final payload = RotuloExtracaoModel(
      porcaoDescricao: _rotuloExtraido?.porcaoDescricao,
      caloriasKcal: paraDouble(_caloriasController),
      proteinasG: paraDouble(_proteinasController),
      carboidratosG: paraDouble(_carboidratosController),
      gordurasG: paraDouble(_gordurasController),
      ingredientesPrincipais: _rotuloExtraido?.ingredientesPrincipais ?? const [],
    ).toJson();

    final resultado = await _coletaDiariaRepository.gravarLeituraRotulo(payload: payload);

    if (!mounted) return;
    setState(() => _salvandoRotulo = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            resultado.success
                ? i18n.tr('dashboard.camera_save_success')
                : (resultado.errorMessage ?? i18n.tr('dashboard.camera_save_error')),
          ),
          backgroundColor: resultado.success ? AppColors.success : AppColors.error,
        ),
      );

    if (resultado.success) {
      Navigator.of(context).pop();
    }
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
                // RELATÓRIO 20260916_0001 — subiu de 32 pra 42 (+10px, ~2mm
                // na maioria das densidades de tela), pedido explícito do
                // fundador: os botões ficavam colados demais na borda
                // inferior/gesture bar de alguns aparelhos.
                padding: const EdgeInsets.only(bottom: 42),
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
        if (state.rawResult != null) {
          return _buildResultadoRotulo(context, _rotuloExtraido);
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

  /// F10 Passo 2 (item 1b, RELATÓRIO 20260916_0001) — card nutricional
  /// amigável para [TipoAparelho.rotulo] (porção/macros/ingredientes lidos
  /// do rótulo impresso, A.8.3), substituindo o JSON cru exibido antes. Os
  /// 4 macros são `TextFormField`s EDITÁVEIS: o usuário pode corrigir um
  /// número que a IA leu errado antes de confirmar — "validar os dados
  /// antes de gravar no banco" (Restrição da tarefa). Prato de comida não
  /// chega mais aqui — tem [ConfirmacaoPratoPage] própria (F10 Passo 3).
  Widget _buildResultadoRotulo(BuildContext context, RotuloExtracaoModel? extracao) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (extracao?.porcaoDescricao != null) ...[
                    Text(
                      i18n.tr('dashboard.camera_rotulo_porcao_label'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      extracao!.porcaoDescricao!,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (extracao?.possivelFotoDeTela ?? false) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Text(
                        i18n.tr('dashboard.camera_rotulo_possivel_foto_tela'),
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i18n.tr('dashboard.camera_rotulo_card_title'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _buildCampoMacro(
                            controller: _caloriasController,
                            labelKey: 'dashboard.camera_rotulo_calorias_label',
                            suffix: 'kcal',
                          ),
                          const SizedBox(height: 12),
                          _buildCampoMacro(
                            controller: _proteinasController,
                            labelKey: 'dashboard.camera_rotulo_proteinas_label',
                            suffix: 'g',
                          ),
                          const SizedBox(height: 12),
                          _buildCampoMacro(
                            controller: _carboidratosController,
                            labelKey: 'dashboard.camera_rotulo_carboidratos_label',
                            suffix: 'g',
                          ),
                          const SizedBox(height: 12),
                          _buildCampoMacro(
                            controller: _gordurasController,
                            labelKey: 'dashboard.camera_rotulo_gorduras_label',
                            suffix: 'g',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (extracao?.ingredientesPrincipais.isNotEmpty ?? false) ...[
                    const SizedBox(height: 16),
                    Text(
                      i18n.tr('dashboard.camera_rotulo_ingredientes_label'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ingrediente in extracao!.ingredientesPrincipais)
                          Chip(
                            label: Text(ingrediente),
                            backgroundColor: Colors.white24,
                            labelStyle: const TextStyle(color: Colors.white),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _salvandoRotulo ? null : _tentarNovamenteRotulo,
                    child: Text(i18n.tr('dashboard.camera_retry_button')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _salvandoRotulo ? null : _confirmarRotulo,
                    child: _salvandoRotulo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(i18n.tr('dashboard.camera_confirm_button')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampoMacro({
    required TextEditingController controller,
    required String labelKey,
    required String suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: i18n.tr(labelKey),
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      enabled: !_salvandoRotulo,
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
