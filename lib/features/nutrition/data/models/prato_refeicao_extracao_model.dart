import 'package:flutter/foundation.dart';

/// Um item do prato que o backend conseguiu casar E calcular contra
/// `alimentos_referencia` — espelha `ItemPratoCalculado` do lado servidor
/// (supabase/functions/extract-metric-photo/index.ts, `processarPratoRefeicao`).
/// Os valores nutricionais aqui já são o TOTAL para [quantidadeOriginal]
/// (não por grama/por unidade) — [ConfirmacaoPratoController] deriva o
/// valor por unidade dividindo por [quantidadeOriginal] para o recálculo
/// local dos botões [+]/[-] (regra de três simples, Parte 11.3).
@immutable
class ItemPratoExtraidoModel {
  /// Nome canônico do `alimentos_referencia` que casou (`nome` no JSON).
  final String nomeCasado;

  /// Nome exatamente como o Gemini identificou — pode divergir de
  /// [nomeCasado] (ex.: "bifinho" identificado, casado como "Carne bovina,
  /// patinho, cru"). A tela mostra os dois quando diferem.
  final String nomeIdentificado;
  final String medida;
  final double quantidadeOriginal;
  final double gramasEstimados;
  final double calorias;
  final double proteinasG;
  final double carboidratosG;
  final double gordurasG;
  final double confianca;

  /// Presente só quando o casamento veio da busca semântica (não do
  /// léxico direto) — ver `resolverComBuscaSemantica` no servidor.
  final String? origemCasamento;
  final double? similaridade;

  /// Indica se a quantidade é estimativa (alimento sem medidas cadastradas).
  /// Quando true, UI mostra ⚠️ e permite edição.
  final bool? quantidadeEstimada;

  /// Peso típico em gramas (para mostrar na UI: "Peso típico: 5g").
  /// Presente apenas quando quantidadeEstimada é true.
  final int? pesoTipicoGramas;

  /// Categoria de consumo do alimento (de `alimentos_referencia.categoria_consumo`):
  /// 'liquido_frio', 'liquido_quente', 'unidade', 'fatia', 'peso_livre'.
  /// Nulo = alimento ainda sem categorização (está em auditoria no CSV).
  final String? categoriaConsumo;

  /// Unidade padrão do alimento ('g' ou 'ml').
  final String? unidadeMedidaPadrao;

  /// Rótulo amigável da medida padrão (ex: 'Copo Pequeno', 'Unidade').
  final String? medidaPadraoNome;

  /// Quantidade numérica da medida padrão (ex: 5 para azeitona, 200 para xícara).
  final double? medidaPadraoQtd;

  const ItemPratoExtraidoModel({
    required this.nomeCasado,
    required this.nomeIdentificado,
    required this.medida,
    required this.quantidadeOriginal,
    required this.gramasEstimados,
    required this.calorias,
    required this.proteinasG,
    required this.carboidratosG,
    required this.gordurasG,
    required this.confianca,
    this.origemCasamento,
    this.similaridade,
    this.quantidadeEstimada,
    this.pesoTipicoGramas,
    this.categoriaConsumo,
    this.unidadeMedidaPadrao,
    this.medidaPadraoNome,
    this.medidaPadraoQtd,
  });

  factory ItemPratoExtraidoModel.fromJson(Map<String, dynamic> json) {
    return ItemPratoExtraidoModel(
      nomeCasado: _requireString(json, 'nome'),
      nomeIdentificado: _requireString(json, 'nome_identificado'),
      medida: _requireString(json, 'medida'),
      quantidadeOriginal: _requireNum(json, 'quantidade').toDouble(),
      gramasEstimados: _requireNum(json, 'gramas_estimados').toDouble(),
      calorias: _requireNum(json, 'calorias').toDouble(),
      proteinasG: _requireNum(json, 'proteinas_g').toDouble(),
      carboidratosG: _requireNum(json, 'carboidratos_g').toDouble(),
      gordurasG: _requireNum(json, 'gorduras_g').toDouble(),
      confianca: _requireNum(json, 'confianca').toDouble(),
      origemCasamento: json['origem_casamento'] as String?,
      similaridade: (json['similaridade'] as num?)?.toDouble(),
      quantidadeEstimada: json['quantidade_estimada'] as bool?,
      pesoTipicoGramas: (json['peso_tipico_gramas'] as num?)?.toInt(),
      categoriaConsumo: json['categoria_consumo'] as String?,
      unidadeMedidaPadrao: json['unidade_medida_padrao'] as String?,
      medidaPadraoNome: json['medida_padrao_nome'] as String?,
      medidaPadraoQtd: (json['medida_padrao_qtd'] as num?)?.toDouble(),
    );
  }
}

