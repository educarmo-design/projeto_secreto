import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../controllers/registro_refeicao_ia_controller.dart';
import 'confirmacao_prato_page.dart';

enum _EstadoGravacao { idle, semPermissao, gravando, enviando, erro }

/// RELATÓRIO 20260824_0003 — Registro de Refeição, Método 2 (áudio). Zero
/// Storage: o `record` só sabe gravar pra um arquivo (não existe modo
/// "só memória" na API do plugin), então o áudio TEM que tocar disco
/// brevemente — mas o `finally` de [_pararEEnviar] apaga esse arquivo
/// IMEDIATAMENTE depois de ler os bytes pra RAM, antes mesmo da resposta
/// do servidor chegar — mesmo princípio/mesma garantia do `XFile` da
/// câmera em `CameraCaptureController.capturarEEnviar`. O áudio em si
/// nunca é enviado a nenhum outro lugar além do Gemini (que também não o
/// armazena, F10 Passo 1) nem persiste em nenhuma tabela.
class GravarRefeicaoPage extends StatefulWidget {
  const GravarRefeicaoPage({
    super.key,
    this.controller,
    AudioRecorder? recorder,
    Map<String, String> Function()? authHeadersProvider,
  })  : _recorder = recorder,
        _authHeadersProvider = authHeadersProvider;

  /// Injetável em teste — mesmo padrão de `ConfirmacaoPratoPage`.
  final RegistroRefeicaoIaController? controller;
  final AudioRecorder? _recorder;

  /// Injetável em teste — mesmo padrão de `FoodSearchController`/
  /// `DescreverRefeicaoPage` (`authHeadersProvider`): sem isto,
  /// `Supabase.instance` (só chamado no padrão real,
  /// `_authHeadersPadrao`) lança `AssertionError` em qualquer ambiente
  /// onde o SDK não foi inicializado (todo widget test).
  final Map<String, String> Function()? _authHeadersProvider;

  @override
  State<GravarRefeicaoPage> createState() => _GravarRefeicaoPageState();
}

class _GravarRefeicaoPageState extends State<GravarRefeicaoPage> {
  late final RegistroRefeicaoIaController _controller =
      widget.controller ?? RegistroRefeicaoIaController();
  late final bool _controllerEhProprio = widget.controller == null;
  late final AudioRecorder _recorder = widget._recorder ?? AudioRecorder();
  late final bool _recorderEhProprio = widget._recorder == null;

  _EstadoGravacao _estado = _EstadoGravacao.idle;
  String? _erroMensagem;
  Timer? _limiteDuracao;

  // Teto de segurança — evita um clipe absurdamente longo (custo de
  // tokens/cota do Gemini, ver RELATÓRIO 20260824_0002) e mantém a UI
  // simples ("completo funcionalmente, cru visualmente"): sem contador
  // regressivo, só um corte automático.
  static const Duration _duracaoMaxima = Duration(seconds: 90);

  // RELATÓRIO 20260902_0001 (mitigação de latência, Regra 4) — mesmo
  // padrão de `CameraCaptureView`/`DescreverRefeicaoPage`: depois de 15s
  // esperando o servidor (estado `enviando`), troca o texto por um aviso
  // de demora, sem interromper o spinner.
  static const Duration _esperaParaAvisoDemora = Duration(seconds: 15);
  Timer? _timerAvisoDemora;
  bool _mostrarAvisoDemora = false;

  /// Liga o timer ao ENTRAR em `enviando`. Chamar só uma vez por envio.
  void _iniciarAvisoDemora() {
    _mostrarAvisoDemora = false;
    _timerAvisoDemora = Timer(_esperaParaAvisoDemora, () {
      if (!mounted) return;
      setState(() => _mostrarAvisoDemora = true);
    });
  }

  /// Desliga o timer ao SAIR de `enviando` (sucesso, erro, ou reset pro
  /// idle) — nunca deixa o aviso vazar pra um próximo envio.
  void _pararAvisoDemora() {
    _timerAvisoDemora?.cancel();
    _timerAvisoDemora = null;
    _mostrarAvisoDemora = false;
  }

  @override
  void dispose() {
    _limiteDuracao?.cancel();
    _timerAvisoDemora?.cancel();
    if (_controllerEhProprio) _controller.dispose();
    if (_recorderEhProprio) _recorder.dispose();
    super.dispose();
  }

