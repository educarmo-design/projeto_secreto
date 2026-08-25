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

    test('500 vira RegistroRefeicaoIaException com mensagem de servidor ocupado', () async {
      final client = MockClient((req) async => http.Response('{}', 502));
      final service = RegistroRefeicaoIaService(httpClient: client);

      await expectLater(
        service.interpretarTexto(descricao: 'x', endpoint: endpoint),
        throwsA(
          isA<RegistroRefeicaoIaException>().having(
            (e) => e.mensagemAmigavel,
            'mensagemAmigavel',
            'Servidor ocupado. Tente novamente.',
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
