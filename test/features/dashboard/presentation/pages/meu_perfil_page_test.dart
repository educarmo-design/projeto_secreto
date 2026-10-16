import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/repositories/perfil_usuario_repository.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/pages/meu_perfil_page.dart';
import 'package:atleta_gamificacao/features/vinculos/data/models/vinculo_ativo_model.dart';
import 'package:atleta_gamificacao/features/vinculos/data/services/vinculos_service.dart';

class _MockRepository extends Mock implements PerfilUsuarioRepository {}

class _MockVinculosService extends Mock implements VinculosService {}

/// RELATÓRIO 20261016_0005 (Tela de Perfil, item 1) — leitura (email, tipo
/// de perfil, profissionais vinculados) + edição restrita a Nome/CEP.
/// Restrição da tarefa: email/tipo de perfil/vínculos nunca editáveis
/// aqui — nenhum teste deste arquivo exercita um caminho de escrita para
/// eles, só para nome/cep.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  late _MockRepository repository;
  late _MockVinculosService vinculosService;

  setUp(() {
    repository = _MockRepository();
    vinculosService = _MockVinculosService();
    when(() => vinculosService.carregarVinculosAtivos()).thenAnswer((_) async => const []);
  });

  Widget criarApp() {
    return MaterialApp(
      home: MeuPerfilPage(repository: repository, vinculosService: vinculosService),
    );
  }

  testWidgets('mostra email, tipo de perfil (paciente) e pré-preenche nome/cep', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(
        email: 'atleta@teste.com',
        ehProfissional: false,
        nome: 'Maria Silva',
        cep: '01001000',
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('atleta@teste.com'), findsOneWidget);
    expect(find.text('Paciente'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Nome'), findsOneWidget);
    final nomeField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Nome'));
    expect(nomeField.controller?.text, 'Maria Silva');
  });

  testWidgets('mostra o tipo de perfil profissional traduzido', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(
        email: 'nutri@teste.com',
        ehProfissional: true,
        tipoProfissional: 'Nutricionista',
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Nutricionista'), findsOneWidget);
  });

  testWidgets('lista os profissionais vinculados ativos', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false),
    );
    when(() => vinculosService.carregarVinculosAtivos()).thenAnswer(
      (_) async => const [
        VinculoAtivoModel(
          vinculoId: 'v1',
          profissionalId: 'p1',
          profissionalNickname: 'dra_ana',
          tipoProfissional: 'Nutricionista',
        ),
      ],
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('dra_ana'), findsOneWidget);
  });

  testWidgets('sem vínculo ativo, mostra o empty state', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Nenhum profissional acompanhando você no momento.'), findsOneWidget);
  });

  testWidgets('salvar com nome vazio mostra erro de validação e não grava nada', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false, cep: '01001000'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), '');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe seu nome'), findsOneWidget);
    verifyNever(() => repository.atualizarNomeECep(nome: any(named: 'nome'), cep: any(named: 'cep')));
  });

  testWidgets('salvar com CEP inválido (menos de 8 dígitos) mostra erro de validação', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false, nome: 'Maria'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '123');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('CEP deve ter 8 números'), findsOneWidget);
    verifyNever(() => repository.atualizarNomeECep(nome: any(named: 'nome'), cep: any(named: 'cep')));
  });

  testWidgets('salvar com nome e CEP válidos chama atualizarNomeECep e mostra sucesso', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false),
    );
    when(() => repository.atualizarNomeECep(nome: any(named: 'nome'), cep: any(named: 'cep')))
        .thenAnswer((_) async {});

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'João Pereira');
    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '01001-000');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    verify(() => repository.atualizarNomeECep(nome: 'João Pereira', cep: '01001000')).called(1);
    expect(find.text('Dados salvos com sucesso'), findsOneWidget);
  });
}
