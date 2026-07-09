import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/gamification/presentation/controllers/esteira_trial_controller.dart';

import '../../../../support/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cadastro = DateTime(2026, 7, 1);

  Future<EsteiraTrialController> criarEAguardar({
    required FakeSecureStorage storage,
    required DateTime relogio,
    DateTime? dataCadastro,
  }) async {
    final controller = EsteiraTrialController(
      dataCadastro: dataCadastro ?? cadastro,
      secureStorage: storage,
      relogio: () => relogio,
    );
    await Future<void>.delayed(Duration.zero);
    return controller;
  }

  group('cálculo do dia atual', () {
    test('carregando começa true e vira false após inicializar', () async {
      final controller = EsteiraTrialController(
        dataCadastro: cadastro,
        secureStorage: FakeSecureStorage(),
        relogio: () => cadastro,
      );

      expect(controller.value.carregando, isTrue);
      expect(controller.value.diaAtual, 1);

      await Future<void>.delayed(Duration.zero);

      expect(controller.value.carregando, isFalse);
    });

    test('dia 1 no dia do cadastro', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro,
      );

      expect(controller.value.diaAtual, 1);
    });

    test('avança um dia por dia corrido desde o cadastro', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro.add(const Duration(days: 6)),
      );

      expect(controller.value.diaAtual, 7);
    });

    test('é limitado a 14 mesmo muito depois do fim do trial', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro.add(const Duration(days: 40)),
      );

      expect(controller.value.diaAtual, 14);
      expect(controller.value.diasRestantes, 0);
    });

    test('diasRestantes reflete 14 - diaAtual', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro.add(const Duration(days: 3)),
      );

      expect(controller.value.diaAtual, 4);
      expect(controller.value.diasRestantes, 10);
    });
  });

  group('Regra de Congelamento', () {
    test('ativar o Modo Recuperação trava o dia atual', () async {
      final storage = FakeSecureStorage();
      final controller = await criarEAguardar(
        storage: storage,
        relogio: cadastro.add(const Duration(days: 5)),
      );
      expect(controller.value.diaAtual, 6);

      await controller.ativarModoRecuperacao();

      expect(controller.value.modoRecuperacaoAtivo, isTrue);
      expect(controller.value.diaAtual, 6);
    });

    test(
      'o congelamento persiste entre sessões mesmo com o relógio real avançando',
      () async {
        final storage = FakeSecureStorage();
        final sessaoA = await criarEAguardar(
          storage: storage,
          relogio: cadastro.add(const Duration(days: 5)),
        );
        await sessaoA.ativarModoRecuperacao();
        expect(sessaoA.value.diaAtual, 6);

        // Nova "sessão" (ex.: usuário reabriu o app), 5 dias de calendário
        // depois, ainda com a recuperação ativa — o dia deve continuar
        // congelado em 6, não pular para 11.
        final sessaoB = await criarEAguardar(
          storage: storage,
          relogio: cadastro.add(const Duration(days: 10)),
        );

        expect(sessaoB.value.modoRecuperacaoAtivo, isTrue);
        expect(sessaoB.value.diaAtual, 6);
      },
    );

    test(
      'desativar retoma exatamente de onde parou e estende o prazo do trial',
      () async {
        final storage = FakeSecureStorage();
        final sessaoA = await criarEAguardar(
          storage: storage,
          relogio: cadastro.add(const Duration(days: 5)),
        );
        await sessaoA.ativarModoRecuperacao();

        // Reabre 5 dias depois, ainda congelado, e desativa a recuperação
        // nesse exato instante.
        final sessaoB = await criarEAguardar(
          storage: storage,
          relogio: cadastro.add(const Duration(days: 10)),
        );
        await sessaoB.desativarModoRecuperacao();

        expect(sessaoB.value.modoRecuperacaoAtivo, isFalse);
        // Retoma exatamente do dia 6 — nem zera, nem pula para o dia 11.
        expect(sessaoB.value.diaAtual, 6);

        // 3 dias corridos depois de desativar: o contador volta a andar
        // normalmente a partir de onde parou.
        final sessaoC = await criarEAguardar(
          storage: storage,
          relogio: cadastro.add(const Duration(days: 13)),
        );
        expect(sessaoC.value.diaAtual, 9);

        // Sem o congelamento de 5 dias, o dia 13 corresponderia ao dia 14
        // do trial (13 dias decorridos); com o congelamento, é o dia 9 —
        // os 5 dias parados foram preservados, não descontados do trial.
      },
    );

    test('desativar sem nunca ter ativado é um no-op seguro', () async {
      final storage = FakeSecureStorage();
      final controller = await criarEAguardar(
        storage: storage,
        relogio: cadastro.add(const Duration(days: 2)),
      );

      await controller.desativarModoRecuperacao();

      expect(controller.value.modoRecuperacaoAtivo, isFalse);
      expect(controller.value.diaAtual, 3);
    });
  });

  group('Gatilho do Dia 7', () {
    test('não dispara antes do dia 7 mesmo com a Semana 1 completa', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro,
      );

      await controller.registrarMetaMovimentoCumprida();
      await controller.registrarMissaoExameConcluida(1);

      expect(controller.value.diaAtual, 1);
      expect(controller.value.missoesSemana1Completas, isTrue);
      expect(controller.value.gatilhoDia7Ativo, isFalse);
    });

    test('não dispara no dia 7 se a Semana 1 estiver incompleta', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro.add(const Duration(days: 6)),
      );

      await controller.registrarMetaMovimentoCumprida();

      expect(controller.value.diaAtual, 7);
      expect(controller.value.uploadExamesSemana1Cumprido, isFalse);
      expect(controller.value.gatilhoDia7Ativo, isFalse);
    });

    test('dispara no dia 7 com meta de movimento e ao menos um exame', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro.add(const Duration(days: 6)),
      );

      await controller.registrarMetaMovimentoCumprida();
      expect(controller.value.gatilhoDia7Ativo, isFalse);

      await controller.registrarMissaoExameConcluida(3);
      expect(controller.value.gatilhoDia7Ativo, isTrue);
    });
  });

  group('missões de exame e meta de movimento', () {
    test('acumula múltiplos dias concluídos sem duplicar', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro.add(const Duration(days: 5)),
      );

      await controller.registrarMissaoExameConcluida(1);
      await controller.registrarMissaoExameConcluida(2);
      await controller.registrarMissaoExameConcluida(1);

      expect(controller.value.missoesExamesConcluidas, {1, 2});
      expect(controller.value.uploadExamesSemana1Cumprido, isTrue);
    });

    test('registrar a meta de movimento duas vezes é idempotente', () async {
      final controller = await criarEAguardar(
        storage: FakeSecureStorage(),
        relogio: cadastro,
      );

      await controller.registrarMetaMovimentoCumprida();
      await controller.registrarMetaMovimentoCumprida();

      expect(controller.value.metaMovimentoCumprida, isTrue);
    });

    test('estado persistido é recarregado em uma nova sessão', () async {
      final storage = FakeSecureStorage();
      final sessaoA = await criarEAguardar(
        storage: storage,
        relogio: cadastro.add(const Duration(days: 2)),
      );
      await sessaoA.registrarMetaMovimentoCumprida();
      await sessaoA.registrarMissaoExameConcluida(1);
      await sessaoA.registrarMissaoExameConcluida(2);

      final sessaoB = await criarEAguardar(
        storage: storage,
        relogio: cadastro.add(const Duration(days: 2)),
      );

      expect(sessaoB.value.metaMovimentoCumprida, isTrue);
      expect(sessaoB.value.missoesExamesConcluidas, {1, 2});
    });
  });
}
