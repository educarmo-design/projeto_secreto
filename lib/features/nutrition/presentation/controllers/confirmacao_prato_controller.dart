import 'package:flutter/foundation.dart';

import '../../../../core/config/app_config.dart';
import '../../data/models/prato_refeicao_extracao_model.dart';
import '../../data/repositories/coleta_diaria_repository.dart';

/// Só liga a exposição do erro real na própria tela — mesmo helper (e mesma
/// justificativa) de `_podeExibirDetalheTecnico` em
/// `CameraCaptureController`, duplicado aqui de propósito: é uma função pura
/// de uma linha, e este arquivo não importa nada da camada de dashboard só
/// para reaproveitá-la (mesma escolha já registrada em
/// `search-food/index.ts` sobre CORS_HEADERS/ErroHttp duplicados entre Edge
/// Functions).
bool get _podeExibirDetalheTecnico => kDebugMode || AppConfig.debugMode;

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

  /// True enquanto [ConfirmacaoPratoController.confirmar] está em voo —
  /// bloqueia o botão Confirmar (nunca dois envios simultâneos da mesma
  /// refeição).
  final bool salvando;

  /// Não-nulo quando a última tentativa de salvar falhou — mensagem
  /// amigável, sempre visível.
  final String? erroSalvar;

  /// Classe/mensagem técnica real por trás de [erroSalvar] — só visível em
  /// debug (Regra 0.15), nunca em produção.
  final String? debugDetalheErroSalvar;

  const ConfirmacaoPratoState({
    required this.itens,
    required this.itensNaoReconhecidos,
    required this.possivelFotoDeTela,
    this.salvando = false,
    this.erroSalvar,
    this.debugDetalheErroSalvar,
  });

  double get totalCalorias => itens.fold(0.0, (soma, item) => soma + item.calorias);
  double get totalProteinasG => itens.fold(0.0, (soma, item) => soma + item.proteinasG);
  double get totalCarboidratosG =>
      itens.fold(0.0, (soma, item) => soma + item.carboidratosG);
  double get totalGordurasG => itens.fold(0.0, (soma, item) => soma + item.gordurasG);

  /// Confiança agregada da refeição inteira: o MÍNIMO entre os itens
  /// confirmados — "a leitura da refeição é tão confiável quanto seu item
  /// menos confiável" (mesma filosofia conservadora já usada em
  /// `BUSCA_SEMANTICA_THRESHOLD`: melhor subestimar confiança do que
  /// inflar). `null` só quando não sobrou nenhum item (Confirmar já fica
  /// desabilitado nesse caso).
  double? get confiancaMinima {
    if (itens.isEmpty) return null;
    return itens.map((item) => item.original.confianca).reduce((a, b) => a < b ? a : b);
  }

  ConfirmacaoPratoState copyWith({
    List<ItemPratoEditavel>? itens,
    bool? salvando,
    String? erroSalvar,
    bool limparErroSalvar = false,
    String? debugDetalheErroSalvar,
  }) {
    return ConfirmacaoPratoState(
      itens: itens ?? this.itens,
      itensNaoReconhecidos: itensNaoReconhecidos,
      possivelFotoDeTela: possivelFotoDeTela,
      salvando: salvando ?? this.salvando,
      erroSalvar: limparErroSalvar ? null : (erroSalvar ?? this.erroSalvar),
      debugDetalheErroSalvar:
          limparErroSalvar ? null : (debugDetalheErroSalvar ?? this.debugDetalheErroSalvar),
    );
  }
}

