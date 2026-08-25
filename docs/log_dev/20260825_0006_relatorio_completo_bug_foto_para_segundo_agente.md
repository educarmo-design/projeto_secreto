# Relatório completo — bug intermitente no registro de refeição por foto

**Objetivo deste documento:** relatar, de forma autocontida (sem exigir acesso ao
repositório), um bug intermitente e ainda não resolvido, para avaliação por um
segundo agente de IA. Inclui o sintoma exato, tudo que já foi investigado e
descartado com evidência real (não suposição), o código-fonte relevante na
íntegra, e as hipóteses em aberto.

**Contexto do produto:** app de saúde/nutrição em Flutter + Supabase (Postgres +
Auth + Edge Functions em Deno). Um dos recursos é "Registro de Refeição", com 4
métodos de entrada: foto, descrição em texto, áudio, ou escolher um prato
favorito salvo antes. Os 3 primeiros passam por uma Edge Function
(`extract-metric-photo`) que chama a API do Gemini (Google) pra identificar os
alimentos, casa cada um contra um catálogo nutricional no Postgres, e devolve
os itens com macros já calculados deterministicamente pelo servidor (o Gemini
nunca faz o cálculo, só identifica).

---

## 1) Sintoma — como ele se apresenta HOJE, no dispositivo real

Testado num celular Android real, alternando entre Wi-Fi e dados móveis (o
mesmo comportamento ocorre nos dois — rede já foi descartada como causa pelo
usuário).

- **Foto (Método 4):** comportamento inconsistente e não determinístico:
  - Às vezes a tela mostra "Analisando com IA...", depois **a tela
    simplesmente fecha/desaparece sem mostrar mensagem de erro nenhuma**. Isso
    já aconteceu tanto numa primeira tentativa quanto numa tentativa seguinte —
    não é exclusivo de "2ª tentativa".
  - Outras vezes aparece um erro explícito de timeout na tela (`TimeoutException:
    TimeoutException after 0:00:XX.000000: Future not completed`).
  - Em pelo menos uma ocasião funcionou normalmente (resposta rápida, foi pra
    tela de confirmação).
- **Texto (Método 1):** funciona, mas percebido como "lento" pelo usuário
  (alguns segundos).
- **Áudio (Método 2):** já retornou "Servidor ocupado. Tente novamente." (essa
  mensagem aparece TANTO para um timeout do lado do cliente QUANTO para uma
  resposta HTTP ≥500 do servidor — ver seção 4, o código trata os dois casos
  com o mesmo texto).
- **Favoritos (Método 3):** sempre funcionou bem. **Importante:** este método
  não chama o Gemini nem a Edge Function de extração — é uma leitura direta do
  Supabase (Postgres) de um prato já salvo antes.

## 2) O que já foi checado e DESCARTADO com evidência real (não suposição)

1. **Instabilidade do Gemini:** o usuário verificou diretamente no Google AI
   Studio (painel oficial do Google) — sem instabilidade reportada, sem cota
   excedida, no momento dos testes mais recentes.
2. **Rede:** mesmo comportamento em Wi-Fi e em dados móveis (GPRS/4G/5G) —
   descartado pelo usuário através de teste real alternando as duas.
3. **Cota diária do Gemini esgotada:** confirmado tecnicamente numa investigação
   anterior (chamando a API do Gemini direto com a chave real do projeto) que
   existe uma cota separada por modelo — mas o AI Studio (item 1) já mostra que
   não é isso agora.
4. **Rotação/invalidação de chaves do Supabase:** uma investigação encontrou
   que várias secrets do Supabase (`SUPABASE_ANON_KEY`, `SUPABASE_URL`, etc.)
   tinham timestamp de atualização do mesmo dia dos testes — investigado e
   descartado: nenhum comando local rodou `secrets set`, um JWT novo gerado
   nesta investigação autenticou normalmente contra a Edge Function, e o
   Método 3 (Favoritos, que usa Supabase mas não Gemini) sempre funcionou — se
   a chave estivesse quebrada, Favoritos teria falhado também.
5. **Exceção não tratada dentro de `CameraCaptureController.capturarEEnviar`:**
   reli o código nesta própria investigação (código completo na seção 5) — a
   função tem um bloco `catch` genérico no final que transforma QUALQUER
   exceção (incluindo `TypeError`, erro de parsing, etc.) num estado de erro
   visível. Não há caminho óbvio, dentro desta função, pra uma exceção
   desaparecer silenciosamente.
