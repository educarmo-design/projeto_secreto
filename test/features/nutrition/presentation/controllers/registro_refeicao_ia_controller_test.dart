import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
        // RELATÓRIO 20260901_0003 — string arbitrária só pra provar que o
        // controller REPETE o que o serviço manda (não decide mensagem
        // nenhuma sozinho); a lógica real de qual mensagem usar por status
        // é testada em registro_refeicao_ia_service_test.dart.
        mensagemAmigavel: 'Erro no servidor. Tente novamente.',
        detalheTecnico: 'HTTP 502',
      ));

      await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.erro);
      expect(controller.value.errorMessage, 'Erro no servidor. Tente novamente.');
    });

    // RELATÓRIO 20260901_0003 — fallback defensivo do controller (o
    // serviço já embrulha isso em RegistroRefeicaoIaException antes de
    // chegar aqui no caminho real; estes testes cobrem o `catch` genérico
    // continuar correto se algum dia outro ponto de `acao()` lançar essas
    // exceções diretamente).
    test('TimeoutException direto (fallback) nunca vira "servidor ocupado"', () async {
      when(() => service.interpretarTexto(
            descricao: any(named: 'descricao'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenThrow(TimeoutException('sem resposta'));

      await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.erro);
      expect(controller.value.errorMessage, 'Tempo esgotado aguardando o servidor. Tente novamente.');
    });

    test('http.ClientException direto (fallback) nunca vira "servidor ocupado"', () async {
      when(() => service.interpretarTexto(
            descricao: any(named: 'descricao'),
            endpoint: any(named: 'endpoint'),
            headers: any(named: 'headers'),
          )).thenThrow(http.ClientException('Connection refused'));

      await controller.interpretarTexto(descricao: 'arroz', endpoint: endpoint);

      expect(controller.value.status, RegistroRefeicaoIaStatus.erro);
      expect(controller.value.errorMessage, 'Falha de conexão. Verifique sua internet e tente novamente.');
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
