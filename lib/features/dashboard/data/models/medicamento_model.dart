import 'package:flutter/material.dart';

/// A single row read from `medicamentos_usuario` — one recurring
/// prescription shown in the "Medicamentos do Dia" module.
class MedicamentoModel {
  final String id;
  final String nomeMedicamento;
  final String? dosagem;
  final TimeOfDay horario;
  final bool ativo;
  final DateTime? ultimaDoseTomadaEm;

  const MedicamentoModel({
    required this.id,
    required this.nomeMedicamento,
    this.dosagem,
    required this.horario,
    required this.ativo,
    this.ultimaDoseTomadaEm,
  });

  factory MedicamentoModel.fromJson(Map<String, dynamic> json) {
    final horarioRaw = json['horario'] as String; // "HH:mm:ss"
    final partes = horarioRaw.split(':');
    return MedicamentoModel(
      id: json['id'] as String,
      nomeMedicamento: json['nome_medicamento'] as String,
      dosagem: json['dosagem'] as String?,
      horario: TimeOfDay(
        hour: int.parse(partes[0]),
        minute: int.parse(partes[1]),
      ),
      ativo: json['ativo'] as bool? ?? true,
      ultimaDoseTomadaEm: json['ultima_dose_tomada_em'] != null
          ? DateTime.parse(json['ultima_dose_tomada_em'] as String)
          : null,
    );
  }

  /// A dose de hoje já foi confirmada quando [ultimaDoseTomadaEm] cai no
  /// dia corrente — comparação por data, não por horário exato, já que o
  /// usuário pode confirmar antes ou depois do horário previsto.
  bool get tomadaHoje {
    final ultima = ultimaDoseTomadaEm;
    if (ultima == null) return false;
    final hoje = DateTime.now();
    return ultima.year == hoje.year &&
        ultima.month == hoje.month &&
        ultima.day == hoje.day;
  }

  String get horarioFormatado =>
      '${horario.hour.toString().padLeft(2, '0')}:${horario.minute.toString().padLeft(2, '0')}';
}