6. **Lista de itens vazia derrubando a tela de confirmação:** `ConfirmacaoPratoPage`
   e `ConfirmacaoPratoController` já tratam explicitamente o caso de 0 itens
   reconhecidos (mostram um "empty state", não tentam acessar `itens.first`
   nem nada parecido) — código na seção 5.

## 3) O que JÁ foi alterado nesta investigação (histórico, mais antigo primeiro)

1. Timeout do cliente (`CameraCaptureController._uploadTimeout`) começou em
   30s, subiu pra 45s, depois pra 60s — porque o servidor não tinha retry
   nenhum contra um 503 transitório do Gemini.
2. Servidor ganhou retry com backoff pra 5xx transitório do Gemini (não pra
   429/cota, que nunca é retentável no mesmo modelo).
3. Servidor ganhou fallback automático de modelo: se o modelo "CORE"
   (`gemini-flash-latest`, mais caro/melhor) falhar (cota OU 5xx esgotado),
   cai automaticamente pro modelo "LITE" (`gemini-flash-lite-latest`, mais
   barato/mais disponível) — e o modelo primário passou a ganhar só 1
   tentativa quando existe fallback configurado (não briga contra si mesmo).
4. **Achado real, medido ao vivo** (chamando a API do Gemini direto, e
   depois a própria Edge Function já em produção, com um usuário de teste
   descartável só pra ter um token válido): o modelo CORE (Flash) tinha
   disponibilidade MUITO instável naquele momento — variou de 200 OK em
   <2s até 503 "high demand" levando **45-59 segundos só pra devolver o
   ERRO**. Numa chamada real à função de produção pedindo foto, levou
   **141,7 segundos** até responder (com sucesso, mas lentíssimo). Numa
   chamada pedindo áudio, levou **150,8 segundos até a própria plataforma
   Supabase matar a função** com o erro `WORKER_RESOURCE_LIMIT` (não é erro
   do Gemini — é o teto de execução da própria infraestrutura serverless
   sendo estourado, porque o Gemini demorou tanto que nem nossa função
   aguentou esperar).
5. **Decisão tomada a partir do achado 4:** trocar o modelo usado na foto de
   Flash (CORE) pra Flash-Lite (LITE) — o mesmo modelo já usado por
   texto/áudio, que nunca falhou em nenhum teste ao vivo feito naquele
   momento (inclusive com uma imagem real de teste). Mudança de
   configuração de uma linha (tabela de roteamento de modelo por tipo de
   captura), sem alterar arquitetura.
6. **Confirmação pós-deploy (ainda no mesmo dia, mais cedo):** 2 chamadas
   reais à função de produção pedindo foto, ambas com sucesso — 72,9s e
   depois 11,7s. Melhora real frente aos 141,7s/150,8s do modelo anterior,
   mas **não instantâneo nem 100% estável** — o Gemini como um todo (não só
   o Flash) mostrou alguma variação naquele dia.
7. **Depois de tudo isso, o usuário testou de novo no celular e o problema
   persiste** (sintomas da seção 1) — inclusive depois de confirmar (item 1
   da seção 2) que o Gemini está saudável agora. Isso motivou esta
   investigação mais profunda, focada no CÓDIGO DO APP em vez de no modelo
   de IA.

## 4) Assimetria estrutural encontrada — o candidato mais forte até agora

Comparando os 3 fluxos que chamam IA (foto / texto / áudio), só o de **foto**
não tem nenhuma checagem de `mounted` antes de navegar. Texto e áudio (que
não relataram o sintoma de "tela fecha sem erro nenhum") têm a checagem em
TODOS os pontos antes de qualquer `Navigator`:

**Áudio (`gravar_refeicao_page.dart`, hoje):**
```dart
if (!mounted) return;         // depois de _recorder.stop()
...
if (!mounted) return;         // depois de ler/apagar o arquivo temporário
...
await _controller.interpretarAudio(...);
if (!mounted) return;         // depois da chamada de rede (10-70+ segundos)
...
final confirmado = await Navigator.of(context).push<bool>(...);
if (!mounted) return;         // depois de voltar da navegação
```

