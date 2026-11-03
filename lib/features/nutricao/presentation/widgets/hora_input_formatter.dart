import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';

/// RELATÓRIO 20261103_0001 (item 1) — máscara `HH:mm` reaproveitada pelos
/// 3 campos de horário da Anamnese ("Hora da refeição" em cada linha de
/// [RefeicoesHabituaisWidget], "Horário habitual de dormir/acordar" em
/// `AnamneseSelfServicePage`): insere o `:` sozinho depois dos 2 primeiros
/// dígitos e nunca deixa passar de 4 dígitos (`HHmm`) — digitar além disso
/// simplesmente não entra, sem travar o campo.
class HoraInputFormatter extends TextInputFormatter {
  const HoraInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length > 4) digitos = digitos.substring(0, 4);

    final formatado = digitos.length <= 2 ? digitos : '${digitos.substring(0, 2)}:${digitos.substring(2)}';

    return TextEditingValue(
      text: formatado,
      selection: TextSelection.collapsed(offset: formatado.length),
    );
  }
}

/// Mesma máscara, como lista de [TextInputFormatter] — atalho pro uso
/// direto em `inputFormatters:` dos 3 campos.
const List<TextInputFormatter> horaInputFormatters = [HoraInputFormatter()];

/// RELATÓRIO 20261103_0001 (item 1) — "garanta a validação correta de
/// horário (00:00 às 23:59) e formato numérico". Campo OPCIONAL em todos
/// os 3 usos (anamnese não obriga nenhum deles) — `null`/vazio nunca é
/// erro, só formato incompleto/fora da faixa quando algo foi digitado.
String? validarHorarioOpcional(String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return null;

  final match = RegExp(r'^([0-9]{2}):([0-9]{2})$').firstMatch(texto);
  if (match == null) return i18n.tr('nutricao.horario_validation_formato');

  final hora = int.parse(match.group(1)!);
  final minuto = int.parse(match.group(2)!);
  if (hora > 23 || minuto > 59) return i18n.tr('nutricao.horario_validation_intervalo');

  return null;
}
