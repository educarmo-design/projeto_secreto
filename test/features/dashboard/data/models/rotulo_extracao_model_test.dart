import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/dashboard/data/models/rotulo_extracao_model.dart';

void main() {
  Map<String, dynamic> respostaJson({
    String? porcaoDescricao = '30 g (2 colheres de sopa)',
    num? caloriasKcal = 120,
    num? proteinasG = 3,
    num? carboidratosG = 18,
    num? gordurasG = 2.4,
    List<String> ingredientesPrincipais = const ['Farinha de trigo', 'Açúcar'],
    bool possivelFotoDeTela = false,
  }) {
    return {
      'porcao_descricao': porcaoDescricao,
      'calorias_kcal': caloriasKcal,
      'proteinas_g': proteinasG,
      'carboidratos_g': carboidratosG,
      'gorduras_g': gordurasG,
      'ingredientes_principais': ingredientesPrincipais,
      'possivel_foto_de_tela': possivelFotoDeTela,
    };
  }

  test('fromJson: lê todos os campos de um rótulo completo', () {
    final modelo = RotuloExtracaoModel.fromJson(respostaJson());

    expect(modelo.porcaoDescricao, '30 g (2 colheres de sopa)');
    expect(modelo.caloriasKcal, 120);
    expect(modelo.proteinasG, 3);
    expect(modelo.carboidratosG, 18);
    expect(modelo.gordurasG, 2.4);
    expect(modelo.ingredientesPrincipais, ['Farinha de trigo', 'Açúcar']);
    expect(modelo.possivelFotoDeTela, false);
  });

  test('fromJson: campo numérico ausente no JSON vira null, não quebra os outros', () {
    final modelo = RotuloExtracaoModel.fromJson(respostaJson(gordurasG: null));

    expect(modelo.caloriasKcal, 120);
    expect(modelo.gordurasG, null);
  });

  group('todosMacrosPresentes (RELATÓRIO 20261016_0004, hotfix OCR de rótulos)', () {
    // Regra 23 ("falhar visível, nunca arbitrar/esconder") — este getter é
    // o que decide se o aviso "este rótulo não imprime todos os valores"
    // aparece em [CameraCaptureView] em vez de deixar o card em branco sem
    // explicação nenhuma.
    test('true quando os 4 macros vieram preenchidos', () {
      final modelo = RotuloExtracaoModel.fromJson(respostaJson());
      expect(modelo.todosMacrosPresentes, true);
    });

    test('false quando QUALQUER um dos 4 macros está ausente (comum — nem todo rótulo imprime os 4)', () {
      expect(RotuloExtracaoModel.fromJson(respostaJson(caloriasKcal: null)).todosMacrosPresentes, false);
      expect(RotuloExtracaoModel.fromJson(respostaJson(proteinasG: null)).todosMacrosPresentes, false);
      expect(RotuloExtracaoModel.fromJson(respostaJson(carboidratosG: null)).todosMacrosPresentes, false);
      expect(RotuloExtracaoModel.fromJson(respostaJson(gordurasG: null)).todosMacrosPresentes, false);
    });

    test('false quando NENHUM macro veio (só ingredientes) — o cenário relatado pelo fundador', () {
      final modelo = RotuloExtracaoModel.fromJson(
        respostaJson(caloriasKcal: null, proteinasG: null, carboidratosG: null, gordurasG: null),
      );
      expect(modelo.todosMacrosPresentes, false);
      // Ingredientes continuam intactos — a restrição explícita da tarefa
      // ("não quebre a extração de ingredientes") não foi tocada por esta
      // correção, que é só sobre os macros/aviso.
      expect(modelo.ingredientesPrincipais, ['Farinha de trigo', 'Açúcar']);
    });
  });
}