**Foto (`camera_capture_view.dart`, hoje — arquivo completo na seção 5):**
```dart
void _onStateChanged() {
    if (_controller.value.isSuccess) {
      final prato = _controller.value.pratoExtraido;
      if (prato != null) {
        Navigator.of(context).pushReplacement(...);  // SEM checagem de mounted
        return;
      }
      ...
      Navigator.of(context).pop(_controller.value.extractedData); // idem
      return;
    }
    setState(() {});   // idem — sem checagem de mounted
}
```

`_onStateChanged` é um listener (`ValueNotifier.addListener`) chamado sempre
que o estado da chamada de rede muda — inclusive depois de um `await` de
10-70+ segundos (o tempo real medido nas chamadas de foto). Normalmente
`removeListener` no `dispose()` evitaria problema, mas isso pressupõe que o
ciclo de vida do widget seja só "usuário navega pra trás" — não cobre o
Android suspendendo/recriando a Activity por trás (tela bloqueia, app vai pra
segundo plano, gerenciador de memória do sistema age) NO MEIO de uma espera
tão longa. Nesse cenário, o código roda até o fim (por isso nenhum erro
aparece — não há exceção nenhuma pra capturar), só que navega dentro de uma
árvore de widgets que o sistema operacional já descartou por baixo — o
usuário só vê a tela anterior "voltar" sozinha, sem mensagem nenhuma. Isso
bateria exatamente com o sintoma relatado.

**Isto ainda é uma hipótese, não uma causa confirmada** — não há log de
dispositivo (logcat) capturado no momento exato da falha pra provar.

## 5) Código-fonte completo dos arquivos mais relevantes

### `lib/features/dashboard/presentation/controllers/camera_capture_controller.dart`
(orquestra captura → upload → parsing da resposta pra foto)