/// Uma medida caseira cadastrada para um alimento (espelha
/// `MedidaCaseiraCatalogo` do servidor) — usada só dentro de
/// [ItemPratoNaoReconhecidoModel.medidasDisponiveis], para o usuário
/// escolher uma medida real em vez do app arbitrar uma.
@immutable
class MedidaCaseiraModel {
  final String medida;
  final double gramas;

  const MedidaCaseiraModel({required this.medida, required this.gramas});

  factory MedidaCaseiraModel.fromJson(Map<String, dynamic> json) {
    return MedidaCaseiraModel(
      medida: _requireString(json, 'medida'),
      gramas: _requireNum(json, 'gramas').toDouble(),
    );
  }
}

/// Um item que o Gemini identificou na foto mas que o backend NÃO
/// conseguiu calcular — fora do catálogo (mesmo após busca semântica) ou
/// sem medida caseira cadastrada. Espelha `ItemPratoNaoReconhecido` do lado
/// servidor. Nunca é arbitrado (RELATÓRIO 20260830_0001, N27/Regra 23) —
/// fica visível para o usuário resolver manualmente.
@immutable
class ItemPratoNaoReconhecidoModel {
  final String nome;
  final String medida;

  /// `'alimento_nao_encontrado'`, `'medida_nao_encontrada'` ou
  /// `'quantidade_nao_informada'` (RELATÓRIO 20260901_0002 — a IA
  /// respondeu, mas com uma quantidade inválida/0, ex.: foto de "café com
  /// leite" sem contagem clara) — ver `confirmacao_prato.motivo.*` no
  /// i18n para o texto exibido.
  final String motivo;

  /// Presentes quando o alimento JÁ foi casado no servidor — `motivo ==
  /// 'medida_nao_encontrada'` (só a medida não bateu) ou `'quantidade_nao_informada'`
  /// (só a quantidade veio inválida) — então o contrato manda o suficiente
  /// pra tela resolver manualmente SEM um novo round-trip: o nome canônico
  /// casado, os macros por 100g, e as medidas que este alimento específico
  /// tem cadastradas. Ausentes quando `motivo == 'alimento_nao_encontrado'`
  /// (não há alimento casado nenhum para descrever — resolver esse caso
  /// exigiria busca manual de alimento, fora do escopo desta tarefa).
  final String? alimentoCasado;
  final double? caloriasKcal100g;
  final double? proteinasG100g;
  final double? carboidratosG100g;
  final double? gordurasG100g;
  final List<MedidaCaseiraModel>? medidasDisponiveis;

  /// RELATÓRIO 20260902_0002 — mesmos 4 campos de [ItemPratoExtraidoModel]
  /// (fix de 20260823_0004), agora também no lado "não reconhecido": sem
  /// eles, a tela de resolução manual não tinha como saber que um alimento
  /// já casado (ex.: "suco de limão" sem "copo" cadastrado) é um LÍQUIDO —
  /// pedia sempre peso em gramas, mesmo quando o item já é
  /// `categoriaConsumo == 'liquido_frio'`/`unidadeMedidaPadrao == 'ml'` de
  /// verdade. Presentes junto com [alimentoCasado] (mesma condição: o
  /// alimento já foi casado).
  final String? categoriaConsumo;
  final String? unidadeMedidaPadrao;
  final String? medidaPadraoNome;
  final double? medidaPadraoQtd;

  const ItemPratoNaoReconhecidoModel({
    required this.nome,
    required this.medida,
    required this.motivo,
    this.alimentoCasado,
    this.caloriasKcal100g,
    this.proteinasG100g,
    this.carboidratosG100g,
    this.gordurasG100g,
    this.medidasDisponiveis,
    this.categoriaConsumo,
    this.unidadeMedidaPadrao,
    this.medidaPadraoNome,
    this.medidaPadraoQtd,
  });

