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

  /// Peso personalizado em gramas quando usuário edita (para itens estimados).
  /// Se null, usar original.gramasEstimados. Se não-nulo, usar este valor.
  final double? pesoPersonalizadoGramas;

  const ItemPratoEditavel({
    required this.chave,
    required this.original,
    required this.quantidadeAtual,
    this.pesoPersonalizadoGramas,
  });

  double get _fator => original.quantidadeOriginal == 0
      ? 0
      : quantidadeAtual / original.quantidadeOriginal;

  /// Se usuário customizou o peso, usar esse. Senão, usar o original calculado.
  double get gramasEstimados {
    if (pesoPersonalizadoGramas != null) {
      return pesoPersonalizadoGramas! * _fator;
    }
    return original.gramasEstimados * _fator;
  }

  double get calorias => (original.calorias / original.gramasEstimados) * gramasEstimados;
  double get proteinasG => (original.proteinasG / original.gramasEstimados) * gramasEstimados;
  double get carboidratosG => (original.carboidratosG / original.gramasEstimados) * gramasEstimados;
  double get gordurasG => (original.gordurasG / original.gramasEstimados) * gramasEstimados;

  ItemPratoEditavel comQuantidade(double novaQuantidade) => ItemPratoEditavel(
        chave: chave,
        original: original,
        quantidadeAtual: novaQuantidade,
        pesoPersonalizadoGramas: pesoPersonalizadoGramas,
      );

  /// Quando usuário edita o peso no aviso amarelo
  ItemPratoEditavel comPesoPersonalizado(double novoGramas) => ItemPratoEditavel(
        chave: chave,
        original: original,
        quantidadeAtual: quantidadeAtual,
        pesoPersonalizadoGramas: novoGramas,
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

  /// True quando algum item confirmado carrega uma estimativa (peso
  /// digitado/escolhido manualmente ou categorizado, nunca uma pesagem
  /// real) — RELATÓRIO 20260830_0001 (N27): o total da refeição precisa
  /// avisar visualmente quando ele inclui números que não são medição.
  bool get incluiEstimativa => itens.any((item) => item.original.quantidadeEstimada ?? false);

  ConfirmacaoPratoState copyWith({
    List<ItemPratoEditavel>? itens,
    List<ItemPratoNaoReconhecidoModel>? itensNaoReconhecidos,
    bool? salvando,
    String? erroSalvar,
    bool limparErroSalvar = false,
    String? debugDetalheErroSalvar,
  }) {
    return ConfirmacaoPratoState(
      itens: itens ?? this.itens,
      itensNaoReconhecidos: itensNaoReconhecidos ?? this.itensNaoReconhecidos,
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
    this.aoConfirmar,
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
        ) {
    // DIAGNÓSTICO 20260825_0007 (instrumentação temporária, ver relatório)
    // — este controller NÃO é um widget (é um ValueNotifier puro), não tem
    // `initState`/`build`; o construtor é o equivalente mais próximo pra
    // saber se ele chegou a ser instanciado.
    debugPrint(
      'DEBUG ConfirmacaoPratoController: construído com ${extracao.itens.length} itens',
    );
  }

  final ColetaDiariaRepository _repositorio;

  /// Próxima [ItemPratoEditavel.chave] livre — os itens iniciais usam
  /// `0..extracao.itens.length-1`; itens resolvidos manualmente (ver
  /// [resolverComMedidaCadastrada]/[resolverComPesoManual]) continuam a
  /// partir daí, nunca colidindo com uma chave existente.
  late int _proximaChave = value.itens.length;

  /// Sobrescreve o destino de [confirmar] — por padrão grava uma refeição
  /// nova em `coleta_diaria` via [ColetaDiariaRepository.gravarRefeicao].
  /// [FavoritasPage]/[ConfirmacaoPratoPage] injetam aqui uma função que
  /// chama [FavoritasRepository.atualizarPayload] no lugar, ao editar o
  /// CONTEÚDO de uma favorita já salva (RELATÓRIO 20260823) — reaproveita
  /// toda a máquina de estado (`salvando`/`erroSalvar`) sem duplicá-la.
  final Future<ColetaDiariaResult> Function(
    Map<String, dynamic> payloadRevisado,
    double? confiancaMinima,
  )? aoConfirmar;

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

  /// Quando usuário edita o peso personalizado (para itens estimados)
  void editarPeso(int chave, double novoGramas) {
    if (novoGramas <= 0) return; // Validação: peso deve ser positivo
    value = value.copyWith(
      itens: value.itens.map((item) {
        if (item.chave != chave) return item;
        return item.comPesoPersonalizado(novoGramas);
      }).toList(),
    );
  }

  /// RELATÓRIO 20260830_0001 (N27, Regra 23 — "falhar visível, nunca
  /// arbitrar"): promove um item de [ConfirmacaoPratoState.itensNaoReconhecidos]
  /// (`motivo: 'medida_nao_encontrada'`, alimento já casado pelo servidor)
  /// para a lista editável, usando uma das [ItemPratoNaoReconhecidoModel.
  /// medidasDisponiveis] — a resolução é sempre uma escolha explícita do
  /// usuário, nunca um chute do app. Marcado como estimativa (mesmo padrão
  /// amber já usado pelos outros itens estimados) porque é o usuário
  /// confirmando manualmente, não uma pesagem real. Não bloqueia o resto do
  /// prato: os outros itens continuam normalmente em [itens].
  void resolverComMedidaCadastrada(
    ItemPratoNaoReconhecidoModel item,
    MedidaCaseiraModel medidaEscolhida,
  ) =>
      _promoverItemResolvido(item, gramas: medidaEscolhida.gramas, medidaTexto: medidaEscolhida.medida);

  /// Mesma ideia de [resolverComMedidaCadastrada], mas para quando nenhuma
  /// medida cadastrada serve (ou o alimento não tem nenhuma) e o usuário
  /// digita o peso direto em gramas.
  void resolverComPesoManual(ItemPratoNaoReconhecidoModel item, double gramas) {
    if (gramas <= 0) return; // Mesma validação de editarPeso: peso deve ser positivo.
    _promoverItemResolvido(item, gramas: gramas, medidaTexto: '${gramas.toStringAsFixed(0)}g');
  }

  void _promoverItemResolvido(
    ItemPratoNaoReconhecidoModel item, {
    required double gramas,
    required String medidaTexto,
  }) {
    final caloriasKcal100g = item.caloriasKcal100g ?? 0;
    final proteinasG100g = item.proteinasG100g ?? 0;
    final carboidratosG100g = item.carboidratosG100g ?? 0;
    final gordurasG100g = item.gordurasG100g ?? 0;

    final modelo = ItemPratoExtraidoModel(
      nomeCasado: item.alimentoCasado ?? item.nome,
      nomeIdentificado: item.nome,
      medida: medidaTexto,
      quantidadeOriginal: 1,
      gramasEstimados: gramas,
      calorias: caloriasKcal100g / 100 * gramas,
      proteinasG: proteinasG100g / 100 * gramas,
      carboidratosG: carboidratosG100g / 100 * gramas,
      gordurasG: gordurasG100g / 100 * gramas,
      // `ItemPratoNaoReconhecidoModel` não carrega confiança (o wire nunca
      // mandou — nada calculado pra ter confiança de cálculo, só de
      // identificação, e essa não sobrevive à resolução manual). 1.0: o
      // PESO agora é uma escolha explícita do usuário, não um chute da IA
      // — não faz sentido este item derrubar `confiancaMinima` da refeição.
      confianca: 1.0,
      quantidadeEstimada: true,
      pesoTipicoGramas: gramas.round(),
    );

    value = value.copyWith(
      itens: [
        ...value.itens,
        ItemPratoEditavel(chave: _proximaChave++, original: modelo, quantidadeAtual: 1),
      ],
      // Identidade de objeto basta pra achar o item certo: a lista nunca é
      // reconstruída com cópias — vem direto da extração original.
      itensNaoReconhecidos: value.itensNaoReconhecidos.where((i) => i != item).toList(),
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

    final resultado = aoConfirmar != null
        ? await aoConfirmar!(payloadRevisado(), value.confiancaMinima)
        : await _repositorio.gravarRefeicao(
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
