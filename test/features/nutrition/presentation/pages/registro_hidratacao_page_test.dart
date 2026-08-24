import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/repositories/perfil_usuario_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/registro_hidratacao_page.dart';

class _MockColetaRepository extends Mock implements ColetaDiariaRepository {}

class _MockPerfilRepository extends Mock implements PerfilUsuarioRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockColetaRepository coletaRepository;
  late _MockPerfilRepository perfilRepository;

  setUp(() {
    coletaRepository = _MockColetaRepository();
    perfilRepository = _MockPerfilRepository();

    when(() => coletaRepository.buscarTotalAguaDoDia()).thenAnswer((_) async => 0);
    when(() => perfilRepository.buscarTamanhoCopoMl()).thenAnswer((_) async => 200);
    when(() => coletaRepository.buscarHistoricoAgua()).thenAnswer((_) async => const []);
  });

  Widget criarApp() {
    return MaterialApp(
      home: RegistroHidratacaoPage(
        coletaRepository: coletaRepository,
        perfilRepository: perfilRepository,
      ),
    );
  }

  testWidgets('carrega e mostra o total de hoje e o tamanho do copo configurado', (tester) async {
    when(() => coletaRepository.buscarTotalAguaDoDia()).thenAnswer((_) async => 400);
    when(() => perfilRepository.buscarTamanhoCopoMl()).thenAnswer((_) async => 350);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Hoje: 400 ml'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '+1 copo (350 ml)'), findsOneWidget);
  });

  testWidgets('erro ao carregar mostra mensagem de erro, não quebra a tela', (tester) async {
    when(() => coletaRepository.buscarTotalAguaDoDia()).thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar seus dados de hidratação.'), findsOneWidget);
  });

  testWidgets('histórico vazio mostra a mensagem de "nenhum registro"', (tester) async {
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum registro nos últimos 7 dias.'), findsOneWidget);
  });

  testWidgets('histórico com dias mostra data e total formatados', (tester) async {
    when(() => coletaRepository.buscarHistoricoAgua()).thenAnswer(
      (_) async => [
        HidratacaoDia(data: DateTime(2026, 8, 19), totalMl: 550),
        HidratacaoDia(data: DateTime(2026, 8, 18), totalMl: 400),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('19/08/2026: 550 ml'), findsOneWidget);
    expect(find.text('18/08/2026: 400 ml'), findsOneWidget);
  });

  testWidgets('"+1 copo" registra o tamanho configurado e recarrega o total', (tester) async {
    when(() => coletaRepository.gravarAgua(mililitros: 200)).thenAnswer(
      (_) async => const ColetaDiariaResult(success: true),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '+1 copo (200 ml)'));
    await tester.pumpAndSettle();

    verify(() => coletaRepository.gravarAgua(mililitros: 200)).called(1);
    expect(find.text('Registrado!'), findsOneWidget);
    // "Sempre um SELECT novo" — buscarTotalAguaDoDia roda de novo no
    // carregamento inicial E de novo após o registro.
    verify(() => coletaRepository.buscarTotalAguaDoDia()).called(2);
  });

  testWidgets('quantidade customizada válida registra e limpa o campo', (tester) async {
    when(() => coletaRepository.gravarAgua(mililitros: 500)).thenAnswer(
      (_) async => const ColetaDiariaResult(success: true),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '500');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Adicionar'));
    await tester.pumpAndSettle();

    verify(() => coletaRepository.gravarAgua(mililitros: 500)).called(1);
  });

  testWidgets('quantidade customizada fora da faixa (1–5000ml) mostra erro, não chama o repositório', (tester) async {
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '9999');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Adicionar'));
    await tester.pumpAndSettle();

    expect(find.text('Quantidade deve estar entre 1 e 5000 ml'), findsOneWidget);
    verifyNever(() => coletaRepository.gravarAgua(mililitros: any(named: 'mililitros')));
  });

  testWidgets('falha ao registrar mostra a mensagem de erro do repositório', (tester) async {
    when(() => coletaRepository.gravarAgua(mililitros: 200)).thenAnswer(
      (_) async => const ColetaDiariaResult(success: false, errorMessage: 'Falhou de propósito'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '+1 copo (200 ml)'));
    await tester.pumpAndSettle();

    expect(find.text('Falhou de propósito'), findsOneWidget);
  });

  testWidgets('salvar tamanho do copo válido chama o repositório e atualiza o botão "+1 copo"', (tester) async {
    when(() => perfilRepository.atualizarTamanhoCopoMl(300)).thenAnswer((_) async {});

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, '300');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Salvar tamanho do copo'));
    await tester.pumpAndSettle();

    verify(() => perfilRepository.atualizarTamanhoCopoMl(300)).called(1);
    expect(find.widgetWithText(FilledButton, '+1 copo (300 ml)'), findsOneWidget);
  });

  testWidgets('tamanho do copo fora da faixa (50–1000ml) mostra erro, não chama o repositório', (tester) async {
    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, '9999');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Salvar tamanho do copo'));
    await tester.pumpAndSettle();

    expect(find.text('Tamanho do copo deve estar entre 50 e 1000 ml'), findsOneWidget);
    verifyNever(() => perfilRepository.atualizarTamanhoCopoMl(any()));
  });
}