```dart
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

bool get _podeExibirDetalheTecnico => kDebugMode || AppConfig.debugMode;

enum CameraCaptureStatus {
  idle, initializing, ready, permissionDenied, capturing, uploading, success, error,
}

enum TipoAparelho { glicosimetro, pressaoArterial, balanca, pratoRefeicao, rotulo }

@immutable
class CameraCaptureState {
  final CameraCaptureStatus status;
  final HealthPayloadModel? extractedData;
  final PratoRefeicaoExtracaoModel? pratoExtraido;
  final Map<String, dynamic>? rawResult;
  final String? errorMessage;
  final String? debugDetail;

  const CameraCaptureState({
    this.status = CameraCaptureStatus.idle,
    this.extractedData, this.pratoExtraido, this.rawResult,
    this.errorMessage, this.debugDetail,
  });

  bool get isReady => status == CameraCaptureStatus.ready;
  bool get isBusy => status == CameraCaptureStatus.capturing || status == CameraCaptureStatus.uploading;
  bool get isPermissionDenied => status == CameraCaptureStatus.permissionDenied;
  bool get isSuccess => status == CameraCaptureStatus.success;
  bool get isError => status == CameraCaptureStatus.error;
}

class CameraCaptureController extends ValueNotifier<CameraCaptureState> {
  CameraCaptureController({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        super(const CameraCaptureState());

  final http.Client _httpClient;
  CameraController? _cameraController;
  CameraController? get cameraController => _cameraController;

  static const Duration _uploadTimeout = Duration(seconds: 60);

  Future<void> initializeCamera({required TipoAparelho tipoAparelho}) async {
    value = const CameraCaptureState(status: CameraCaptureStatus.initializing);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        value = CameraCaptureState(status: CameraCaptureStatus.error, errorMessage: i18n.tr('dashboard.camera_unavailable'));
        return;
      }
      final lens = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final preset = tipoAparelho == TipoAparelho.pratoRefeicao ? ResolutionPreset.low : ResolutionPreset.medium;
      final controller = CameraController(lens, preset, enableAudio: false);
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
        status: isDenied ? CameraCaptureStatus.permissionDenied : CameraCaptureStatus.error,
        errorMessage: isDenied ? i18n.tr('dashboard.camera_permission_denied') : i18n.tr('dashboard.camera_error'),
        debugDetail: _podeExibirDetalheTecnico ? '${e.code}: ${e.description}' : null,
      );
    }
  }

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
          .post(endpoint, headers: {...headers, 'Content-Type': 'application/octet-stream', 'X-Tipo-Aparelho': tipoAparelho.name}, body: bytes)
          .timeout(_uploadTimeout);

      if (response.statusCode != 200) {
        final erroBackend = _extrairMensagemErroBackend(response.body);
        value = _estadoDeErro(
          mensagemAmigavel: response.statusCode >= 500 ? i18n.tr('dashboard.camera_upload_error') : (erroBackend ?? i18n.tr('dashboard.camera_client_error')),
          detalheTecnico: 'HTTP ${response.statusCode} em $endpoint — corpo: ${response.body}',
        );
        return;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (tipoAparelho == TipoAparelho.pratoRefeicao) {
        value = CameraCaptureState(status: CameraCaptureStatus.success, pratoExtraido: PratoRefeicaoExtracaoModel.fromJson(decoded));
        return;
      }
      if (tipoAparelho == TipoAparelho.rotulo) {
        value = CameraCaptureState(status: CameraCaptureStatus.success, rawResult: decoded);
        return;
      }

      final payload = HealthPayloadModel.fromAiExtraction(decoded, tipoAparelho: tipoAparelho.name);
      if (payload.isEmpty) {
        value = _estadoDeErro(mensagemAmigavel: i18n.tr('dashboard.camera_no_data_extracted_error'), detalheTecnico: 'HTTP 200 mas HealthPayloadModel.isEmpty — corpo: ${response.body}');
        return;
      }
      value = CameraCaptureState(status: CameraCaptureStatus.success, extractedData: payload);
    } on CameraException catch (e, stackTrace) {
      value = _estadoDeErro(mensagemAmigavel: i18n.tr('dashboard.camera_error'), detalheTecnico: '${e.code}: ${e.description}', excecao: e, stackTrace: stackTrace);
    } on TimeoutException catch (e, stackTrace) {
      value = _estadoDeErro(mensagemAmigavel: i18n.tr('dashboard.camera_upload_error'), detalheTecnico: e.toString(), excecao: e, stackTrace: stackTrace);
    } on http.ClientException catch (e, stackTrace) {
      value = _estadoDeErro(mensagemAmigavel: i18n.tr('dashboard.camera_upload_error'), detalheTecnico: e.toString(), excecao: e, stackTrace: stackTrace);
    } on FormatException catch (e, stackTrace) {
      value = _estadoDeErro(mensagemAmigavel: i18n.tr('dashboard.camera_parse_error'), detalheTecnico: e.toString(), excecao: e, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      value = _estadoDeErro(mensagemAmigavel: i18n.tr('dashboard.camera_unexpected_error'), detalheTecnico: e.toString(), excecao: e, stackTrace: stackTrace);
    } finally {
      if (capturedFile != null) {
        try {
          await File(capturedFile.path).delete();
        } catch (_) {}
      }
    }
  }

  CameraCaptureState _estadoDeErro({required String mensagemAmigavel, required String detalheTecnico, Object? excecao, StackTrace? stackTrace}) {
    final classeExcecao = excecao?.runtimeType.toString();
    debugPrint('CameraCaptureController: ${classeExcecao ?? 'erro'} — $detalheTecnico');
    if (stackTrace != null) debugPrint(stackTrace.toString());
    return CameraCaptureState(status: CameraCaptureStatus.error, errorMessage: mensagemAmigavel, debugDetail: _podeExibirDetalheTecnico ? '${classeExcecao ?? 'HTTP'}: $detalheTecnico' : null);
  }

  String? _extrairMensagemErroBackend(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['message'] is String) return decoded['message'] as String;
        if (decoded['error'] is String) return decoded['error'] as String;
      }
    } catch (_) {}
    return null;
  }

  void reset() => value = const CameraCaptureState();

  @override
  void dispose() {
    _cameraController?.dispose();
    _httpClient.close();
    super.dispose();
  }
}
```

### `lib/features/dashboard/presentation/widgets/camera_capture_view.dart`
(a tela em si — onde a navegação acontece)