  factory ItemPratoNaoReconhecidoModel.fromJson(Map<String, dynamic> json) {
    final medidasBrutas = json['medidas_disponiveis'];
    return ItemPratoNaoReconhecidoModel(
      nome: _requireString(json, 'nome'),
      medida: _requireString(json, 'medida'),
      motivo: _requireString(json, 'motivo'),
      alimentoCasado: json['alimento_casado'] as String?,
      caloriasKcal100g: (json['calorias_kcal_100g'] as num?)?.toDouble(),
      proteinasG100g: (json['proteinas_g_100g'] as num?)?.toDouble(),
      carboidratosG100g: (json['carboidratos_g_100g'] as num?)?.toDouble(),
      gordurasG100g: (json['gorduras_g_100g'] as num?)?.toDouble(),
      medidasDisponiveis: medidasBrutas is List
          ? medidasBrutas.map((m) => MedidaCaseiraModel.fromJson(_requireMap(m))).toList()
          : null,
      categoriaConsumo: json['categoria_consumo'] as String?,
      unidadeMedidaPadrao: json['unidade_medida_padrao'] as String?,
      medidaPadraoNome: json['medida_padrao_nome'] as String?,
      medidaPadraoQtd: (json['medida_padrao_qtd'] as num?)?.toDouble(),
    );
  }
}

/// Resposta inteira de `extract-metric-photo` para `tipo_captura:
/// "pratoRefeicao"` (F10 Passo 3). Parsing É ESTRITO de propósito — ao
/// contrário de [HealthPayloadModel.fromAiExtraction] (que descarta campo a
/// campo porque cada leitura de aparelho é individualmente incerta), aqui
/// um item malformado indica um bug real no contrato entre cliente e
/// servidor (o servidor já fez o cálculo determinístico — não é uma
/// estimativa de IA que pode faltar um campo). Regra 0.15: nunca engolir —
/// [FormatException] sobe para quem chamou, que decide como/quando expor a
/// mensagem real ([CameraCaptureController] já tem esse tratamento pronto).
@immutable
class PratoRefeicaoExtracaoModel {
  final List<ItemPratoExtraidoModel> itens;
  final List<ItemPratoNaoReconhecidoModel> itensNaoReconhecidos;

  /// Sinal de antifraude (mesmo espírito do F10 Passo 1): true quando o
  /// Gemini suspeitou que a foto é de uma tela/outra foto, não de um prato
  /// real. Tolerante no parse (nunca lança por causa dela) — é um aviso
  /// complementar, não dado crítico para o cálculo.
  final bool possivelFotoDeTela;

  const PratoRefeicaoExtracaoModel({
    required this.itens,
    required this.itensNaoReconhecidos,
    required this.possivelFotoDeTela,
  });

  factory PratoRefeicaoExtracaoModel.fromJson(Map<String, dynamic> json) {
    final itensBrutos = json['itens'];
    if (itensBrutos is! List) {
      throw FormatException(
        'Campo "itens" ausente ou não é uma lista na resposta do prato.',
        json,
      );
    }
    final naoReconhecidosBrutos = json['itens_nao_reconhecidos'];
    if (naoReconhecidosBrutos is! List) {
      throw FormatException(
        'Campo "itens_nao_reconhecidos" ausente ou não é uma lista na resposta do prato.',
        json,
      );
    }

    return PratoRefeicaoExtracaoModel(
      itens: itensBrutos
          .map((item) => ItemPratoExtraidoModel.fromJson(_requireMap(item)))
          .toList(),
      itensNaoReconhecidos: naoReconhecidosBrutos
          .map((item) => ItemPratoNaoReconhecidoModel.fromJson(_requireMap(item)))
          .toList(),
      possivelFotoDeTela: json['possivel_foto_de_tela'] == true,
    );
  }
}

Map<String, dynamic> _requireMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Esperava um objeto JSON dentro da lista, recebeu: $value');
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Campo "$key" ausente ou não é texto.', json);
}

num _requireNum(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value;
  throw FormatException('Campo "$key" ausente ou não é número.', json);
}
