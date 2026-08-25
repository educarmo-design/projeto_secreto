import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/services/registro_refeicao_ia_service.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/registro_refeicao_ia_controller.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/gravar_refeicao_page.dart';

class _MockAudioRecorder extends Mock implements AudioRecorder {}

class _MockService extends Mock implements RegistroRefeicaoIaService {}

/// `getTemporaryDirectory()` (usado por `_iniciarGravacao` pra escolher
/// onde o `record` grava o clipe temporário) não tem plugin nenhum
/// registrado em ambiente de teste puro (`flutter test`, sem device) — sem
/// este fake, a chamada lança `MissingPluginException` dentro de
/// `_iniciarGravacao`, ANTES do `setState` que muda pro estado "gravando",
/// e a UI nunca sai do estado inicial (achado real ao investigar por que
/// "Gravando..." nunca aparecia nos testes).
class _FakePathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(const RecordConfig());
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  late _MockAudioRecorder recorder;
  late RegistroRefeicaoIaController controller;

  setUp(() {
    recorder = _MockAudioRecorder();
    controller = RegistroRefeicaoIaController();
    when(() => recorder.dispose()).thenAnswer((_) async {});
  });

  Future<void> pumpPagina(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GravarRefeicaoPage(controller: controller, recorder: recorder, authHeadersProvider: () => const {}),
      ),
    );
    await tester.pump();
  }

  testWidgets('sem permissão de microfone mostra aviso, não tenta gravar', (tester) async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => false);

    await pumpPagina(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();

    expect(find.text('Precisamos da permissão do microfone para gravar sua refeição.'), findsOneWidget);
    verifyNever(() => recorder.start(any(), path: any(named: 'path')));
  });

  testWidgets('com permissão, tocar no microfone inicia a gravação (mostra "Gravando...")', (tester) async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(() => recorder.start(any(), path: any(named: 'path'))).thenAnswer((_) async {});

    await pumpPagina(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();

    expect(find.text('Gravando...'), findsOneWidget);
    verify(() => recorder.start(any(), path: any(named: 'path'))).called(1);

    // Descarta a árvore ANTES do fim do teste — dispara `dispose()`, que
    // cancela o Timer de 90s (`_limiteDuracao`, `dart:async`, não o
    // `recorder`); sem isso o `flutter_test` acusa "Timer ainda pendente"
    // ao encerrar o teste com a gravação em andamento.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelar durante a gravação chama recorder.cancel() e volta pro estado inicial', (tester) async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(() => recorder.start(any(), path: any(named: 'path'))).thenAnswer((_) async {});
    when(() => recorder.cancel()).thenAnswer((_) async {});

    await pumpPagina(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
    await tester.pumpAndSettle();

    verify(() => recorder.cancel()).called(1);
    expect(find.byIcon(Icons.mic_none), findsOneWidget); // voltou pro estado idle
  });

  testWidgets('gravar, parar e enviar com sucesso abre ConfirmacaoPratoPage; arquivo temporário é apagado',
      (tester) async {
    final service = _MockService();
    final controllerComMock = RegistroRefeicaoIaController(service: service);
    registerFallbackValue(Uri.parse('http://localhost'));

    // Arquivo real temporário — o `stop()` do plugin real devolveria um
    // caminho de arquivo de verdade; aqui simulamos isso pra
    // `File(caminho).readAsBytes()` ter o que ler.
    //
    // ACHADO: `testWidgets` roda o corpo do teste inteiro dentro de uma
    // zona `FakeAsync` (é assim que `pump()`/`pumpAndSettle()` controlam o
    // tempo sem esperar de verdade); operações de I/O REAIS do `dart:io`
    // (aqui, e dentro de `_pararEEnviar` no widget: `readAsBytes`/`delete`)
    // dependem do loop de eventos de verdade (`dart:isolate
    // _RawReceivePort._handleMessage`, confirmado no stack trace do hang) e
    // por isso NUNCA completam dentro da zona fake — travam pra sempre, não
    // importa quantos `pump()` sejam chamados depois. `tester.runAsync()` é
    // a saída documentada: roda o `callback` numa zona de verdade.
    final arquivoTemporario = File('${Directory.systemTemp.path}/teste_gravar_refeicao.m4a');
    await tester.runAsync(() => arquivoTemporario.writeAsBytes([1, 2, 3, 4]));

    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(() => recorder.start(any(), path: any(named: 'path'))).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer((_) async => arquivoTemporario.path);
    when(() => service.interpretarAudio(
          bytesAudio: any(named: 'bytesAudio'),
          mimeType: any(named: 'mimeType'),
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) async => const PratoRefeicaoExtracaoModel(
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
        ));

    await tester.pumpWidget(
      MaterialApp(
        home: GravarRefeicaoPage(
          controller: controllerComMock,
          recorder: recorder,
          authHeadersProvider: () => const {},
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
    // `_pararEEnviar` faz I/O real (`File.readAsBytes`/`File.delete`) antes
    // de chamar o service mockado — uma vez que o `tap()` entra nessa
    // cadeia real, ELA CONTINUA RODANDO na zona real independente da zona
    // fake do teste, então o `tap()` E os pumps que esperam a navegação
    // precisam ficar dentro do mesmo `runAsync`.
    //
    // MESMO DENTRO do `runAsync`, ainda não dá pra usar `pumpAndSettle()`
    // direto: enquanto a cadeia real não termina, a tela mostra
    // `CircularProgressIndicator` (indeterminado, `..repeat()` nunca
    // "assenta" sozinho) — se `pumpAndSettle()` for chamado antes da
    // navegação acontecer, ele terma em "pumpAndSettle timed out" (achado
    // real: com só 400ms de pump fixo, a cadeia real ainda não tinha
    // chegado no `readAsBytes()`). A saída é sondar em pumps curtos e
    // limitados até a tela de confirmação aparecer, só ENTÃO chamar
    // `pumpAndSettle()` (seguro, sem spinner na árvore).
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Parar e enviar'));
      // `tester.pump(duration)` só avança o relógio FAKE — não bloqueia
      // tempo de verdade nenhum, então não dá chance nenhuma pro I/O real
      // (rodando na zona real, fora do controle desse relógio) progredir
      // (achado real: 100 pumps(100ms) em sequência, sem nenhum delay de
      // verdade entre eles, e a cadeia real nem tinha saído do
      // `readAsBytes()`). Precisa de `Future.delayed` de verdade entre os
      // pumps pra ceder o loop de eventos real.
      var tentativas = 0;
      while (find.text('Confirmar Refeição').evaluate().isEmpty && tentativas < 50) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        tentativas++;
      }
      await tester.pumpAndSettle();
    });

    verify(() => service.interpretarAudio(
          bytesAudio: [1, 2, 3, 4],
          mimeType: 'audio/mp4',
          endpoint: any(named: 'endpoint'),
          headers: any(named: 'headers'),
        )).called(1);
    expect(find.text('Confirmar Refeição'), findsOneWidget);
    expect(await tester.runAsync(() => arquivoTemporario.exists()), false); // Zero Storage — apagado
  }, timeout: const Timeout(Duration(seconds: 20)));
}
