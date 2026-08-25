import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/config/app_config.dart';
import '../../data/models/prato_refeicao_extracao_model.dart';
import '../../data/services/registro_refeicao_ia_service.dart';

/// Só liga a exposição do erro real na própria tela — mesmo helper/mesma
/// justificativa de `CameraCaptureController._podeExibirDetalheTecnico`,
/// duplicado aqui de propósito (função pura de uma linha).
bool get _podeExibirDetalheTecnico => kDebugMode || AppConfig.debugMode;

enum RegistroRefeicaoIaStatus { idle, processando, sucesso, erro }

@immutable
class RegistroRefeicaoIaState {
  const RegistroRefeicaoIaState({
    this.status = RegistroRefeicaoIaStatus.idle,
    this.extracao,
    this.errorMessage,
    this.debugDetail,
  });

  final RegistroRefeicaoIaStatus status;
  final PratoRefeicaoExtracaoModel? extracao;
  final String? errorMessage;
  final String? debugDetail;

  bool get isProcessando => status == RegistroRefeicaoIaStatus.processando;
  bool get isErro => status == RegistroRefeicaoIaStatus.erro;
}

/// RELATÓRIO 20260824_0003 — orquestra os Métodos 1 (texto) e 2 (áudio) do
/// Registro de Refeição. Mesmo formato de saída
/// ([PratoRefeicaoExtracaoModel]) que o Método 4 (foto,
/// `CameraCaptureController`) já produz — as telas dos 2 novos métodos
/// abrem a MESMA `ConfirmacaoPratoPage` no final, sem nenhum código a
/// mais lá.
class RegistroRefeicaoIaController extends ValueNotifier<RegistroRefeicaoIaState> {
  RegistroRefeicaoIaController({RegistroRefeicaoIaService? service})
      : _service = service ?? RegistroRefeicaoIaService(),
        super(const RegistroRefeicaoIaState());

  final RegistroRefeicaoIaService _service;

  Future<void> interpretarTexto({
    required String descricao,
    required Uri endpoint,
    Map<String, String> headers = const {},
  }) => _executar(
        () => _service.interpretarTexto(descricao: descricao, endpoint: endpoint, headers: headers),
      );

  Future<void> interpretarAudio({
    required List<int> bytesAudio,
    required String mimeType,
    required Uri endpoint,
    Map<String, String> headers = const {},
  }) => _executar(
        () => _service.interpretarAudio(
          bytesAudio: bytesAudio,
          mimeType: mimeType,
          endpoint: endpoint,
          headers: headers,
        ),
      );

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
      value = _erro(
        mensagemAmigavel: 'Não foi possível interpretar a resposta do servidor.',
        detalheTecnico: e.toString(),
      );
    } catch (e) {
      value = _erro(mensagemAmigavel: 'Erro inesperado. Tente novamente.', detalheTecnico: e.toString());
    }
  }

  RegistroRefeicaoIaState _erro({required String mensagemAmigavel, required String detalheTecnico}) {
    debugPrint('RegistroRefeicaoIaController: $detalheTecnico');
    return RegistroRefeicaoIaState(
      status: RegistroRefeicaoIaStatus.erro,
      errorMessage: mensagemAmigavel,
      debugDetail: _podeExibirDetalheTecnico ? detalheTecnico : null,
    );
  }

  void reset() => value = const RegistroRefeicaoIaState();

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
