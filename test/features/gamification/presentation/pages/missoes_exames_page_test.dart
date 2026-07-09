import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/controllers/esteira_trial_controller.dart';
import 'package:atleta_gamificacao/features/gamification/presentation/pages/missoes_exames_page.dart';

import '../../../../support/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  final hoje = DateTime(2026, 7, 1);

  // Não usa `Future.delayed` para esperar o carregamento assíncrono do
  // controller: dentro de `testWidgets`, timers/delays só avançam quando o
  // relógio falso do binding é avançado via `tester.pump()` — um
  // `Future.delayed` "solto" nunca dispara e trava o teste. `pumpPagina`
  // abaixo constrói o controller (síncrono) e deixa o `tester.pump()` do
  // primeiro frame drenar a cadeia de `await`s do FakeSecureStorage
  // (puramente microtasks, sem timer real).
  EsteiraTrialController controllerPronto() {
    return EsteiraTrialController(
      dataCadastro: hoje,
      secureStorage: FakeSecureStorage(),
      relogio: () => hoje,
    );
  }

  PlatformFile arquivoFalso({String nome = 'hemograma.pdf'}) {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    return PlatformFile(name: nome, size: bytes.length, bytes: bytes);
  }

  Future<void> pumpPagina(
    WidgetTester tester, {
    required EsteiraTrialController controller,
    required http.Client httpClient,
    Future<PlatformFile?> Function()? selecionarArquivo,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MissoesExamesPage(
          controller: controller,
          httpClient: httpClient,
          selecionarArquivo: selecionarArquivo ?? () async => arquivoFalso(),
          obterSessaoAtual: () => null,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renderiza as 6 missões, só o Dia 1 desbloqueado', (tester) async {
    final controller = controllerPronto();
    await pumpPagina(
      tester,
      controller: controller,
      httpClient: MockClient((_) async => http.Response('ok', 200)),
    );

    expect(find.text('Anexar PDF'), findsOneWidget);
    expect(find.text('Disponível no Dia 2'), findsOneWidget);
    expect(
      find.text(
        'Seus arquivos são processados em memória e nunca ficam salvos no aparelho.',
      ),
      findsOneWidget,
    );

    // O card do Dia 6 começa fora do viewport de teste — rola a lista até
    // ele aparecer para confirmar que os 6 cards existem, não só os 5
    // primeiros.
    await tester.scrollUntilVisible(find.text('Disponível no Dia 6'), 300);
    expect(find.text('Disponível no Dia 6'), findsOneWidget);
  });

  testWidgets('upload bem-sucedido conclui a missão do dia', (tester) async {
    final controller = controllerPronto();
    await pumpPagina(
      tester,
      controller: controller,
      httpClient: MockClient((request) async {
        expect(request.headers['X-Missao-Dia'], '1');
        return http.Response('ok', 200);
      }),
    );

    await tester.tap(find.text('Anexar PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Missão concluída'), findsOneWidget);
    expect(controller.value.missoesExamesConcluidas, {1});
  });

  testWidgets('cancelar o seletor de arquivo não altera o estado', (tester) async {
    final controller = controllerPronto();
    await pumpPagina(
      tester,
      controller: controller,
      httpClient: MockClient((_) async => http.Response('ok', 200)),
      selecionarArquivo: () async => null,
    );

    await tester.tap(find.text('Anexar PDF'));
    await tester.pumpAndSettle();

    expect(find.text('Anexar PDF'), findsOneWidget);
    expect(controller.value.missoesExamesConcluidas, isEmpty);
  });

  testWidgets('falha HTTP mostra erro e não conclui a missão', (tester) async {
    final controller = controllerPronto();
    await pumpPagina(
      tester,
      controller: controller,
      httpClient: MockClient((_) async => http.Response('erro', 500)),
    );

    await tester.tap(find.text('Anexar PDF'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível enviar o exame. Tente novamente.'),
      findsOneWidget,
    );
    expect(controller.value.missoesExamesConcluidas, isEmpty);
    expect(find.text('Anexar PDF'), findsOneWidget);
  });

  testWidgets('exceção de rede também mostra erro e libera o botão', (tester) async {
    final controller = controllerPronto();
    await pumpPagina(
      tester,
      controller: controller,
      httpClient: MockClient((_) async => throw Exception('sem rede')),
    );

    await tester.tap(find.text('Anexar PDF'));
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível enviar o exame. Tente novamente.'),
      findsOneWidget,
    );
    expect(find.text('Anexar PDF'), findsOneWidget);
  });
}
