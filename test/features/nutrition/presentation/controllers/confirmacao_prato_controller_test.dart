import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/dashboard/data/models/health_payload_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/confirmacao_prato_controller.dart';

void main() {
  ItemPratoExtraidoModel item({
    String nomeCasado = 'Carne bovina, patinho, cru',
    String nomeIdentificado = 'bifinho',
    String medida = 'filé',
    double quantidadeOriginal = 1,
    double gramasEstimados = 100,
    double calorias = 130,
    double proteinasG = 22,
    double carboidratosG = 0,
    double gordurasG = 4,
    double confianca = 0.9,
  }) {
    return ItemPratoExtraidoModel(
      nomeCasado: nomeCasado,
      nomeIdentificado: nomeIdentificado,
      medida: medida,
      quantidadeOriginal: quantidadeOriginal,
      gramasEstimados: gramasEstimados,
      calorias: calorias,
      proteinasG: proteinasG,
      carboidratosG: carboidratosG,
      gordurasG: gordurasG,
      confianca: confianca,
    );
  }

  PratoRefeicaoExtracaoModel extracaoCom({
    List<ItemPratoExtraidoModel>? itens,
    List<ItemPratoNaoReconhecidoModel>? itensNaoReconhecidos,
    bool possivelFotoDeTela = false,
  }) {
    return PratoRefeicaoExtracaoModel(
      itens: itens ?? [item()],
      itensNaoReconhecidos: itensNaoReconhecidos ?? const [],
      possivelFotoDeTela: possivelFotoDeTela,
    );
  }

  test('estado inicial reflete a extração 1:1, com quantidadeAtual == quantidadeOriginal', () {
    final controller = ConfirmacaoPratoController(extracaoCom());

    expect(controller.value.itens, hasLength(1));
    final itemEditavel = controller.value.itens.single;
    expect(itemEditavel.quantidadeAtual, 1.0);
    expect(itemEditavel.calorias, 130.0);
    expect(controller.value.totalCalorias, 130.0);
  });

  test('incrementar dobra quantidade e macros proporcionalmente (regra de três)', () {
    final controller = ConfirmacaoPratoController(extracaoCom());

    controller.incrementar(0);

    final itemEditavel = controller.value.itens.single;
    expect(itemEditavel.quantidadeAtual, 2.0);
    expect(itemEditavel.calorias, 260.0);
    expect(itemEditavel.proteinasG, 44.0);
    expect(itemEditavel.carboidratosG, 0.0);
    expect(itemEditavel.gordurasG, 8.0);
    expect(itemEditavel.gramasEstimados, 200.0);
    expect(controller.value.totalCalorias, 260.0);
  });

  test('decrementar reduz macros proporcionalmente', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [item(quantidadeOriginal: 2, calorias: 260, proteinasG: 44)]),
    );

    controller.decrementar(0);

    final itemEditavel = controller.value.itens.single;
    expect(itemEditavel.quantidadeAtual, 1.0);
    expect(itemEditavel.calorias, 130.0);
    expect(itemEditavel.proteinasG, 22.0);
  });

  test('decrementar nunca reduz a quantidade abaixo de 1', () {
    final controller = ConfirmacaoPratoController(extracaoCom());

    controller.decrementar(0);
    controller.decrementar(0);
    controller.decrementar(0);

    expect(controller.value.itens.single.quantidadeAtual, 1.0);
  });

  test('ajustar um item não afeta os demais', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [
        item(nomeCasado: 'Arroz', calorias: 100),
        item(nomeCasado: 'Feijão', calorias: 80),
      ]),
    );

    controller.incrementar(0);

    expect(controller.value.itens[0].calorias, 200.0);
    expect(controller.value.itens[1].calorias, 80.0);
  });

  test('remover tira o item da lista e atualiza o total', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [
        item(nomeCasado: 'Arroz', calorias: 100),
        item(nomeCasado: 'Feijão', calorias: 80),
      ]),
    );

    controller.remover(0);

    expect(controller.value.itens, hasLength(1));
    expect(controller.value.itens.single.original.nomeCasado, 'Feijão');
    expect(controller.value.totalCalorias, 80.0);
  });

  test('chave permanece estável após remover outro item', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [
        item(nomeCasado: 'Arroz'),
        item(nomeCasado: 'Feijão'),
      ]),
    );

    controller.remover(0); // remove Arroz (chave 0)
    controller.incrementar(1); // ainda deve achar Feijão pela chave 1

    expect(controller.value.itens.single.original.nomeCasado, 'Feijão');
    expect(controller.value.itens.single.quantidadeAtual, 2.0);
  });

  test('itensNaoReconhecidos e possivelFotoDeTela são preservados no estado', () {
    const naoReconhecido = ItemPratoNaoReconhecidoModel(
      nome: 'sushi',
      medida: 'peça',
      motivo: 'alimento_nao_encontrado',
    );
    final controller = ConfirmacaoPratoController(
      extracaoCom(itensNaoReconhecidos: [naoReconhecido], possivelFotoDeTela: true),
    );

    expect(controller.value.itensNaoReconhecidos.single, naoReconhecido);
    expect(controller.value.possivelFotoDeTela, true);

    controller.incrementar(0);

    expect(controller.value.itensNaoReconhecidos.single, naoReconhecido);
    expect(controller.value.possivelFotoDeTela, true);
  });

  test('payloadRevisado reflete as quantidades já editadas, não as originais', () {
    final controller = ConfirmacaoPratoController(extracaoCom());
    controller.incrementar(0);

    final payload = controller.payloadRevisado();

    final itemPayload = (payload['itens'] as List).single as Map<String, dynamic>;
    expect(itemPayload['quantidade'], 2.0);
    expect(itemPayload['calorias'], 260.0);
    final totais = payload['totais'] as Map<String, dynamic>;
    expect(totais['calorias'], 260.0);
  });

  test('payloadRevisado inclui nome_identificado, confianca por item e itens_nao_reconhecidos', () {
    const naoReconhecido = ItemPratoNaoReconhecidoModel(
      nome: 'sushi',
      medida: 'peça',
      motivo: 'alimento_nao_encontrado',
    );
    final controller = ConfirmacaoPratoController(
      extracaoCom(
        itens: [item(nomeIdentificado: 'bifinho', confianca: 0.85)],
        itensNaoReconhecidos: [naoReconhecido],
      ),
    );

    final payload = controller.payloadRevisado();

    final itemPayload = (payload['itens'] as List).single as Map<String, dynamic>;
    expect(itemPayload['nome_identificado'], 'bifinho');
    expect(itemPayload['confianca'], 0.85);

    final naoReconhecidos = payload['itens_nao_reconhecidos'] as List;
    expect(naoReconhecidos, hasLength(1));
    final naoReconhecidoPayload = naoReconhecidos.single as Map<String, dynamic>;
    expect(naoReconhecidoPayload['nome'], 'sushi');
    expect(naoReconhecidoPayload['motivo'], 'alimento_nao_encontrado');
  });

  test('confiancaMinima é o menor valor entre os itens confirmados', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [
        item(nomeCasado: 'Arroz', confianca: 0.95),
        item(nomeCasado: 'Feijão', confianca: 0.62),
        item(nomeCasado: 'Carne', confianca: 0.88),
      ]),
    );

    expect(controller.value.confiancaMinima, 0.62);
  });

  test('confiancaMinima ignora item removido', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [
        item(nomeCasado: 'Arroz', confianca: 0.95),
        item(nomeCasado: 'Feijão', confianca: 0.62),
      ]),
    );

    controller.remover(1); // remove Feijão (pior confiança)

    expect(controller.value.confiancaMinima, 0.95);
  });

  test('confiancaMinima é null quando não há itens', () {
    final controller = ConfirmacaoPratoController(extracaoCom());
    controller.remover(0);

    expect(controller.value.confiancaMinima, isNull);
  });

  test('confirmar com sucesso grava via repositório e retorna true', () async {
    final fake = _FakeColetaDiariaRepository(resultado: const ColetaDiariaResult(success: true));
    final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: fake);
    controller.incrementar(0); // garante que o payload gravado reflete a edição

    final sucesso = await controller.confirmar();

    expect(sucesso, true);
    expect(fake.chamadas, hasLength(1));
    expect(fake.chamadas.single.confianca, 0.9);
    final itensGravados = fake.chamadas.single.payload['itens'] as List;
    expect((itensGravados.single as Map)['quantidade'], 2.0);
    expect(controller.value.salvando, false);
    expect(controller.value.erroSalvar, isNull);
  });

  test('confirmar preenche salvando=true durante a chamada', () async {
    final fake = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(success: true),
      atraso: const Duration(milliseconds: 10),
    );
    final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: fake);

    final future = controller.confirmar();
    expect(controller.value.salvando, true);

    await future;
    expect(controller.value.salvando, false);
  });

  test('confirmar bloqueia envio duplicado enquanto já está salvando', () async {
    final fake = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(success: true),
      atraso: const Duration(milliseconds: 10),
    );
    final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: fake);

    final primeira = controller.confirmar();
    final segunda = controller.confirmar(); // deve ser recusado imediatamente

    expect(await segunda, false);
    expect(await primeira, true);
    expect(fake.chamadas, hasLength(1)); // só a primeira chegou a chamar o repositório
  });

  test('confirmar com prato vazio nunca chama o repositório', () async {
    final fake = _FakeColetaDiariaRepository(resultado: const ColetaDiariaResult(success: true));
    final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: fake);
    controller.remover(0);

    final sucesso = await controller.confirmar();

    expect(sucesso, false);
    expect(fake.chamadas, isEmpty);
  });

  test('confirmar com falha expõe a mensagem amigável e preserva os itens', () async {
    final fake = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar a refeição agora. Tente novamente.',
        debugDetail: 'PostgrestException 42501: permission denied',
      ),
    );
    final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: fake);

    final sucesso = await controller.confirmar();

    expect(sucesso, false);
    expect(controller.value.salvando, false);
    expect(
      controller.value.erroSalvar,
      'Não foi possível salvar a refeição agora. Tente novamente.',
    );
    expect(controller.value.itens, hasLength(1)); // nada foi perdido
  });

  test('confirmar de novo depois de uma falha limpa o erro anterior', () async {
    final falha = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(success: false, errorMessage: 'Erro de rede.'),
    );
    final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: falha);
    await controller.confirmar();
    expect(controller.value.erroSalvar, isNotNull);

    falha.resultado = const ColetaDiariaResult(success: true);
    final sucesso = await controller.confirmar();

    expect(sucesso, true);
    expect(controller.value.erroSalvar, isNull);
  });

  test('totais somam múltiplos itens corretamente', () {
    final controller = ConfirmacaoPratoController(
      extracaoCom(itens: [
        item(calorias: 100, proteinasG: 10, carboidratosG: 20, gordurasG: 5),
        item(calorias: 200, proteinasG: 15, carboidratosG: 25, gordurasG: 8),
      ]),
    );

    expect(controller.value.totalCalorias, 300.0);
    expect(controller.value.totalProteinasG, 25.0);
    expect(controller.value.totalCarboidratosG, 45.0);
    expect(controller.value.totalGordurasG, 13.0);
  });

  test('prato vazio (todos os itens removidos) dá totais zerados', () {
    final controller = ConfirmacaoPratoController(extracaoCom());
    controller.remover(0);

    expect(controller.value.itens, isEmpty);
    expect(controller.value.totalCalorias, 0.0);
  });

  // RELATÓRIO 20260823 — `aoConfirmar` (editar CONTEÚDO de uma favorita já
  // salva): confirmar() precisa desviar para a função injetada em vez do
  // repositório padrão, sem perder a máquina de estado
  // (salvando/erroSalvar) que já existia.
  group('aoConfirmar (override do destino de confirmar)', () {
    test('quando presente, confirmar chama aoConfirmar em vez do repositório', () async {
      final fake = _FakeColetaDiariaRepository(resultado: const ColetaDiariaResult(success: true));
      final chamadasOverride = <({Map<String, dynamic> payload, double? confianca})>[];
      final controller = ConfirmacaoPratoController(
        extracaoCom(),
        repositorio: fake,
        aoConfirmar: (payload, confianca) async {
          chamadasOverride.add((payload: payload, confianca: confianca));
          return const ColetaDiariaResult(success: true);
        },
      );

      final sucesso = await controller.confirmar();

      expect(sucesso, true);
      expect(chamadasOverride, hasLength(1));
      expect(fake.chamadas, isEmpty); // repositório padrão nunca chamado
    });

    test('aoConfirmar recebe o payloadRevisado atual, refletindo edições', () async {
      Map<String, dynamic>? payloadRecebido;
      final controller = ConfirmacaoPratoController(
        extracaoCom(),
        aoConfirmar: (payload, confianca) async {
          payloadRecebido = payload;
          return const ColetaDiariaResult(success: true);
        },
      );
      controller.incrementar(0);

      await controller.confirmar();

      final itemPayload = (payloadRecebido!['itens'] as List).single as Map<String, dynamic>;
      expect(itemPayload['quantidade'], 2.0);
    });

    test('falha de aoConfirmar expõe erroSalvar do mesmo jeito que o repositório padrão', () async {
      final controller = ConfirmacaoPratoController(
        extracaoCom(),
        aoConfirmar: (payload, confianca) async => const ColetaDiariaResult(
          success: false,
          errorMessage: 'Não foi possível salvar as alterações agora. Tente novamente.',
        ),
      );

      final sucesso = await controller.confirmar();

      expect(sucesso, false);
      expect(controller.value.salvando, false);
      expect(
        controller.value.erroSalvar,
        'Não foi possível salvar as alterações agora. Tente novamente.',
      );
    });

    test('sem aoConfirmar, comportamento padrão (gravarRefeicao) é preservado', () async {
      final fake = _FakeColetaDiariaRepository(resultado: const ColetaDiariaResult(success: true));
      final controller = ConfirmacaoPratoController(extracaoCom(), repositorio: fake);

      await controller.confirmar();

      expect(fake.chamadas, hasLength(1));
    });
  });
}