  static Map<String, String> _authHeadersPadrao() {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Future<void> _iniciarGravacao() async {
    final temPermissao = await _recorder.hasPermission();
    if (!mounted) return;
    if (!temPermissao) {
      setState(() => _estado = _EstadoGravacao.semPermissao);
      return;
    }

    final diretorio = await getTemporaryDirectory();
    final caminho = '${diretorio.path}/registro_refeicao_${DateTime.now().microsecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: caminho);
    if (!mounted) return;
    setState(() => _estado = _EstadoGravacao.gravando);

    _limiteDuracao = Timer(_duracaoMaxima, () {
      if (mounted && _estado == _EstadoGravacao.gravando) _pararEEnviar();
    });
  }

  Future<void> _cancelarGravacao() async {
    _limiteDuracao?.cancel();
    await _recorder.cancel();
    if (!mounted) return;
    setState(() => _estado = _EstadoGravacao.idle);
  }

  Future<void> _pararEEnviar() async {
    _limiteDuracao?.cancel();
    final caminho = await _recorder.stop();
    if (!mounted) return;

    if (caminho == null) {
      setState(() {
        _estado = _EstadoGravacao.erro;
        _erroMensagem = i18n.tr('gravar_refeicao.erro_gravacao');
      });
      return;
    }

    setState(() => _estado = _EstadoGravacao.enviando);
    _iniciarAvisoDemora();

    List<int> bytes;
    try {
      bytes = await File(caminho).readAsBytes();
    } finally {
      // Zero Storage — apaga o arquivo temporário assim que os bytes estão
      // em memória, ANTES de esperar a resposta do servidor. Mesmo
      // best-effort de `CameraCaptureController.capturarEEnviar`/`XFile`:
      // o diretório temporário do SO já é volátil por si só.
      try {
        await File(caminho).delete();
      } catch (_) {
        // Best-effort.
      }
    }

    if (!mounted) return;

    final headers = (widget._authHeadersProvider ?? _authHeadersPadrao)();
    await _controller.interpretarAudio(
      bytesAudio: bytes,
      mimeType: 'audio/mp4',
      endpoint: Uri.parse(AppConfig.metricPhotoExtractionEndpoint),
      headers: headers,
    );

    if (!mounted) return;
    final resultado = _controller.value;
    if (resultado.status != RegistroRefeicaoIaStatus.sucesso) {
      _pararAvisoDemora();
      setState(() {
        _estado = _EstadoGravacao.erro;
        _erroMensagem = resultado.errorMessage;
      });
      return;
    }
    _pararAvisoDemora();

    final confirmado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ConfirmacaoPratoPage(extracao: resultado.extracao!)),
    );
    if (!mounted) return;
    if (confirmado == true) {
      Navigator.of(context).pop(true);
    } else {
      _controller.reset();
      setState(() => _estado = _EstadoGravacao.idle);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('gravar_refeicao.title'))),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  i18n.tr('gravar_refeicao.instrucao'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                _buildConteudo(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConteudo(BuildContext context) {
    switch (_estado) {
      case _EstadoGravacao.semPermissao:
        return Text(
          i18n.tr('gravar_refeicao.sem_permissao'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      case _EstadoGravacao.enviando:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `const` — nunca reconstruído quando só o texto abaixo troca
            // (Regra 4).
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            // RELATÓRIO 20260902_0001 — crossfade curto pro aviso de
            // demora (15s), nunca troca de uma vez ("sem piscar").
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _mostrarAvisoDemora
                    ? i18n.tr('gravar_refeicao.interpretando_demora')
                    : i18n.tr('gravar_refeicao.interpretando'),
                key: ValueKey(_mostrarAvisoDemora),
              ),
            ),
          ],
        );
      case _EstadoGravacao.erro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _erroMensagem ?? i18n.tr('gravar_refeicao.erro_gravacao'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _estado = _EstadoGravacao.idle),
              child: Text(i18n.tr('gravar_refeicao.tentar_novamente')),
            ),
          ],
        );
      case _EstadoGravacao.gravando:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(i18n.tr('gravar_refeicao.gravando')),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _cancelarGravacao,
                  child: Text(i18n.tr('common.cancel')),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _pararEEnviar,
                  child: Text(i18n.tr('gravar_refeicao.parar_button')),
                ),
              ],
            ),
          ],
        );
      case _EstadoGravacao.idle:
        return IconButton(
          iconSize: 72,
          icon: const Icon(Icons.mic_none),
          tooltip: i18n.tr('gravar_refeicao.gravar_button'),
          onPressed: _iniciarGravacao,
        );
    }
  }
}