```dart
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../nutrition/presentation/pages/confirmacao_prato_page.dart';
import '../../data/models/health_payload_model.dart';
import '../controllers/camera_capture_controller.dart';

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
    if (_controller.value.isSuccess) {
      final prato = _controller.value.pratoExtraido;
      if (prato != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => ConfirmacaoPratoPage(extracao: prato)),
        );
        return;
      }
      if (widget.tipoAparelho == TipoAparelho.rotulo) {
        debugPrint('F10 — resultado de rotulo: ${jsonEncode(_controller.value.rawResult)}');
        setState(() {});
        return;
      }
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
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(i18n.tr(_chaveTituloAppBar(widget.tipoAparelho)))),
      body: _buildBody(state),
    );
  }

  static String _chaveTituloAppBar(TipoAparelho tipo) {
    switch (tipo) {
      case TipoAparelho.pratoRefeicao: return 'dashboard.camera_option_prato_refeicao';
      case TipoAparelho.rotulo: return 'dashboard.camera_option_rotulo';
      case TipoAparelho.glicosimetro:
      case TipoAparelho.pressaoArterial:
      case TipoAparelho.balanca: return 'dashboard.camera_option';
    }
  }

  Widget _buildBody(CameraCaptureState state) {
    switch (state.status) {
      case CameraCaptureStatus.idle:
      case CameraCaptureStatus.initializing:
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      case CameraCaptureStatus.permissionDenied:
        return _buildMessage(state.errorMessage ?? i18n.tr('dashboard.camera_permission_denied'), debugDetail: state.debugDetail);
      case CameraCaptureStatus.error:
        return _buildMessage(state.errorMessage ?? i18n.tr('dashboard.camera_error'),
          onRetry: () => _controller.initializeCamera(tipoAparelho: widget.tipoAparelho), debugDetail: state.debugDetail);
      case CameraCaptureStatus.ready:
      case CameraCaptureStatus.capturing:
      case CameraCaptureStatus.uploading:
        final preview = _controller.cameraController;
        if (preview == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
        return Stack(fit: StackFit.expand, children: [
          CameraPreview(preview),
          if (state.isBusy) Container(color: Colors.black54, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: Colors.white), const SizedBox(height: 16),
            Text(state.status == CameraCaptureStatus.capturing ? i18n.tr('dashboard.camera_capturing') : i18n.tr('dashboard.camera_uploading'), style: const TextStyle(color: Colors.white)),
          ]))),
          Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 32),
            child: FilledButton.icon(onPressed: state.isBusy ? null : _capturar, icon: const Icon(Icons.camera), label: Text(i18n.tr('dashboard.camera_take_photo_button'))))),
        ]);
      case CameraCaptureStatus.success:
        final resultado = state.rawResult;
        if (resultado != null) return _buildRawResult(resultado);
        return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
  }

  Widget _buildRawResult(Map<String, dynamic> resultado) { /* ... irrelevante pro bug (só pra TipoAparelho.rotulo) ... */ return const SizedBox.shrink(); }
  Widget _buildMessage(String message, {VoidCallback? onRetry, String? debugDetail}) { /* ... exibe errorMessage + debugDetail (se debug/homolog) + botão "Tentar Novamente" ... */ return const SizedBox.shrink(); }
}
```

### Ponto de entrada (`main_navigation_page.dart`) — como a tela é aberta

```dart
Future<void> _capturarEExibir(TipoAparelho tipoAparelho) async {
  final extracted = await Navigator.of(context).push<HealthPayloadModel?>(
    MaterialPageRoute(builder: (_) => CameraCaptureView(tipoAparelho: tipoAparelho)),
  );
  if (extracted != null && mounted) {
    await mostrarDialogoConfirmarLeituraAparelho(context, payload: extracted, tipoAparelho: tipoAparelho);
  }
  if (mounted) unawaited(_carregarConsumoMeta());
}
```
`pratoRefeicao` nunca devolve um `HealthPayloadModel` (é sempre `null` — o
fluxo de confirmação dele é a `ConfirmacaoPratoPage`, que a própria
`CameraCaptureView` já abriu via `pushReplacement`, ver acima).

### Para comparação — o fluxo de ÁUDIO, que tem os `mounted` checks e não
apresentou o sintoma de "tela fecha sem erro"