/// Fake em memória — nunca toca `Supabase.instance` (mesmo espírito do
/// `_FakeGateway` de vinculos_controller_test.dart). [atraso] simula uma
/// chamada de rede em voo, para testar `salvando`/bloqueio de duplo envio.
class _FakeColetaDiariaRepository implements ColetaDiariaRepository {
  _FakeColetaDiariaRepository({required this.resultado, this.atraso});

  ColetaDiariaResult resultado;
  final Duration? atraso;
  final List<({Map<String, dynamic> payload, double? confianca})> chamadas = [];

  @override
  Future<ColetaDiariaResult> gravarRefeicao({
    required Map<String, dynamic> payloadRevisado,
    required double? confianca,
    DateTime? dataColeta,
  }) async {
    if (atraso != null) await Future<void>.delayed(atraso!);
    chamadas.add((payload: payloadRevisado, confianca: confianca));
    return resultado;
  }

  // N16 (RELATÓRIO 20260819) — este teste nunca exercita hidratação;
  // implementações mínimas só para satisfazer `implements
  // ColetaDiariaRepository` (interface completa, não um mock parcial).
  @override
  Future<ColetaDiariaResult> gravarAgua({
    required int mililitros,
    DateTime? dataColeta,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> buscarTotalAguaDoDia({DateTime? data}) => throw UnimplementedError();

  @override
  Future<List<HidratacaoDia>> buscarHistoricoAgua({int dias = 7}) =>
      throw UnimplementedError();

  // N15/N12 (RELATÓRIO 20260820) — mesma justificativa dos stubs acima.
  @override
  Future<ColetaDiariaResult> gravarLeituraAparelho({
    required HealthPayloadModel payload,
    required String atributo,
    DateTime? dataColeta,
  }) =>
      throw UnimplementedError();

  @override
  Future<ConsumoDia> buscarConsumoHoje() => throw UnimplementedError();
}
