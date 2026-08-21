import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/models/health_payload_model.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/controllers/camera_capture_controller.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/widgets/health_payload_dialog.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';

class _MockColetaRepository extends Mock implements ColetaDiariaRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(
      HealthPayloadModel(dateFrom: DateTime(2026), dateTo: DateTime(2026), source: 'camera'),
    );
  });

  late _MockColetaRepository repository;

  setUp(() {
    repository = _MockColetaRepository();
  });

  Widget criarApp(HealthPayloadModel payload, TipoAparelho tipo) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => mostrarDialogoConfirmarLeituraAparelho(
              context,
              payload: payload,
              tipoAparelho: tipo,
              repository: repository,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
  }

  // N15 (RELATÓRIO 20260820) — ACHADO REAL: antes desta tarefa, confirmar
  // este diálogo não gravava nada em lugar nenhum.
  testWidgets('confirmar grava via gravarLeituraAparelho com o atributo certo e mostra snack de sucesso', (tester) async {
    when(() => repository.gravarLeituraAparelho(
          payload: any(named: 'payload'),
          atributo: any(named: 'atributo'),
        )).thenAnswer((_) async => const ColetaDiariaResult(success: true));

    final payload = HealthPayloadModel(
      pesoKg: 80.6,
      dateFrom: DateTime(2026, 8, 20),
      dateTo: DateTime(2026, 8, 20),
      source: 'camera',
    );

    await tester.pumpWidget(criarApp(payload, TipoAparelho.balanca));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    verify(() => repository.gravarLeituraAparelho(payload: payload, atributo: 'balanca'))
        .called(1);
    expect(find.text('Leitura salva com sucesso'), findsOneWidget);
  });

  testWidgets('cancelar nunca chama o repositório', (tester) async {
    final payload = HealthPayloadModel(
      pesoKg: 80.6,
      dateFrom: DateTime(2026, 8, 20),
      dateTo: DateTime(2026, 8, 20),
      source: 'camera',
    );

    await tester.pumpWidget(criarApp(payload, TipoAparelho.balanca));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.gravarLeituraAparelho(
          payload: any(named: 'payload'),
          atributo: any(named: 'atributo'),
        ));
  });

  testWidgets('falha ao gravar mostra a mensagem de erro do repositório', (tester) async {
    when(() => repository.gravarLeituraAparelho(
          payload: any(named: 'payload'),
          atributo: any(named: 'atributo'),
        )).thenAnswer(
      (_) async => const ColetaDiariaResult(success: false, errorMessage: 'Falhou de propósito'),
    );

    final payload = HealthPayloadModel(
      pressaoSistolica: 120,
      dateFrom: DateTime(2026, 8, 20),
      dateTo: DateTime(2026, 8, 20),
      source: 'camera',
    );

    await tester.pumpWidget(criarApp(payload, TipoAparelho.pressaoArterial));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    verify(() => repository.gravarLeituraAparelho(payload: payload, atributo: 'pressao_arterial'))
        .called(1);
    expect(find.text('Falhou de propósito'), findsOneWidget);
  });

  testWidgets('glicosimetro mapeia pro atributo glicosimetro', (tester) async {
    when(() => repository.gravarLeituraAparelho(
          payload: any(named: 'payload'),
          atributo: any(named: 'atributo'),
        )).thenAnswer((_) async => const ColetaDiariaResult(success: true));

    final payload = HealthPayloadModel(
      glicoseJejum: 92,
      dateFrom: DateTime(2026, 8, 20),
      dateTo: DateTime(2026, 8, 20),
      source: 'camera',
    );

    await tester.pumpWidget(criarApp(payload, TipoAparelho.glicosimetro));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    verify(() => repository.gravarLeituraAparelho(payload: payload, atributo: 'glicosimetro'))
        .called(1);
  });
}