`lib/features/nutrition/presentation/pages/gravar_refeicao_page.dart`:
```dart
Future<void> _pararEEnviar() async {
  _limiteDuracao?.cancel();
  final caminho = await _recorder.stop();
  if (!mounted) return;

  if (caminho == null) {
    setState(() { _estado = _EstadoGravacao.erro; _erroMensagem = i18n.tr('gravar_refeicao.erro_gravacao'); });
    return;
  }
  setState(() => _estado = _EstadoGravacao.enviando);

  List<int> bytes;
  try {
    bytes = await File(caminho).readAsBytes();
  } finally {
    try { await File(caminho).delete(); } catch (_) {}
  }
  if (!mounted) return;

  final headers = (widget._authHeadersProvider ?? _authHeadersPadrao)();
  await _controller.interpretarAudio(bytesAudio: bytes, mimeType: 'audio/mp4', endpoint: Uri.parse(AppConfig.metricPhotoExtractionEndpoint), headers: headers);

  if (!mounted) return;
  final resultado = _controller.value;
  if (resultado.status != RegistroRefeicaoIaStatus.sucesso) {
    setState(() { _estado = _EstadoGravacao.erro; _erroMensagem = resultado.errorMessage; });
    return;
  }

  final confirmado = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ConfirmacaoPratoPage(extracao: resultado.extracao!)));
  if (!mounted) return;
  if (confirmado == true) {
    Navigator.of(context).pop(true);
  } else {
    _controller.reset();
    setState(() => _estado = _EstadoGravacao.idle);
  }
}
```

`lib/features/nutrition/presentation/controllers/registro_refeicao_ia_controller.dart`
(o controller por trás de texto/áudio — mapeia `TimeoutException` pra
"Servidor ocupado. Tente novamente."):
```dart
Future<void> _executar(Future<PratoRefeicaoExtracaoModel> Function() acao) async {
    value = const RegistroRefeicaoIaState(status: RegistroRefeicaoIaStatus.processando);
    try {
      final extracao = await acao();
      value = RegistroRefeicaoIaState(status: RegistroRefeicaoIaStatus.sucesso, extracao: extracao);
    } on RegistroRefeicaoIaException catch (e) {
      value = _erro(mensagemAmigavel: e.mensagemAmigavel, detalheTecnico: e.detalheTecnico);
    } on TimeoutException catch (e) {
      value = _erro(mensagemAmigavel: 'Servidor ocupado. Tente novamente.', detalheTecnico: e.toString());
    } on FormatException catch (e) {
      value = _erro(mensagemAmigavel: 'Não foi possível interpretar a resposta do servidor.', detalheTecnico: e.toString());
    } catch (e) {
      value = _erro(mensagemAmigavel: 'Erro inesperado. Tente novamente.', detalheTecnico: e.toString());
    }
}
```

### Backend — roteamento de modelo e retry/fallback (`extract-metric-photo/index.ts`, trechos relevantes)

```typescript
const MODELO_LITE_PADRAO = 'gemini-flash-lite-latest';
const MODELO_CORE_PADRAO = 'gemini-flash-latest';

const NIVEL_POR_TIPO: Record<string, NivelModelo> = {
  glicosimetro: 'lite',
  balanca: 'lite',
  pressaoArterial: 'lite',
  pratoRefeicao: 'lite',   // ATÉ ONTEM era 'core' — trocado após achar que o
                            // modelo CORE tinha disponibilidade instável
  rotulo: 'core',
  pratoRefeicaoTexto: 'lite',
  pratoRefeicaoAudio: 'lite',
};

const MAX_TENTATIVAS_VISAO = 3;

export function criarChamadorGeminiReal(apiKey: string, modelo: string, opcoes: OpcoesRetryGemini = {}): ChamadorGemini {
  const maxTentativas = opcoes.maxTentativas ?? MAX_TENTATIVAS_VISAO;
  const backoffBaseMs = opcoes.backoffBaseMs ?? 1_500;
  return async ({ base64, mimeType, systemPrompt, userText }) => {
    // ... monta a requisição pro Gemini generateContent ...
    let ultimoErro: ErroHttp | null = null;
    for (let tentativa = 1; tentativa <= maxTentativas; tentativa++) {
      const resposta = await fetch(url, { method: 'POST', headers: {...}, body: JSON.stringify(corpo) });
      if (resposta.ok) { /* retorna o texto */ }
      if (resposta.status === 429) throw new ErroCotaGemini(/* cota — nunca retenta */);
      ultimoErro = new ErroHttp(502, /* ... */);
      const retentavel = resposta.status >= 500;
      if (!retentavel || tentativa === maxTentativas) throw ultimoErro;
      await delay(backoffBaseMs * tentativa); // 1s, 2s (config atual do fallback)
    }
    throw ultimoErro ?? new ErroHttp(502, 'Gemini generateContent falhou sem detalhe.');
  };
}

export function criarChamadorGeminiComFallback(apiKey: string, modeloPrimario: string, modeloFallback: string | null): ChamadorGemini {
  const temFallback = modeloFallback !== null && modeloFallback !== modeloPrimario;
  const chamarPrimario = criarChamadorGeminiReal(apiKey, modeloPrimario, {
    maxTentativas: temFallback ? 1 : MAX_TENTATIVAS_VISAO,
    backoffBaseMs: 1_000,
  });
  return async (params) => {
    try {
      return await chamarPrimario(params);
    } catch (erro) {
      if (!(erro instanceof ErroHttp) || !temFallback) throw erro;
      const chamarFallback = criarChamadorGeminiReal(apiKey, modeloFallback!, { backoffBaseMs: 1_000 });
      return await chamarFallback(params);
    }
  };
}
```