/// Orquestra a Tela de Confirmação do Prato (F10 Passo 3 + F34): parte da
/// extração já calculada pelo backend, deixa o usuário ajustar
/// quantidade/remover itens EM MEMÓRIA (sem round-trip ao servidor), e só
/// então [confirmar] grava o payload revisado em `coleta_diaria` via
/// [ColetaDiariaRepository].
class ConfirmacaoPratoController extends ValueNotifier<ConfirmacaoPratoState> {
  ConfirmacaoPratoController(
    PratoRefeicaoExtracaoModel extracao, {
    ColetaDiariaRepository? repositorio,
  })  : _repositorio = repositorio ?? ColetaDiariaRepository(),
        super(
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

  final ColetaDiariaRepository _repositorio;

  /// Incremento de 1 unidade — mesma granularidade que o Gemini reporta
  /// (medida caseira inteira: "1 escumadeira" -> "2 escumadeiras"). O botão
  /// [-] nunca reduz abaixo de 1: zerar um item é a ação explícita de
  /// remover ([remover]), não um efeito colateral de decrementar demais.
  static const double _quantidadeMinima = 1;
  static const double _passo = 1;

  void incrementar(int chave) => _ajustarQuantidade(chave, _passo);

  void decrementar(int chave) => _ajustarQuantidade(chave, -_passo);

  void _ajustarQuantidade(int chave, double delta) {
    value = value.copyWith(
      itens: value.itens.map((item) {
        if (item.chave != chave) return item;
        final novaQuantidade = item.quantidadeAtual + delta;
        return item.comQuantidade(
          novaQuantidade < _quantidadeMinima ? _quantidadeMinima : novaQuantidade,
        );
      }).toList(),
    );
  }

  void remover(int chave) {
    value = value.copyWith(
      itens: value.itens.where((item) => item.chave != chave).toList(),
    );
  }

  /// Payload final revisado pelo usuário — vai inteiro para
  /// `coleta_diaria.valor_jsonb` (ver comentário de cabeçalho da migration
  /// `20260730130000_coleta_diaria_eav.sql`). Inclui a confiança POR ITEM
  /// (auditoria: por que este item específico ficou com um score baixo) e
  /// os itens não reconhecidos (o que a IA viu mas o backend não conseguiu
  /// calcular) — nenhum dos dois é usado para exibição nesta tela, mas
  /// ambos valem a pena preservar no registro gravado.
  Map<String, dynamic> payloadRevisado() {
    return {
      'itens': value.itens
          .map((item) => {
                'nome': item.original.nomeCasado,
                'nome_identificado': item.original.nomeIdentificado,
                'medida': item.original.medida,
                'quantidade': item.quantidadeAtual,
                'gramas_estimados': item.gramasEstimados,
                'calorias': item.calorias,
                'proteinas_g': item.proteinasG,
                'carboidratos_g': item.carboidratosG,
                'gorduras_g': item.gordurasG,
                'confianca': item.original.confianca,
              })
          .toList(),
      'itens_nao_reconhecidos': value.itensNaoReconhecidos
          .map((item) => {
                'nome': item.nome,
                'medida': item.medida,
                'motivo': item.motivo,
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

  /// Grava a refeição em `coleta_diaria`. Retorna `true` só em sucesso —
  /// [ConfirmacaoPratoPage] usa isso para decidir se mostra o snack de
  /// sucesso e volta, ou deixa o usuário tentar de novo. Bloqueia envios
  /// concorrentes ([value.salvando]) e recusa confirmar um prato vazio
  /// (nada para gravar).
  Future<bool> confirmar() async {
    if (value.salvando || value.itens.isEmpty) return false;

    value = value.copyWith(salvando: true, limparErroSalvar: true);

    final resultado = await _repositorio.gravarRefeicao(
      payloadRevisado: payloadRevisado(),
      confianca: value.confiancaMinima,
    );

    if (!resultado.success) {
      value = value.copyWith(
        salvando: false,
        erroSalvar: resultado.errorMessage ?? 'Erro desconhecido ao salvar.',
        debugDetalheErroSalvar:
            _podeExibirDetalheTecnico ? resultado.debugDetail : null,
      );
      return false;
    }

    value = value.copyWith(salvando: false);
    return true;
  }
}
