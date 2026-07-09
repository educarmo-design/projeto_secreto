import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/controllers/esteira_trial_controller.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/pages/teaser_conversao_page.dart';

import '../../../../support/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  // Não usa `Future.delayed` para esperar o carregamento assíncrono do
  // controller: dentro de `testWidgets`, timers/delays só avançam quando o
  // relógio falso do binding é avançado via `tester.pump()` — um
  // `Future.delayed` "solto" nunca dispara e trava o teste. O controller é
  // construído síncrono aqui; os dois `tester.pump()` depois de
  // `pumpWidget` drenam a cadeia de `await`s do FakeSecureStorage
  // (puramente microtasks, sem timer real).
  EsteiraTrialController controllerNoDia(int diasDesdeCadastro) {
    final cadastro = DateTime(2026, 7, 1);
    return EsteiraTrialController(
      dataCadastro: cadastro,
      secureStorage: FakeSecureStorage(),
      relogio: () => cadastro.add(Duration(days: diasDesdeCadastro)),
    );
  }

  testWidgets('renderiza título, oferta e botão de conversão', (tester) async {
    final controller = controllerNoDia(6); // dia 7

    await tester.pumpWidget(
      MaterialApp(
        home: TeaserConversaoPage(
          controller: controller,
          onLiberarProjecao: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Sua Projeção de Longevidade está pronta'), findsOneWidget);
    expect(find.text('Dia 7 de 14 — Oferta Especial'), findsOneWidget);
    expect(find.text('Liberar Projeção de Longevidade'), findsOneWidget);
    expect(find.text('R\$ 179,90/ano após 14 dias grátis'), findsOneWidget);
    expect(
      find.text('Cancele quando quiser durante o período gratuito'),
      findsOneWidget,
    );
  });

  testWidgets('o badge do dia reflete o diaAtual real do controller', (tester) async {
    final controller = controllerNoDia(9); // dia 10

    await tester.pumpWidget(
      MaterialApp(
        home: TeaserConversaoPage(
          controller: controller,
          onLiberarProjecao: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Dia 10 de 14 — Oferta Especial'), findsOneWidget);
  });

  testWidgets('tocar no CTA aciona onLiberarProjecao uma vez', (tester) async {
    final controller = controllerNoDia(6);
    var chamadas = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TeaserConversaoPage(
          controller: controller,
          onLiberarProjecao: () => chamadas++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Liberar Projeção de Longevidade'));
    await tester.pump();

    expect(chamadas, 1);
  });

  testWidgets(
    'o gráfico e os insights ficam atrás de um BackdropFilter borrado',
    (tester) async {
      final controller = controllerNoDia(6);

      await tester.pumpWidget(
        MaterialApp(
          home: TeaserConversaoPage(
            controller: controller,
            onLiberarProjecao: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);

      // O conteúdo "real" continua na árvore de widgets — é o blur que o
      // esconde visualmente, não a ausência do conteúdo.
      expect(find.text('Insights Preventivos'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    },
  );
}
