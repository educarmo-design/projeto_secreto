import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';

void main() {
  Map<String, dynamic> itemJson({
    String nome = 'Carne bovina, patinho, cru',
    String nomeIdentificado = 'bifinho',
    String medida = 'filé',
    num quantidade = 1,
    num gramasEstimados = 100,
    num calorias = 130,
    num proteinasG = 22,
    num carboidratosG = 0,
    num gordurasG = 4,
    num confianca = 0.9,
    String? origemCasamento,
    num? similaridade,
  }) {
    return {
      'nome': nome,
      'nome_identificado': nomeIdentificado,
      'medida': medida,
      'quantidade': quantidade,
      'gramas_estimados': gramasEstimados,
      'calorias': calorias,
      'proteinas_g': proteinasG,
      'carboidratos_g': carboidratosG,
      'gorduras_g': gordurasG,
      'confianca': confianca,
      if (origemCasamento != null) 'origem_casamento': origemCasamento,
      if (similaridade != null) 'similaridade': similaridade,
    };
  }

  Map<String, dynamic> respostaCompleta({
    List<Map<String, dynamic>>? itens,
    List<Map<String, dynamic>>? itensNaoReconhecidos,
    bool possivelFotoDeTela = false,
  }) {
    return {
      'tipo_captura': 'pratoRefeicao',
      'itens': itens ?? [itemJson()],
      'itens_nao_reconhecidos': itensNaoReconhecidos ?? [],
      'totais': {
        'calorias': 130,
        'proteinas_g': 22,
        'carboidratos_g': 0,
        'gorduras_g': 4,
      },
      'possivel_foto_de_tela': possivelFotoDeTela,
    };
  }

  test('parseia uma resposta completa e válida', () {
    final modelo = PratoRefeicaoExtracaoModel.fromJson(respostaCompleta());

    expect(modelo.itens, hasLength(1));
    final item = modelo.itens.single;
    expect(item.nomeCasado, 'Carne bovina, patinho, cru');
    expect(item.nomeIdentificado, 'bifinho');
    expect(item.medida, 'filé');
    expect(item.quantidadeOriginal, 1.0);
    expect(item.gramasEstimados, 100.0);
    expect(item.calorias, 130.0);
    expect(item.proteinasG, 22.0);
    expect(item.carboidratosG, 0.0);
    expect(item.gordurasG, 4.0);
    expect(item.confianca, 0.9);
    expect(item.origemCasamento, isNull);
    expect(item.similaridade, isNull);
    expect(modelo.itensNaoReconhecidos, isEmpty);
    expect(modelo.possivelFotoDeTela, false);
  });

  test('parseia origem_casamento e similaridade quando presentes', () {
    final modelo = PratoRefeicaoExtracaoModel.fromJson(
      respostaCompleta(
        itens: [itemJson(origemCasamento: 'semantico', similaridade: 0.71)],
      ),
    );

    expect(modelo.itens.single.origemCasamento, 'semantico');
    expect(modelo.itens.single.similaridade, 0.71);
  });

  test('parseia itens_nao_reconhecidos com nome/medida/motivo', () {
    final modelo = PratoRefeicaoExtracaoModel.fromJson(
      respostaCompleta(
        itens: [],
        itensNaoReconhecidos: [
          {'nome': 'sushi', 'medida': 'peça', 'motivo': 'alimento_nao_encontrado'},
        ],
      ),
    );

    expect(modelo.itens, isEmpty);
    expect(modelo.itensNaoReconhecidos, hasLength(1));
    expect(modelo.itensNaoReconhecidos.single.nome, 'sushi');
    expect(modelo.itensNaoReconhecidos.single.motivo, 'alimento_nao_encontrado');
  });

  test('possivel_foto_de_tela true é propagado', () {
    final modelo =
        PratoRefeicaoExtracaoModel.fromJson(respostaCompleta(possivelFotoDeTela: true));

    expect(modelo.possivelFotoDeTela, true);
  });

  test('possivel_foto_de_tela ausente ou de tipo errado nunca lança — vira false', () {
    final semCampo = Map<String, dynamic>.from(respostaCompleta())
      ..remove('possivel_foto_de_tela');
    expect(PratoRefeicaoExtracaoModel.fromJson(semCampo).possivelFotoDeTela, false);

    final tipoErrado = Map<String, dynamic>.from(respostaCompleta());
    tipoErrado['possivel_foto_de_tela'] = 'sim';
    expect(PratoRefeicaoExtracaoModel.fromJson(tipoErrado).possivelFotoDeTela, false);
  });

  test('"itens" ausente lança FormatException', () {
    final json = Map<String, dynamic>.from(respostaCompleta())..remove('itens');
    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('"itens" com tipo errado (não é lista) lança FormatException', () {
    final json = Map<String, dynamic>.from(respostaCompleta());
    json['itens'] = 'não é uma lista';
    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('"itens_nao_reconhecidos" ausente lança FormatException', () {
    final json = Map<String, dynamic>.from(respostaCompleta())
      ..remove('itens_nao_reconhecidos');
    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('item sem "calorias" lança FormatException com a classe/mensagem real', () {
    final itemSemCalorias = itemJson()..remove('calorias');
    final json = respostaCompleta(itens: [itemSemCalorias]);

    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('calorias'),
        ),
      ),
    );
  });

  test('item com "quantidade" de tipo errado lança FormatException', () {
    final itemQuantidadeErrada = itemJson();
    itemQuantidadeErrada['quantidade'] = 'dois';
    final json = respostaCompleta(itens: [itemQuantidadeErrada]);

    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('item não é um objeto JSON lança FormatException', () {
    final json = respostaCompleta();
    json['itens'] = ['isso não é um mapa'];

    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });

  test('item não reconhecido sem "motivo" lança FormatException', () {
    final json = respostaCompleta(
      itens: [],
      itensNaoReconhecidos: [
        {'nome': 'sushi', 'medida': 'peça'},
      ],
    );

    expect(
      () => PratoRefeicaoExtracaoModel.fromJson(json),
      throwsA(isA<FormatException>()),
    );
  });
}
