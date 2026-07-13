import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/vinculos/data/models/convite_vinculo_model.dart';
import 'package:atleta_gamificacao/features/vinculos/data/services/manage_professional_link_gateway_service.dart';
import 'package:atleta_gamificacao/features/vinculos/presentation/controllers/vinculos_controller.dart';

void main() {
  ConviteVinculoModel convite({String id = 'vinculo-1', String? nickname = 'dra_ana'}) {
    return ConviteVinculoModel(
      vinculoId: id,
      profissionalId: 'prof-1',
      profissionalNickname: nickname,
      tipoProfissional: 'Nutricionista',
      comEnvioGarmin: false,
      convidadoEm: DateTime(2026, 7, 10),
    );
  }

  /// Gateway falso: nunca toca rede — devolve sucesso ou falha conforme
  /// configurado, e registra qual (acao, vinculoId) foi chamado, para os
  /// testes provarem que o controller não confunde aceitar com recusar.
  ({ManageProfessionalLinkGatewayService gateway, List<(AcaoVinculoPaciente, String)> chamadas})
      gatewayFalso({bool sucesso = true, String? erro}) {
    final chamadas = <(AcaoVinculoPaciente, String)>[];
    return (
      gateway: _FakeGateway(sucesso: sucesso, erro: erro, onChamada: chamadas.add),
      chamadas: chamadas,
    );
  }

  test('carrega os convites pendentes ao ser construído', () async {
    final controller = VinculosController(
      carregarConvitesFn: () async => [convite()],
      gateway: gatewayFalso().gateway,
      authHeadersProvider: () => const {},
    );

    // O construtor dispara carregarConvites() mas não espera por ele —
    // precisa de um microtask para a Future completar.
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.carregando, false);
    expect(controller.value.convites, hasLength(1));
    expect(controller.value.convites.first.vinculoId, 'vinculo-1');
  });

  test('lista vazia produz empty state (não erro)', () async {
    final controller = VinculosController(
      carregarConvitesFn: () async => [],
      gateway: gatewayFalso().gateway,
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.value.convites, isEmpty);
    expect(controller.value.erro, isNull);
  });

  test('aceitar com sucesso remove o convite da lista e chama aceitar_vinculo', () async {
    final fake = gatewayFalso();
    final controller = VinculosController(
      carregarConvitesFn: () async => [convite(id: 'vinculo-1'), convite(id: 'vinculo-2')],
      gateway: fake.gateway,
      authHeadersProvider: () => const {},
    );
    await Future<void>.delayed(Duration.zero);

    final sucesso = await controller.aceitar('vinculo-1');

    expect(sucesso, true);
    expect(controller.value.convites.map((c) => c.vinculoId), ['vinculo-2']);
    expect(controller.value.processandoVinculoId, isNull);
    expect(fake.chamadas.single, (AcaoVinculoPaciente.aceitar, 'vinculo-1'));
  });

  test('recusar com sucesso remove o convite e chama encerrar_vinculo', () async {
    final fake = gatewayFalso();
    final controller = VinculosController(
      carregarConvitesFn: () async => [convite(id: 'vinculo-1')],
      gateway: fake.gateway,
      authHeadersProvider: () => const {},
    );
    await Future<void>.delayed(Duration.zero);

    final sucesso = await controller.recusar('vinculo-1');

    expect(sucesso, true);
    expect(controller.value.convites, isEmpty);
    // "Recusar" não é uma ação própria do servidor — é encerrar_vinculo
    // aplicado a um vínculo pendente (ver manage_professional_link_gateway_
    // service.dart). Este assert é o que garante que o app nunca inventa uma
    // ação que o servidor não entende.
    expect(fake.chamadas.single, (AcaoVinculoPaciente.recusar, 'vinculo-1'));
  });

  test('falha do gateway preserva o convite na lista e expõe o erro', () async {
    final fake = gatewayFalso(sucesso: false, erro: 'Sessão expirada.');
    final controller = VinculosController(
      carregarConvitesFn: () async => [convite(id: 'vinculo-1')],
      gateway: fake.gateway,
      authHeadersProvider: () => const {},
    );
    await Future<void>.delayed(Duration.zero);

    final sucesso = await controller.aceitar('vinculo-1');

    expect(sucesso, false);
    expect(controller.value.convites, hasLength(1)); // nada foi removido
    expect(controller.value.erro, 'Sessão expirada.');
    expect(controller.value.processandoVinculoId, isNull);
  });

  test('carregarConvites de novo limpa o erro anterior', () async {
    final fake = gatewayFalso(sucesso: false, erro: 'Erro de rede.');
    final controller = VinculosController(
      carregarConvitesFn: () async => [convite(id: 'vinculo-1')],
      gateway: fake.gateway,
      authHeadersProvider: () => const {},
    );
    await Future<void>.delayed(Duration.zero);
    await controller.aceitar('vinculo-1');
    expect(controller.value.erro, isNotNull);

    await controller.carregarConvites();

    expect(controller.value.erro, isNull);
  });
}

/// Fake em memória — mesmo espírito do `fakeSupabaseAdmin` usado nos testes
/// Deno da Edge Function: implementa só o contrato que o controller chama,
/// sem tocar rede.
class _FakeGateway implements ManageProfessionalLinkGatewayService {
  _FakeGateway({required this.sucesso, this.erro, required this.onChamada});

  final bool sucesso;
  final String? erro;
  final void Function((AcaoVinculoPaciente, String) chamada) onChamada;

  @override
  Future<ManageProfessionalLinkResult> executar({
    required AcaoVinculoPaciente acao,
    required String vinculoId,
    required Map<String, String> authHeaders,
  }) async {
    onChamada((acao, vinculoId));
    return ManageProfessionalLinkResult(success: sucesso, errorMessage: erro);
  }
}
