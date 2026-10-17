import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/auth/presentation/controllers/cadastro_controller.dart';
import 'package:atleta_gamificacao/features/dashboard/data/repositories/perfil_usuario_repository.dart';
import 'package:atleta_gamificacao/features/dashboard/presentation/pages/meu_perfil_page.dart';
import 'package:atleta_gamificacao/features/vinculos/data/models/vinculo_ativo_model.dart';
import 'package:atleta_gamificacao/features/vinculos/data/services/vinculos_service.dart';

class _MockRepository extends Mock implements PerfilUsuarioRepository {}

class _MockVinculosService extends Mock implements VinculosService {}

class _MockHttpClient extends Mock implements http.Client {}

/// RELATÓRIO 20261016_0005 (Tela de Perfil, item 1) + RELATÓRIO
/// 20261016_0009 (paridade — telefone/endereço completo + ViaCEP).
/// Restrição da tarefa: email/tipo de perfil/vínculos nunca editáveis
/// aqui — nenhum teste deste arquivo exercita um caminho de escrita para
/// eles. `CadastroController` é SEMPRE injetado com um `http.Client`
/// mockado (nunca o real) — nenhum teste aqui faz uma chamada de rede de
/// verdade pro ViaCEP.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(Uri.parse('https://viacep.com.br/ws/00000000/json/'));
  });

  late _MockRepository repository;
  late _MockVinculosService vinculosService;
  late _MockHttpClient httpClient;
  late CadastroController cepController;

  setUp(() {
    repository = _MockRepository();
    vinculosService = _MockVinculosService();
    httpClient = _MockHttpClient();
    cepController = CadastroController(httpClient: httpClient);
    when(() => vinculosService.carregarVinculosAtivos()).thenAnswer((_) async => const []);
    // Default seguro: qualquer CEP digitado num teste que não é sobre
    // ViaCEP cai num "não encontrado" (resposta real do ViaCEP pra CEP
    // inexistente) — nunca um MissingStubError, nunca rede de verdade.
    when(() => httpClient.get(any())).thenAnswer((_) async => http.Response('{"erro": true}', 200));
  });

  Widget criarApp() {
    return MaterialApp(
      home: MeuPerfilPage(
        repository: repository,
        vinculosService: vinculosService,
        cepController: cepController,
      ),
    );
  }

  /// Preenche os 5 campos de endereço sem passar pelo ViaCEP — usado por
  /// todo teste que só quer chegar num formulário válido pra salvar,
  /// deixando a busca automática pra seus próprios testes dedicados.
  Future<void> preencherEnderecoManualmente(WidgetTester tester) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '01001000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rua'), 'Praça da Sé');
    await tester.enterText(find.widgetWithText(TextFormField, 'Bairro'), 'Sé');
    await tester.enterText(find.widgetWithText(TextFormField, 'Cidade'), 'São Paulo');
    await tester.enterText(find.widgetWithText(TextFormField, 'Estado'), 'SP');
  }

  testWidgets('mostra email, tipo de perfil (paciente) e pré-preenche nome/telefone/endereço', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(
        email: 'atleta@teste.com',
        ehProfissional: false,
        nome: 'Maria Silva',
        telefone: '11999999999',
        cep: '01001000',
        logradouro: 'Praça da Sé',
        bairro: 'Sé',
        cidade: 'São Paulo',
        estado: 'SP',
      ),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('atleta@teste.com'), findsOneWidget);
    expect(find.text('Paciente'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Nome')).controller?.text, 'Maria Silva');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Telefone')).controller?.text, '11999999999');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Rua')).controller?.text, 'Praça da Sé');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Bairro')).controller?.text, 'Sé');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Cidade')).controller?.text, 'São Paulo');
    expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Estado')).controller?.text, 'SP');
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
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), '');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe seu nome'), findsOneWidget);
    verifyNever(() => repository.atualizarDadosConta(
          nome: any(named: 'nome'),
          telefone: any(named: 'telefone'),
          cep: any(named: 'cep'),
          logradouro: any(named: 'logradouro'),
          bairro: any(named: 'bairro'),
          cidade: any(named: 'cidade'),
          estado: any(named: 'estado'),
        ));
  });

  testWidgets('salvar com telefone vazio mostra erro de validação', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false, nome: 'Maria'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await preencherEnderecoManualmente(tester);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Telefone inválido'), findsOneWidget);
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
  });

  testWidgets('salvar com endereço incompleto (bairro vazio) mostra erro de validação', (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false, nome: 'Maria'),
    );

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Telefone'), '11999999999');
    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '01001000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rua'), 'Praça da Sé');
    await tester.enterText(find.widgetWithText(TextFormField, 'Cidade'), 'São Paulo');
    await tester.enterText(find.widgetWithText(TextFormField, 'Estado'), 'SP');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Preencha este campo'), findsOneWidget);
  });

  testWidgets('salvar com tudo preenchido chama atualizarDadosConta com o payload completo e mostra sucesso',
      (tester) async {
    when(() => repository.buscarPerfilConta()).thenAnswer(
      (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false),
    );
    when(() => repository.atualizarDadosConta(
          nome: any(named: 'nome'),
          telefone: any(named: 'telefone'),
          cep: any(named: 'cep'),
          logradouro: any(named: 'logradouro'),
          bairro: any(named: 'bairro'),
          cidade: any(named: 'cidade'),
          estado: any(named: 'estado'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nome'), 'João Pereira');
    await tester.enterText(find.widgetWithText(TextFormField, 'Telefone'), '11999999999');
    await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '01001-000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Rua'), 'Praça da Sé');
    await tester.enterText(find.widgetWithText(TextFormField, 'Bairro'), 'Sé');
    await tester.enterText(find.widgetWithText(TextFormField, 'Cidade'), 'São Paulo');
    await tester.enterText(find.widgetWithText(TextFormField, 'Estado'), 'SP');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await tester.pumpAndSettle();

    verify(() => repository.atualizarDadosConta(
          nome: 'João Pereira',
          telefone: '11999999999',
          cep: '01001000',
          logradouro: 'Praça da Sé',
          bairro: 'Sé',
          cidade: 'São Paulo',
          estado: 'SP',
        )).called(1);
    expect(find.text('Dados salvos com sucesso'), findsOneWidget);
  });

  // RELATÓRIO 20261016_0009 (item 2 — ViaCEP) — mesmo mecanismo de
  // `CadastroController`, só que agora dentro de `MeuPerfilPage`.
  group('busca automática de endereço por CEP (ViaCEP)', () {
    testWidgets('CEP de 8 dígitos preenche Rua/Bairro/Cidade/Estado automaticamente', (tester) async {
      when(() => repository.buscarPerfilConta()).thenAnswer(
        (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false, nome: 'Maria'),
      );
      when(() => httpClient.get(any())).thenAnswer(
        (_) async => http.Response(
          '{"cep": "01001-000", "logradouro": "Praça da Sé", "bairro": "Sé", "localidade": "São Paulo", "uf": "SP"}',
          200,
        ),
      );

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '01001000');
      await tester.pumpAndSettle();

      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Rua')).controller?.text, 'Praça da Sé');
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Bairro')).controller?.text, 'Sé');
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Cidade')).controller?.text, 'São Paulo');
      expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Estado')).controller?.text, 'SP');
    });

    testWidgets('CEP inexistente mostra o aviso de CEP inválido, não quebra a tela', (tester) async {
      when(() => repository.buscarPerfilConta()).thenAnswer(
        (_) async => const PerfilContaResumo(email: 'atleta@teste.com', ehProfissional: false, nome: 'Maria'),
      );
      when(() => httpClient.get(any())).thenAnswer((_) async => http.Response('{"erro": true}', 200));

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'CEP'), '00000000');
      await tester.pumpAndSettle();

      expect(find.text('CEP inválido'), findsOneWidget);
    });
  });
}
