import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atleta_gamificacao/features/nutrition/data/services/registro_refeicao_ia_service.dart';

const _respostaValida = {
  'itens': [
    {'nome': 'Arroz', 'nome_identificado': 'arroz', 'medida': 'colher de sopa', 'quantidade': 2, 'gramas_estimados': 50, 'calorias': 64, 'proteinas_g': 1.3, 'carboidratos_g': 14.1, 'gorduras_g': 0.1, 'confianca': 0.9},
  ],
  'itens_nao_reconhecidos': [],
  'totais': {'calorias': 64, 'proteinas_g': 1.3, 'carboidratos_g': 14.1, 'gorduras_g': 0.1},
};

void main() {
  final endpoint = Uri.parse('http://localhost/extract-metric-photo');

  group('interpretarTexto', () {
    test('200 devolve PratoRefeicaoExtracaoModel parseado', () async {
      http.Request? requisicaoCapturada;
      final client = MockClient((req) async {
        requisicaoCapturada = req;
        return http.Response(jsonEncode(_respostaValida), 200);
      });
      final service = RegistroRefeicaoIaService(httpClient: client);

      final extracao = await service.interpretarTexto(
        descricao: 'arroz 2 colheres',
        endpoint: endpoint,
        headers: {'Authorization': 'Bearer x'},
      );

      expect(extracao.itens, hasLength(1));
      expect(extracao.itens.single.calorias, 64);
      expect(requisicaoCapturada!.headers['X-Tipo-Aparelho'], 'pratoRefeicaoTexto');
      expect(requisicaoCapturada!.headers['Authorization'], 'Bearer x');
      expect(requisicaoCapturada!.body, 'arroz 2 colheres');
    });

    // RELATÓRIO 20260901_0003 (achado do teste físico — "Servidor Ocupado"
    // fantasma): 502 sem mensagem do backend NÃO é mais "servidor ocupado"
    // — só 503/504 genuínos usam esse texto. Ver testes abaixo.
    test('502 sem mensagem do backend vira "erro no servidor", nunca "servidor ocupado"', () async {
      final client = MockClient((req) async => http.Response('{}', 502));
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Erro no servidor. Tente novamente.',
          ),
        ),
      );
    });

    test('502 COM mensagem do backend usa a mensagem real (nunca joga fora)', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'error': 'Falha ao analisar a imagem.'}), 502),
      );
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Falha ao analisar a imagem.',
          ),
        ),
      );
    });

    test('503/504 sem mensagem do backend são o único caso genuíno de "servidor ocupado"', () async {
      final client503 = MockClient((req) async => http.Response('{}', 503));
      final service503 = RegistroRefeicaoIaService(httpClient: client503);
      await expectLater(
        service503.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Servidor ocupado. Tente novamente em instantes.',
          ),
        ),
      );

      final client504 = MockClient((req) async => http.Response('{}', 504));
      final service504 = RegistroRefeicaoIaService(httpClient: client504);
      await expectLater(
        service504.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Servidor ocupado. Tente novamente em instantes.',
          ),
        ),
      );
    });

    // N45 (decisão 93, R44): HTTP 402 = saldo/faturamento do Gemini. Mensagem
    // própria, uma única chamada (o app nunca retenta) e jamais "servidor
    // ocupado" nem "erro no servidor" (Regras 15 e 23).
    test('402 vira mensagem própria de faturamento, com 1 única chamada e sem "ocupado"', () async {
      var chamadas = 0;
      final client = MockClient((req) async {
        chamadas++;
        return http.Response(jsonEncode({'error': 'texto qualquer do backend'}), 402);
      });
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>()
              .having((e) => e.mensagemAmigavel, 'mensagemAmigavel', RegistroRefeicaoIaService.mensagemSaldoIaIndisponivel)
              .having((e) => e.mensagemAmigavel.toLowerCase().contains('ocupado'), 'diz ocupado', false)
              .having((e) => e.mensagemAmigavel.contains('faturamento'), 'cita faturamento', true),
        ),
      );
      expect(chamadas, 1);
    });

    test('402 com corpo vazio também usa a mensagem própria (não cai em "erro no servidor")', () async {
      final client = MockClient((req) async => http.Response('', 402));
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            RegistroRefeicaoIaService.mensagemSaldoIaIndisponivel,
          ),
        ),
      );
    });

    test('timeout do cliente nunca vira "servidor ocupado" — mensagem de tempo esgotado', () async {
      final client = MockClient((req) async {
        // Nunca resolve dentro do timeout curto injetado abaixo — força o
        // `.timeout()` do serviço a disparar de verdade (não é um mock
        // instantâneo nem um teste de 90s reais).
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response(jsonEncode(_respostaValida), 200);
      });
      final service = RegistroRefeicaoIaService(
        httpClient: client,
        uploadTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Tempo esgotado aguardando o servidor. Tente novamente.',
          ),
        ),
      );
    });

    test('falha de conexão (ClientException) nunca vira "servidor ocupado" — mensagem de rede', () async {
      final client = MockClient((req) async {
        throw http.ClientException('Connection refused');
      });
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Falha de conexão. Verifique sua internet e tente novamente.',
          ),
        ),
      );
    });

    test('400 com corpo {"message": ...} usa a mensagem do backend', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'error': 'leitura_ilegivel', 'message': 'Descrição vazia.'}), 400),
      );
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: '', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Descrição vazia.',
          ),
        ),
      );
    });
  });

  group('interpretarAudio', () {
    test('200 devolve PratoRefeicaoExtracaoModel, manda X-Tipo-Aparelho/X-Image-Mime certos', () async {
      http.Request? requisicaoCapturada;
      final client = MockClient((req) async {
        requisicaoCapturada = req;
        return http.Response(jsonEncode(_respostaValida), 200);
      });
      final service = RegistroRefeicaoIaService(httpClient: client);

      final extracao = await service.interpretarAudio(
        bytesAudio: [1, 2, 3, 4],
        mimeType: 'audio/mp4',
        endpoint: endpoint,
      );

      expect(extracao.itens, hasLength(1));
      expect(requisicaoCapturada!.headers['X-Tipo-Aparelho'], 'pratoRefeicaoAudio');
      expect(requisicaoCapturada!.headers['X-Image-Mime'], 'audio/mp4');
      expect(requisicaoCapturada!.bodyBytes, [1, 2, 3, 4]);
    });
  });
}
