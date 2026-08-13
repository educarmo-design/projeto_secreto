import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/models/health_payload_model.dart';
import 'package:atleta_gamificacao/features/dashboard/data/repositories/telemetria_historico_repository.dart';
import 'package:atleta_gamificacao/features/dashboard/data/services/health_sync_service.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/controllers/sync_ui_controller.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/pages/historico_telemetria_page.dart';

class _MockRepository extends Mock implements TelemetriaHistoricoRepository {}

class _MockSyncUiController extends Mock implements SyncUiController {}

HealthPayloadModel _linha({
  required DateTime data,
  int? passos,
  int? fcRepouso,
  int? fcMaxima,
  double? hrvMedio,
  double? massaMagraKg,
  double? aguaCorporalKg,
  double? imc,
  double? caloriasAtivas,
  double? caloriasBasais,
  double? caloriasTotais,
}) {
  return HealthPayloadModel(
    passos: passos,
    fcRepouso: fcRepouso,
    fcMaxima: fcMaxima,
    hrvMedio: hrvMedio,
    massaMagraKg: massaMagraKg,
    aguaCorporalKg: aguaCorporalKg,
    imc: imc,
    caloriasAtivas: caloriasAtivas,
    caloriasBasais: caloriasBasais,
    caloriasTotais: caloriasTotais,
    dateFrom: data,
    dateTo: data,
    source: 'wearable',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;
  late _MockSyncUiController syncUiController;

  setUp(() {
    repository = _MockRepository();
    syncUiController = _MockSyncUiController();
    when(() => syncUiController.dispose()).thenReturn(null);
  });

  Widget criarApp() {
    return MaterialApp(
      home: HistoricoTelemetriaPage(
        repository: repository,
        syncUiController: syncUiController,
      ),
    );
  }

  testWidgets('carrega e mostra as linhas vindas do repositório (não de cache)', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer(
      (_) async => [
        _linha(data: DateTime(2026, 8, 8), passos: 4200, fcRepouso: 58),
        _linha(data: DateTime(2026, 6, 10), passos: 2000, massaMagraKg: 62.5),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('08/08/2026'), findsOneWidget);
    expect(find.text('10/06/2026'), findsOneWidget);
    expect(find.textContaining('Passos: 4200'), findsOneWidget);
    expect(find.textContaining('FC repouso: 58'), findsOneWidget);
    expect(find.textContaining('Massa magra (kg): 62.5'), findsOneWidget);
    verify(() => repository.buscarUltimosDias()).called(1);
  });

  testWidgets('mostra FC máxima, HRV, água corporal e IMC (RELATÓRIO 20260810_0005 — não apareciam antes)', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer(
      (_) async => [
        _linha(
          data: DateTime(2026, 8, 8),
          fcMaxima: 172,
          hrvMedio: 45.3,
          aguaCorporalKg: 38.4,
          imc: 24.7,
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('FC máxima: 172'), findsOneWidget);
    expect(find.textContaining('HRV: 45.3'), findsOneWidget);
    expect(find.textContaining('Água corporal (kg): 38.4'), findsOneWidget);
    expect(find.textContaining('IMC: 24.7'), findsOneWidget);
  });

  testWidgets('mostra Calorias totais/ativas/basais (RELATÓRIO 20260811_0002 — decisão do fundador, calorias granulares)', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer(
      (_) async => [
        _linha(
          data: DateTime(2026, 8, 8),
          caloriasAtivas: 480,
          caloriasBasais: 1650,
          caloriasTotais: 2130,
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Calorias totais (kcal): 2130'), findsOneWidget);
    expect(find.textContaining('Calorias ativas (kcal): 480'), findsOneWidget);
    expect(find.textContaining('Calorias basais (kcal): 1650'), findsOneWidget);
  });

  testWidgets('lista vazia mostra o empty state', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer((_) async => const []);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum dia com dado nos últimos 30 dias.'), findsOneWidget);
  });

  testWidgets('erro no SELECT mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => repository.buscarUltimosDias()).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar o histórico.'), findsOneWidget);
  });

  testWidgets('"FORÇAR SYNC HOJE" chama forcarSincronizacaoAtleta e recarrega do banco', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer((_) async => const []);
    when(() => syncUiController.forcarSincronizacaoAtleta()).thenAnswer(
      (_) async => const DeltaSyncResult(
        outcome: DeltaSyncOutcome.sucesso,
        linhas: [
          {'usuario_id_anonimo': 'u1', 'data_referencia': '2026-08-09'},
        ],
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('FORÇAR SYNC HOJE'));
    await tester.pumpAndSettle();

    verify(() => syncUiController.forcarSincronizacaoAtleta()).called(1);
    // Recarrega do banco depois do botão — não do retorno do próprio botão.
    verify(() => repository.buscarUltimosDias()).called(2);
    verifyNever(() => syncUiController.conectarWearablePelaPrimeiraVez());
  });

  testWidgets('"FORÇAR CARGA 30 DIAS" chama conectarWearablePelaPrimeiraVez e recarrega do banco', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer((_) async => const []);
    when(() => syncUiController.conectarWearablePelaPrimeiraVez()).thenAnswer(
      (_) async => const DeltaSyncResult(outcome: DeltaSyncOutcome.sucesso, linhas: []),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('FORÇAR CARGA 30 DIAS'));
    await tester.pumpAndSettle();

    verify(() => syncUiController.conectarWearablePelaPrimeiraVez()).called(1);
    verify(() => repository.buscarUltimosDias()).called(2);
    verifyNever(() => syncUiController.forcarSincronizacaoAtleta());
  });

  testWidgets('"GERAR LOG DIAGNÓSTICO (30 DIAS)" chama gerarDiagnosticoProfundo e recarrega do banco (RELATÓRIO 20260813_0015)', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer((_) async => const []);
    when(() => syncUiController.gerarDiagnosticoProfundo()).thenAnswer(
      (_) async => const DeltaSyncResult(outcome: DeltaSyncOutcome.sucesso, linhas: []),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('GERAR LOG DIAGNÓSTICO (30 DIAS)'));
    await tester.pumpAndSettle();

    verify(() => syncUiController.gerarDiagnosticoProfundo()).called(1);
    verify(() => repository.buscarUltimosDias()).called(2);
    verifyNever(() => syncUiController.forcarSincronizacaoAtleta());
    verifyNever(() => syncUiController.conectarWearablePelaPrimeiraVez());
    expect(
      find.text('Diagnóstico gerado — veja o console do Flutter (prefixo [SYNC_DIAGNOSTICO]).'),
      findsOneWidget,
    );
  });

  testWidgets('resultado offline do botão de debug mostra a mensagem de fila offline', (tester) async {
    when(() => repository.buscarUltimosDias()).thenAnswer((_) async => const []);
    when(() => syncUiController.forcarSincronizacaoAtleta()).thenAnswer(
      (_) async => const DeltaSyncResult(outcome: DeltaSyncOutcome.offline),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('FORÇAR SYNC HOJE'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sem conexão. Os dados serão enviados automaticamente assim que você estiver online.'),
      findsOneWidget,
    );
  });
}
