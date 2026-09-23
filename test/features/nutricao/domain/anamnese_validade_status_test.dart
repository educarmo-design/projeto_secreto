import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/nutricao/domain/anamnese_validade_status.dart';

void main() {
  final agora = DateTime(2026, 9, 22, 12);

  test('sem data_validade (null) -> ok', () {
    final status = AnamneseValidadeStatus.calcular(null, agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.ok);
  });

  test('faltando mais de 7 dias -> ok', () {
    final status = AnamneseValidadeStatus.calcular(agora.add(const Duration(days: 8)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.ok);
  });

  test('faltando exatamente 7 dias -> lembrete', () {
    final status = AnamneseValidadeStatus.calcular(agora.add(const Duration(days: 7)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.lembrete);
    expect(status.dias, 7);
    expect(status.podeDispensar, isTrue);
  });

  test('faltando exatamente 3 dias -> lembrete', () {
    final status = AnamneseValidadeStatus.calcular(agora.add(const Duration(days: 3)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.lembrete);
    expect(status.dias, 3);
  });

  test('vence hoje (0 dias) -> lembrete', () {
    final status = AnamneseValidadeStatus.calcular(agora, agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.lembrete);
    expect(status.dias, 0);
  });

  test('vencida há 1 dia -> atrasada', () {
    final status = AnamneseValidadeStatus.calcular(agora.subtract(const Duration(days: 1)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.atrasada);
    expect(status.dias, 1);
    expect(status.podeDispensar, isTrue);
  });

  test('vencida há 10/20/30 dias (exemplos citados na tarefa) -> atrasada, sempre com o número exato', () {
    for (final dias in [10, 20, 30]) {
      final status = AnamneseValidadeStatus.calcular(agora.subtract(Duration(days: dias)), agora: agora);
      expect(status.nivel, AnamneseValidadeNivel.atrasada, reason: '$dias dias de atraso');
      expect(status.dias, dias);
    }
  });

  test('vencida há 39 dias -> ainda atrasada (não bloqueada)', () {
    final status = AnamneseValidadeStatus.calcular(agora.subtract(const Duration(days: 39)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.atrasada);
  });

  test('vencida há exatamente 40 dias -> bloqueada, NÃO dispensável', () {
    final status = AnamneseValidadeStatus.calcular(agora.subtract(const Duration(days: 40)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.bloqueada);
    expect(status.dias, 40);
    expect(status.podeDispensar, isFalse);
  });

  test('vencida há mais de 40 dias -> continua bloqueada, dias exato', () {
    final status = AnamneseValidadeStatus.calcular(agora.subtract(const Duration(days: 55)), agora: agora);
    expect(status.nivel, AnamneseValidadeNivel.bloqueada);
    expect(status.dias, 55);
  });
}
