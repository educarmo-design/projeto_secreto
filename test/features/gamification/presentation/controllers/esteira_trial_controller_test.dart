import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atleta_gamificacao/features/gamification/data/services/esteira_trial_gateway_service.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/controllers/esteira_trial_controller.dart';

/// Etapa 0.5 (F21): [EsteiraTrialController] não calcula mais o dia do
/// trial nem a janela de congelamento localmente — ele só repassa a
/// intenção do usuário para `calculate-recovery-mode` e adota a resposta.
/// Esta suíte, portanto, não testa mais aritmética de datas (isso migrou
/// para o servidor, hoje um stub — ver `supabase/functions/
/// calculate-recovery-mode/index_test.ts`); testa o contrato entre o
/// controller e o gateway: qual `acao` cada método público dispara, e como
/// o estado local reage a sucesso/erro do servidor.
void main() {
  final cadastro = DateTime(2026, 7, 1);

  EsteiraTrialGatewayService gatewayComRespostas(
    Map<String, dynamic> Function(Map<String, dynamic> corpo) responder,
  ) {
    final mockClient = MockClient((request) async {
      final corpo = jsonDecode(request.body) as Map<String, dynamic>;
      final resposta = responder(corpo);
      return http.Response(jsonEncode(resposta), 200);
    });
    return EsteiraTrialGatewayService(httpClient: mockClient);
  }

  EsteiraTrialGatewayService gatewayComFalha({int status = 501}) {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'error': 'calculate-recovery-mode ainda não implementada.'}),
        status,
      );
    });
    return EsteiraTrialGatewayService(httpClient: mockClient);
  }

  Map<String, dynamic> estadoPadrao({
    int diaAtual = 1,
    bool modoRecuperacaoAtivo = false,
    bool metaMovimentoCumprida = false,
    List<int> missoesExamesConcluidas = const [],
  }) {
    return {
      'diaAtual': diaAtual,
      'modoRecuperacaoAtivo': modoRecuperacaoAtivo,
      'metaMovimentoCumprida': metaMovimentoCumprida,
      'missoesExamesConcluidas': missoesExamesConcluidas,
    };
  }

  group('consulta inicial', () {
    test('carregando começa true e vira false após a resposta do servidor',
        () async {
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((_) => estadoPadrao(diaAtual: 3)),
      );

      expect(controller.value.carregando, isTrue);
      expect(controller.value.diaAtual, 1);

      await Future<void>.delayed(Duration.zero);

      expect(controller.value.carregando, isFalse);
      expect(controller.value.diaAtual, 3);
    });

    test('a primeira chamada ao gateway usa a ação "consultar"', () async {
      String? acaoRecebida;
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((corpo) {
          acaoRecebida = corpo['acao'] as String;
          return estadoPadrao();
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(acaoRecebida, 'consultar');
      expect(controller.value.carregando, isFalse);
    });

    test('uma falha do servidor preenche erro sem travar em "carregando"',
        () async {
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComFalha(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.carregando, isFalse);
      expect(controller.value.erro, isNotNull);
      // Nenhum valor é inventado localmente como substituto — fica no
      // default neutro (dia 1, sem recuperação) até uma chamada bem
      // sucedida chegar.
      expect(controller.value.diaAtual, 1);
    });
  });

  group('Modo Recuperação — delega ao servidor', () {
    test('ativarModoRecuperacao envia "ativar_recuperacao" e adota a resposta',
        () async {
      String? acaoRecebida;
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((corpo) {
          acaoRecebida = corpo['acao'] as String;
          if (acaoRecebida == 'ativar_recuperacao') {
            return estadoPadrao(diaAtual: 6, modoRecuperacaoAtivo: true);
          }
          return estadoPadrao(diaAtual: 6);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.ativarModoRecuperacao();

      expect(acaoRecebida, 'ativar_recuperacao');
      expect(controller.value.modoRecuperacaoAtivo, isTrue);
      expect(controller.value.diaAtual, 6);
    });

    test(
        'desativarModoRecuperacao envia "desativar_recuperacao" e adota a '
        'resposta', () async {
      String? acaoRecebida;
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((corpo) {
          acaoRecebida = corpo['acao'] as String;
          if (acaoRecebida == 'desativar_recuperacao') {
            return estadoPadrao(diaAtual: 6, modoRecuperacaoAtivo: false);
          }
          return estadoPadrao(diaAtual: 6, modoRecuperacaoAtivo: true);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.desativarModoRecuperacao();

      expect(acaoRecebida, 'desativar_recuperacao');
      expect(controller.value.modoRecuperacaoAtivo, isFalse);
      expect(controller.value.diaAtual, 6);
    });

    test('uma falha ao ativar recuperação preserva o último estado conhecido '
        'e expõe o erro', () async {
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((_) => estadoPadrao(diaAtual: 6)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.value.diaAtual, 6);

      // Troca o gateway "por baixo" não é possível (é final) — em vez
      // disso, este teste usa uma segunda instância dedicada para simular
      // a falha isoladamente, mantendo o padrão de injeção do serviço.
      final controllerComFalha = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComFalha(status: 500),
      );
      await Future<void>.delayed(Duration.zero);
      await controllerComFalha.ativarModoRecuperacao();

      expect(controllerComFalha.value.erro, isNotNull);
    });
  });

  group('missões de exame e meta de movimento — delega ao servidor', () {
    test('registrarMetaMovimentoCumprida envia "registrar_meta_movimento"',
        () async {
      String? acaoRecebida;
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((corpo) {
          acaoRecebida = corpo['acao'] as String;
          return estadoPadrao(metaMovimentoCumprida: true);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.registrarMetaMovimentoCumprida();

      expect(acaoRecebida, 'registrar_meta_movimento');
      expect(controller.value.metaMovimentoCumprida, isTrue);
    });

    test(
        'registrarMissaoExameConcluida envia "registrar_missao_exame" com o '
        'dia informado', () async {
      String? acaoRecebida;
      int? diaRecebido;
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((corpo) {
          acaoRecebida = corpo['acao'] as String;
          diaRecebido = corpo['dia'] as int?;
          return estadoPadrao(missoesExamesConcluidas: [3]);
        }),
      );
      await Future<void>.delayed(Duration.zero);

      await controller.registrarMissaoExameConcluida(3);

      expect(acaoRecebida, 'registrar_missao_exame');
      expect(diaRecebido, 3);
      expect(controller.value.missoesExamesConcluidas, {3});
    });
  });

  group('Gatilho do Dia 7 (derivado do estado devolvido pelo servidor)', () {
    test('não dispara antes do dia 7 mesmo com a Semana 1 completa',
        () async {
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((_) => estadoPadrao(
              diaAtual: 1,
              metaMovimentoCumprida: true,
              missoesExamesConcluidas: [1],
            )),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.missoesSemana1Completas, isTrue);
      expect(controller.value.gatilhoDia7Ativo, isFalse);
    });

    test('dispara no dia 7 com meta de movimento e ao menos um exame',
        () async {
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        authHeadersProvider: () => const {},
        gatewayService: gatewayComRespostas((_) => estadoPadrao(
              diaAtual: 7,
              metaMovimentoCumprida: true,
              missoesExamesConcluidas: [3],
            )),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.gatilhoDia7Ativo, isTrue);
    });
  });
}
