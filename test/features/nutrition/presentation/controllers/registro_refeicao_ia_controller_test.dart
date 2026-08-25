import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/services/registro_refeicao_ia_service.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/registro_refeicao_ia_controller.dart';

class _MockService extends Mock implements RegistroRefeicaoIaService {}

void main() {
  late _MockService service;
  late RegistroRefeicaoIaController controller;
  final endpoint = Uri.parse('http://localhost');

  setUpAll(() {
    registerFallbackValue(endpoint);
  });

  setUp(() {
    service = _MockService();
    controller = RegistroRefeicaoIaController(service: service);
  });

  const extracao = PratoRefeicaoExtracaoModel(itens: [], itensNaoReconhecidos: [], possivelFotoDeTela: false);

  group('interpretarTexto', () {
    test('sucesso: status vira sucesso com a extração', () async {
      when(() => service.interpretarTexto(
            descricao: any(named: 'descricao'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => extracao);

      await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.sucesso);
      expect(controller.value.extracao, extracao);
    });

    test('RegistroRefeicaoIaException vira erro com a mensagem amigável', () async {
      when(() => service.interpretarTexto(
            descricao: any(named: 'descricao'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenThrow(const RegistroRefeicaoIaException(
        mensagemAmigavel: 'Servidor ocupado. Tente novamente.',
        detalheTecnico: 'HTTP 502',
      ));

      await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.erro);
      expect(controller.value.errorMessage, 'Servidor ocupado. Tente novamente.');
    });

    test('FormatException (resposta malformada) vira erro sem derrubar o app', () async {
      when(() => service.interpretarTexto(
            descricao: any(named: 'descricao'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenThrow(const FormatException('itens ausente'));

      await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.erro);
      expect(controller.value.errorMessage, isNotNull);
    });

    test('processando fica true durante a chamada', () async {
      when(() => service.interpretarTexto(
            descricao: any(named: 'descricao'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return extracao;
      });

      final future = controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);
      expect(controller.value.isProcessando, true);
      await future;
      expect(controller.value.isProcessando, false);
    });
  });

  group('interpretarAudio', () {
    test('sucesso: status vira sucesso com a extração', () async {
      when(() => service.interpretarAudio(
            bytesAudio: any(named: 'bytesAudio'),
            mimeType: any(named: 'mimeType'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => extracao);

      await controller.interpretarAudio(bytesAudio: [1, 2, 3], mimeType: 'audio/mp4', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.sucesso);
    });
  });

  test('reset volta pro estado idle', () async {
    when(() => service.interpretarTexto(
          descricao: any(named: 'descricao'),
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) async => extracao);
    await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);
    expect(controller.value.status, RegistroRefeicaoIaStatus.sucesso);

    controller.reset();

    expect(controller.value.status, RegistroRefeicaoIaStatus.idle);
    expect(controller.value.extracao, isNull);
  });
}
