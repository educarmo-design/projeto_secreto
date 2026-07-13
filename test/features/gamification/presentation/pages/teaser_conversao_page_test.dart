import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/gamification/data/services/esteira_trial_gateway_service.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/controllers/esteira_trial_controller.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/pages/teaser_conversao_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  // Etapa 0.5/1 (F21): o dia do trial não é mais calculado localmente a
  // partir de um relógio falso — vem da resposta de
  // `calculate-recovery-mode` (EsteiraTrialGatewayService), aqui simulada
  // com um MockClient que sempre devolve o `diaAtual` fixo pedido pelo
  // teste. `diasDesdeCadastro` é mantido só como nome do parâmetro para
  // minimizar o diff nos call sites abaixo — o valor vira diretamente o
  // `diaAtual` devolvido (dia = diasDesdeCadastro + 1, mesma fórmula que o
  // cálculo real no servidor usa a partir da âncora).
  EsteiraTrialController controllerNoDia(int diasDesdeCadastro) {
    final diaAtual = (diasDesdeCadastro + 1).clamp(1, 14);
    final gateway = EsteiraTrialGatewayService(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'diaAtual': diaAtual,
            'modoRecuperacaoAtivo': false,
            'metaMovimentoCumprida': false,
            'missoesExamesConcluidas': <int>[],
          }),
          200,
        );
      }),
    );
    return EsteiraTrialController(
      gatewayService: gateway,
      authHeadersProvider: () => const {},
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
