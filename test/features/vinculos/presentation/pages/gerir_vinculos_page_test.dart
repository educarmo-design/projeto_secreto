import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/vinculos/data/models/convite_vinculo_model.dart';
import 'package:atleta_gamificacao/features/vinculos/data/services/manage_professional_link_gateway_service.dart';
import 'package:atleta_gamificacao/features/vinculos/presentation/controllers/vinculos_controller.dart';
import 'package:atleta_gamificacao/features/vinculos/presentation/pages/gerir_vinculos_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  ConviteVinculoModel convite({
    String id = 'vinculo-1',
    String? nickname = 'dra_ana',
    bool comGarmin = false,
  }) {
    return ConviteVinculoModel(
      vinculoId: id,
      profissionalId: 'prof-1',
      profissionalNickname: nickname,
      tipoProfissional: 'Nutricionista',
      comEnvioGarmin: comGarmin,
      convidadoEm: DateTime(2026, 7, 10),
    );
  }

  VinculosController controllerCom({
    required List<ConviteVinculoModel> convites,
    ManageProfessionalLinkGatewayService? gateway,
  }) {
    return VinculosController(
      carregarConvitesFn: () async => convites,
      gateway: gateway ?? _FakeGateway(sucesso: true),
      authHeadersProvider: () => const {},
    );
  }

  Future<void> pumpPagina(WidgetTester tester, VinculosController controller) async {
    await tester.pumpWidget(
      MaterialApp(home: GerirVinculosPage(controller: controller)),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('lista vazia mostra o empty state', (tester) async {
    await pumpPagina(tester, controllerCom(convites: []));

    expect(find.text('Você não tem convites pendentes.'), findsOneWidget);
  });

  testWidgets('mostra o card do convite com nickname, tipo e aviso de privacidade', (tester) async {
    await pumpPagina(tester, controllerCom(convites: [convite()]));

    expect(find.text('dra_ana deseja acompanhar você'), findsOneWidget);
    expect(find.text('Nutricionista'), findsOneWidget);
    expect(find.text('Sem envio de treino ao Garmin'), findsOneWidget);
    expect(
      find.text(
        'Ao aceitar, este profissional terá acesso aos seus exames e métricas diárias. '
        'Você pode revogar esse acesso quando quiser.',
      ),
      findsOneWidget,
    );
    expect(find.text('Aceitar'), findsOneWidget);
    expect(find.text('Recusar'), findsOneWidget);
  });

  testWidgets('convite com tipo_produto com_garmin mostra o texto correspondente', (tester) async {
    await pumpPagina(tester, controllerCom(convites: [convite(comGarmin: true)]));

    expect(find.text('Com envio de treino ao Garmin'), findsOneWidget);
  });

  testWidgets('nickname nulo cai no rótulo genérico', (tester) async {
    await pumpPagina(tester, controllerCom(convites: [convite(nickname: null)]));

    expect(find.text('Um profissional deseja acompanhar você'), findsOneWidget);
  });

  testWidgets('aceitar chama aceitar_vinculo, remove o card e mostra confirmação', (tester) async {
    final gateway = _FakeGateway(sucesso: true);
    await pumpPagina(tester, controllerCom(convites: [convite()], gateway: gateway));

    await tester.tap(find.text('Aceitar'));
    await tester.pumpAndSettle();

    expect(gateway.chamadas.single, (AcaoVinculoPaciente.aceitar, 'vinculo-1'));
    expect(find.text('dra_ana deseja acompanhar você'), findsNothing);
    expect(find.text('Convite aceito. dra_ana já pode acompanhar seus dados.'), findsOneWidget);
    expect(find.text('Você não tem convites pendentes.'), findsOneWidget);
  });

  testWidgets('recusar pede confirmação; cancelar mantém o convite na lista', (tester) async {
    final gateway = _FakeGateway(sucesso: true);
    await pumpPagina(tester, controllerCom(convites: [convite()], gateway: gateway));

    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();

    expect(find.text('Recusar convite?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(gateway.chamadas, isEmpty); // nada foi enviado ao servidor
    expect(find.text('dra_ana deseja acompanhar você'), findsOneWidget);
  });

  testWidgets('recusar confirmado chama encerrar_vinculo e remove o card', (tester) async {
    final gateway = _FakeGateway(sucesso: true);
    await pumpPagina(tester, controllerCom(convites: [convite()], gateway: gateway));

    await tester.tap(find.text('Recusar'));
    await tester.pumpAndSettle();
    // O diálogo também tem um botão "Recusar" (ação de confirmação) — usa o
    // último encontrado, que é o do AlertDialog (renderizado por cima).
    await tester.tap(find.text('Recusar').last);
    await tester.pumpAndSettle();

    expect(gateway.chamadas.single, (AcaoVinculoPaciente.recusar, 'vinculo-1'));
    expect(find.text('Você não tem convites pendentes.'), findsOneWidget);
  });

  testWidgets('falha do gateway mantém o card e mostra o erro', (tester) async {
    final gateway = _FakeGateway(sucesso: false, erro: 'Sessão expirada.');
    await pumpPagina(tester, controllerCom(convites: [convite()], gateway: gateway));

    await tester.tap(find.text('Aceitar'));
    await tester.pumpAndSettle();

    expect(find.text('Sessão expirada.'), findsOneWidget);
    expect(find.text('dra_ana deseja acompanhar você'), findsOneWidget); // continua na lista
  });
}

class _FakeGateway implements ManageProfessionalLinkGatewayService {
  _FakeGateway({required this.sucesso, this.erro});

  final bool sucesso;
  final String? erro;
  final List<(AcaoVinculoPaciente, String)> chamadas = [];

  @override
  Future<ManageProfessionalLinkResult> executar({
    required AcaoVinculoPaciente acao,
    required String vinculoId,
    required Map<String, String> authHeaders,
  }) async {
    chamadas.add((acao, vinculoId));
    return ManageProfessionalLinkResult(success: sucesso, errorMessage: erro);
  }
}
