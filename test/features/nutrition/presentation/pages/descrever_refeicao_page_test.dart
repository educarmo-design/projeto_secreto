import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/services/registro_refeicao_ia_service.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/registro_refeicao_ia_controller.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/descrever_refeicao_page.dart';

class _MockService extends Mock implements RegistroRefeicaoIaService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(Uri.parse('http://localhost'));
  });

  late _MockService service;
  late RegistroRefeicaoIaController controller;

  setUp(() {
    service = _MockService();
    controller = RegistroRefeicaoIaController(service: service);
  });

  Future<void> pumpPagina(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DescreverRefeicaoPage(controller: controller, authHeadersProvider: () => const {}),
      ),
    );
    await tester.pump();
  }

  const extracaoComItem = PratoRefeicaoExtracaoModel(
    itens: [
      ItemPratoExtraidoModel(
        nomeCasado: 'Arroz, branco, cozido',
        nomeIdentificado: 'arroz',
        medida: 'colher de sopa',
        quantidadeOriginal: 2,
        gramasEstimados: 50,
        calorias: 64,
        proteinasG: 1.3,
        carboidratosG: 14.1,
        gordurasG: 0.1,
        confianca: 0.9,
      ),
    ],
    itensNaoReconhecidos: [],
    possivelFotoDeTela: false,
  );

  testWidgets('botão Interpretar desabilitado quando o campo está vazio não impede tap, mas nada acontece sem texto',
      (tester) async {
    await pumpPagina(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Interpretar'));
    await tester.pump();

    verifyNever(() => service.interpretarTexto(
          descricao: any(named: 'descricao'),
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        ));
  });

  testWidgets('digitar e interpretar com sucesso abre ConfirmacaoPratoPage', (tester) async {
    when(() => service.interpretarTexto(
          descricao: any(named: 'descricao'),
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) async => extracaoComItem);

    await pumpPagina(tester);

    await tester.enterText(find.byType(TextField), 'arroz 2 colheres');
    await tester.tap(find.widgetWithText(FilledButton, 'Interpretar'));
    // NUNCA `pumpAndSettle()` direto após um tap que mostra
    // `CircularProgressIndicator` (indeterminado, `..repeat()` nunca
    // "assenta" sozinho) — mesmo cuidado documentado em
    // `confirmacao_prato_page_test.dart#pumpEConfirmar`: processa o Future
    // mockado com `pump()` primeiro, cobre a transição de rota com uma
    // duração fixa, só then `pumpAndSettle()`.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    verify(() => service.interpretarTexto(
          descricao: 'arroz 2 colheres',
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).called(1);
    expect(find.text('Confirmar Refeição'), findsOneWidget);
    expect(find.text('arroz'), findsOneWidget);
  });

  testWidgets('erro do servidor mostra a mensagem, não navega', (tester) async {
    when(() => service.interpretarTexto(
          descricao: any(named: 'descricao'),
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).thenThrow(const RegistroRefeicaoIaException(
      // RELATÓRIO 20260901_0003 — string arbitrária só pra provar que a
      // tela REPETE o que o controller manda; qual mensagem é escolhida
      // por status/exceção é testado em registro_refeicao_ia_service_test.dart.
      mensagemAmigavel: 'Erro no servidor. Tente novamente.',
      detalheTecnico: 'HTTP 502',
    ));

    await pumpPagina(tester);
    await tester.enterText(find.byType(TextField), 'arroz');
    await tester.tap(find.widgetWithText(FilledButton, 'Interpretar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Erro no servidor. Tente novamente.'), findsOneWidget);
    expect(find.text('Confirmar Refeição'), findsNothing);
  });

  // RELATÓRIO 20260902_0001 — mitigação de latência (Regra 4): depois de
  // 15s esperando o servidor, a mensagem do botão troca pra um aviso de
  // demora, sem interromper o spinner nem "piscar" a tela.
  testWidgets('depois de 15s esperando a resposta, troca a mensagem pro aviso de demora', (tester) async {
    // Completer em vez de `thenAnswer((_) async => ...)` — controla
    // manualmente QUANDO a resposta chega, pra poder avançar o relógio
    // fake do teste (`tester.pump(duration)`) até passar dos 15s antes de
    // resolver (sem completer, o Future resolveria no próximo microtask,
    // nunca dando tempo do timer de 15s disparar).
    final completer = Completer<PratoRefeicaoExtracaoModel>();
    when(() => service.interpretarTexto(
          descricao: any(named: 'descricao'),
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) => completer.future);

    await pumpPagina(tester);
    await tester.enterText(find.byType(TextField), 'arroz 2 colheres');
    await tester.tap(find.widgetWithText(FilledButton, 'Interpretar'));
    await tester.pump();

    expect(find.text('Interpretando...'), findsOneWidget);
    expect(find.text('Ainda analisando, pode levar um pouco mais...'), findsNothing);

    // Ainda não passou 15s — mensagem original continua (timer não
    // reinicia, não pisca).
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Interpretando...'), findsOneWidget);

    // Passa dos 15s — dispara o timer; pump extra cobre o crossfade de
    // 300ms do `AnimatedSwitcher`.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Ainda analisando, pode levar um pouco mais...'), findsOneWidget);
    expect(find.text('Interpretando...'), findsNothing);

    // Resolve — sai do estado de espera, aviso de demora some, navega.
    completer.complete(extracaoComItem);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar Refeição'), findsOneWidget);
  });
}
