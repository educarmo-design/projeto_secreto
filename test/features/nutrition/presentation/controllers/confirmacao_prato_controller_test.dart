import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
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
}
