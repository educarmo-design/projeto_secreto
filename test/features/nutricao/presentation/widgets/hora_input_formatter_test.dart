import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/widgets/hora_input_formatter.dart';

/// RELATÓRIO 20261103_0001 (item 1) — máscara `HH:mm` + validação de
/// horário (00:00 a 23:59), compartilhada pelos 3 campos de horário da
/// Anamnese. Testes unitários diretos do formatter/validator, separados
/// dos testes de widget (que já cobrem a aplicação real nos campos).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  group('HoraInputFormatter', () {
    const formatter = HoraInputFormatter();

    TextEditingValue digitar(String textoAtual, String novoTexto) => formatter.formatEditUpdate(
          TextEditingValue(text: textoAtual),
          TextEditingValue(text: novoTexto, selection: TextSelection.collapsed(offset: novoTexto.length)),
        );

    test('insere o ":" sozinho depois dos 2 primeiros dígitos', () {
      expect(digitar('2', '22').text, '22');
      expect(digitar('22', '223').text, '22:3');
      expect(digitar('22:3', '2230').text, '22:30');
    });

    test('ignora qualquer caractere que não seja dígito', () {
      expect(digitar('', 'ab22cd30').text, '22:30');
    });

    test('nunca deixa passar de 4 dígitos (HHmm)', () {
      expect(digitar('22:30', '223059').text, '22:30');
    });

    test('cursor sempre no fim do texto formatado', () {
      final resultado = digitar('22', '223');
      expect(resultado.selection.baseOffset, resultado.text.length);
    });
  });

  group('validarHorarioOpcional', () {
    test('vazio ou nulo é válido — campo opcional', () {
      expect(validarHorarioOpcional(null), isNull);
      expect(validarHorarioOpcional(''), isNull);
      expect(validarHorarioOpcional('   '), isNull);
    });

    test('formato incompleto/inválido devolve a mensagem de formato', () {
      expect(validarHorarioOpcional('22'), 'Use o formato HH:mm (ex.: 22:30)');
      expect(validarHorarioOpcional('22h30'), 'Use o formato HH:mm (ex.: 22:30)');
    });

    test('hora ou minuto fora da faixa devolve a mensagem de intervalo', () {
      expect(validarHorarioOpcional('25:00'), 'Informe um horário válido (00:00 a 23:59)');
      expect(validarHorarioOpcional('10:70'), 'Informe um horário válido (00:00 a 23:59)');
    });

    test('horários válidos (incluindo os limites 00:00 e 23:59) não geram erro', () {
      expect(validarHorarioOpcional('00:00'), isNull);
      expect(validarHorarioOpcional('23:59'), isNull);
      expect(validarHorarioOpcional('07:05'), isNull);
    });
  });
}
