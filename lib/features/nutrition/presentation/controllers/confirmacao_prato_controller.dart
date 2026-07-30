import 'package:flutter/foundation.dart';

import '../../data/models/prato_refeicao_extracao_model.dart';

/// Um [ItemPratoExtraidoModel] + a quantidade ATUAL escolhida pelo usuário
/// nesta tela — [original] nunca muda; só [quantidadeAtual] muda, e todo
/// macro exibido é derivado dela por regra de três simples sobre o que o
/// backend já calculou para [ItemPratoExtraidoModel.quantidadeOriginal].
/// Nenhuma requisição nova: é a mesma proporção que `calcularPrato` usaria
/// no servidor, só que aplicada localmente, em memória (Parte 11.3 — "IA
/// estima + usuário edita").
@immutable
class ItemPratoEditavel {
  /// Identidade estável do item na lista, independente de posição — sobrevive
  /// a edições de quantidade (que trocam a instância via [comQuantidade]) e a
  /// remoções de OUTROS itens (que mudariam o índice na lista).
  final int chave;
  final ItemPratoExtraidoModel original;
  final double quantidadeAtual;

  const ItemPratoEditavel({
    required this.chave,
    required this.original,
    required this.quantidadeAtual,
  });

  double get _fator => original.quantidadeOriginal == 0
      ? 0
      : quantidadeAtual / original.quantidadeOriginal;

  double get gramasEstimados => original.gramasEstimados * _fator;
  double get calorias => original.calorias * _fator;
  double get proteinasG => original.proteinasG * _fator;
  double get carboidratosG => original.carboidratosG * _fator;
  double get gordurasG => original.gordurasG * _fator;

  ItemPratoEditavel comQuantidade(double novaQuantidade) => ItemPratoEditavel(
        chave: chave,
        original: original,
        quantidadeAtual: novaQuantidade,
      );
}

@immutable
class ConfirmacaoPratoState {
  final List<ItemPratoEditavel> itens;
  final List<ItemPratoNaoReconhecidoModel> itensNaoReconhecidos;
  final bool possivelFotoDeTela;

  const ConfirmacaoPratoState({
    required this.itens,
    required this.itensNaoReconhecidos,
    required this.possivelFotoDeTela,
  });

  double get totalCalorias => itens.fold(0.0, (soma, item) => soma + item.calorias);
  double get totalProteinasG => itens.fold(0.0, (soma, item) => soma + item.proteinasG);
  double get totalCarboidratosG =>
      itens.fold(0.0, (soma, item) => soma + item.carboidratosG);
  double get totalGordurasG => itens.fold(0.0, (soma, item) => soma + item.gordurasG);
}

/// Orquestra a Tela de Confirmação do Prato (F10 Passo 3): parte da
/// extração já calculada pelo backend e deixa o usuário ajustar
/// quantidade/remover itens ANTES de confirmar — tudo em memória, sem
/// round-trip ao servidor. Nunca grava sozinho: [payloadRevisado] só monta
/// o payload final revisado; persistir no diário é escopo do F34.
class ConfirmacaoPratoController extends ValueNotifier<ConfirmacaoPratoState> {
  ConfirmacaoPratoController(PratoRefeicaoExtracaoModel extracao)
      : super(
          ConfirmacaoPratoState(
            itens: [
              for (var i = 0; i < extracao.itens.length; i++)
                ItemPratoEditavel(
                  chave: i,
                  original: extracao.itens[i],
                  quantidadeAtual: extracao.itens[i].quantidadeOriginal,
                ),
            ],
            itensNaoReconhecidos: extracao.itensNaoReconhecidos,
            possivelFotoDeTela: extracao.possivelFotoDeTela,
          ),
        );

  /// Incremento de 1 unidade — mesma granularidade que o Gemini reporta
  /// (medida caseira inteira: "1 escumadeira" -> "2 escumadeiras"). O botão
  /// [-] nunca reduz abaixo de 1: zerar um item é a ação explícita de
  /// remover ([remover]), não um efeito colateral de decrementar demais.
  static const double _quantidadeMinima = 1;
  static const double _passo = 1;

  void incrementar(int chave) => _ajustarQuantidade(chave, _passo);

  void decrementar(int chave) => _ajustarQuantidade(chave, -_passo);

  void _ajustarQuantidade(int chave, double delta) {
    value = ConfirmacaoPratoState(
      itens: value.itens.map((item) {
        if (item.chave != chave) return item;
        final novaQuantidade = item.quantidadeAtual + delta;
        return item.comQuantidade(
          novaQuantidade < _quantidadeMinima ? _quantidadeMinima : novaQuantidade,
        );
      }).toList(),
      itensNaoReconhecidos: value.itensNaoReconhecidos,
      possivelFotoDeTela: value.possivelFotoDeTela,
    );
  }

  void remover(int chave) {
    value = ConfirmacaoPratoState(
      itens: value.itens.where((item) => item.chave != chave).toList(),
      itensNaoReconhecidos: value.itensNaoReconhecidos,
      possivelFotoDeTela: value.possivelFotoDeTela,
    );
  }

  /// Payload final revisado pelo usuário — hoje só impresso no console
  /// (Critério de Aceite #6); F34 decide como isto vira uma gravação em
  /// `refeicoes_diario`/tabela equivalente.
  Map<String, dynamic> payloadRevisado() {
    return {
      'itens': value.itens
          .map((item) => {
                'nome': item.original.nomeCasado,
                'medida': item.original.medida,
                'quantidade': item.quantidadeAtual,
                'gramas_estimados': item.gramasEstimados,
                'calorias': item.calorias,
                'proteinas_g': item.proteinasG,
                'carboidratos_g': item.carboidratosG,
                'gorduras_g': item.gordurasG,
              })
          .toList(),
      'totais': {
        'calorias': value.totalCalorias,
        'proteinas_g': value.totalProteinasG,
        'carboidratos_g': value.totalCarboidratosG,
        'gorduras_g': value.totalGordurasG,
      },
    };
  }
}