Como `pratoRefeicao` agora está no nível `'lite'`, `temFallback` é `false`
pra ele — ou seja, hoje ele usa `MAX_TENTATIVAS_VISAO` (3) tentativas
completas contra o LITE, sem fallback pra outro modelo (não existe "mais
barato que o mais barato").

## 6) Dados reais medidos (chamadas diretas, não estimativa)

| Chamada | Modelo | Resultado | Tempo |
|---|---|---|---|
| Gemini direto | `gemini-flash-latest` (CORE) | 503 "high demand" | 44,9s |
| Gemini direto | `gemini-flash-latest` (CORE) | 503 "high demand" | 58,9s |
| Gemini direto | `gemini-flash-lite-latest` (LITE) | 200 OK | 571ms |
| Gemini direto | `gemini-flash-lite-latest` (LITE) | 200 OK | 715ms |
| Edge Function produção — texto | LITE | 200 OK | 3,2s |
| Edge Function produção — foto (CORE, antes da troca) | CORE | 200 OK (mas lentíssimo) | 141,7s |
| Edge Function produção — áudio (CORE→fallback ativo na época) | — | **546 `WORKER_RESOURCE_LIMIT`** (Supabase matou a função) | 150,8s |
| Edge Function produção — foto (LITE, depois da troca) | LITE | 200 OK | 72,9s |
| Edge Function produção — foto (LITE, depois da troca) | LITE | 200 OK | 11,7s |

## 7) Perguntas em aberto para o segundo agente

1. Existe algum padrão conhecido de "Future/callback resolvendo contra uma
   árvore de widgets Flutter já descartada pelo sistema operacional" em
   apps Android que fazem uma requisição de rede muito longa (10-70+
   segundos) enquanto a tela pode bloquear/o app pode ir pra segundo
   plano? A hipótese da seção 4 é plausível, mas não comprovada.
2. Existe alguma diferença de comportamento entre `Navigator.pushReplacement`
   (usado só no fluxo de foto) e `Navigator.push` (usado nos fluxos de
   texto/áudio) que tornaria o primeiro mais vulnerável a esse tipo de
   problema?
3. O padrão "funciona uma vez, falha 'do nada' na seguinte, mesmo sem trocar
   de rede" é mais consistente com: (a) o ciclo de vida do Android/Flutter,
   (b) alguma variação residual do próprio Gemini que o AI Studio não
   reflete em tempo real, ou (c) outra causa ainda não cogitada aqui?
4. Dado que o app já expõe o detalhe técnico de erro na tela em builds de
   debug/homolog (`_podeExibirDetalheTecnico`) e MESMO ASSIM a tela às vezes
   fecha sem NENHUM texto — isso é evidência forte de que a exceção nem
   está sendo levantada dentro do código já lido (senão apareceria o
   texto), certo? Ou existe algum caminho que ainda escaparia dos `catch`
   existentes?

## 8) O que ainda não foi feito

Nenhuma captura de log real do dispositivo (`adb logcat`) no momento exato
da falha — é o próximo passo mais indicado, mas depende de acesso físico ao
aparelho.
