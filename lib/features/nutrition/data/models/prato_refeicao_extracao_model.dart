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
    );
  }
}

/// Um item que o Gemini identificou na foto mas que o backend NÃO
/// conseguiu calcular — fora do catálogo (mesmo após busca semântica) ou
/// sem medida caseira cadastrada. Espelha `ItemPratoNaoReconhecido` do lado
/// servidor; o wire só manda nome/medida/motivo (não quantidade/confiança
/// — sem número calculado, não há o que exibir além disso).
@immutable
class ItemPratoNaoReconhecidoModel {
  final String nome;
  final String medida;

  /// `'alimento_nao_encontrado'` ou `'medida_nao_encontrada'` — ver
  /// `confirmacao_prato.motivo.*` no i18n para o texto exibido.
  final String motivo;

  const ItemPratoNaoReconhecidoModel({
    required this.nome,
    required this.medida,
    required this.motivo,
  });

  factory ItemPratoNaoReconhecidoModel.fromJson(Map<String, dynamic> json) {
    return ItemPratoNaoReconhecidoModel(
      nome: _requireString(json, 'nome'),
      medida: _requireString(json, 'medida'),
      motivo: _requireString(json, 'motivo'),
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
