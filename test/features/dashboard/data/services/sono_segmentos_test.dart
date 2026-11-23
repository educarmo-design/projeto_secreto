import 'package:atleta_gamificacao/features/dashboard/data/services/sono_segmentos.dart';
import 'package:flutter_test/flutter_test.dart';

/// N43 Etapa 2 (regra G.9 + regra 23) — união de segmentos de sono numa noite.
/// A janela é sempre PARÂMETRO (regra 16): estes testes variam a janela para
/// provar que a função não tem valor embutido.
void main() {
  IntervaloSono iv(int hIni, int mIni, int hFim, int mFim, {int diaIni = 8, int diaFim = 8}) => (
        inicio: DateTime(2026, 7, diaIni, hIni, mIni),
        fim: DateTime(2026, 7, diaFim, hFim, mFim),
      );

  const trinta = Duration(minutes: 30);

  test('lista vazia: 0 segmentos e nenhum instante', () {
    final r = consolidarSegmentosDeSono(const [], janelaUniao: trinta);
    expect(r.segmentos, 0);
    expect(r.inicio, isNull);
    expect(r.fim, isNull);
    expect(r.ambiguo, false);
  });

  test('um intervalo só: ele mesmo é a noite', () {
    final r = consolidarSegmentosDeSono([iv(23, 0, 7, 0, diaFim: 9)], janelaUniao: trinta);
    expect(r.segmentos, 1);
    expect(r.inicio, DateTime(2026, 7, 8, 23));
    expect(r.fim, DateTime(2026, 7, 9, 7));
  });

  test('estágios contíguos e sobrepostos viram uma noite (ordem de chegada não importa)', () {
    final r = consolidarSegmentosDeSono([
      iv(2, 0, 4, 0, diaIni: 9, diaFim: 9),
      iv(23, 0, 2, 0, diaFim: 9), // termina exatamente quando o próximo começa
      iv(3, 0, 5, 30, diaIni: 9, diaFim: 9), // sobrepõe o anterior
    ], janelaUniao: trinta);
    expect(r.segmentos, 1);
    expect(r.inicio, DateTime(2026, 7, 8, 23));
    expect(r.fim, DateTime(2026, 7, 9, 5, 30));
  });

  test('lacuna MENOR que a janela une; lacuna IGUAL ou maior separa', () {
    final lacuna10 = [iv(23, 0, 1, 0, diaFim: 9), iv(1, 10, 3, 0, diaIni: 9, diaFim: 9)];

    expect(consolidarSegmentosDeSono(lacuna10, janelaUniao: trinta).segmentos, 1);
    expect(consolidarSegmentosDeSono(lacuna10, janelaUniao: const Duration(minutes: 11)).segmentos, 1);
    expect(consolidarSegmentosDeSono(lacuna10, janelaUniao: const Duration(minutes: 10)).segmentos, 2,
        reason: '"menos de X minutos": lacuna == X já separa');
    expect(consolidarSegmentosDeSono(lacuna10, janelaUniao: const Duration(minutes: 5)).segmentos, 2);
  });

  test('janela zero só une intervalos que se tocam ou se sobrepõem', () {
    final tocando = [iv(23, 0, 1, 0, diaFim: 9), iv(1, 0, 3, 0, diaIni: 9, diaFim: 9)];
    final comLacuna = [iv(23, 0, 1, 0, diaFim: 9), iv(1, 1, 3, 0, diaIni: 9, diaFim: 9)];

    expect(consolidarSegmentosDeSono(tocando, janelaUniao: Duration.zero).segmentos, 1,
        reason: 'lacuna 0 < 0 é falso, mas sobreposição/contato também precisa unir');
    expect(consolidarSegmentosDeSono(comLacuna, janelaUniao: Duration.zero).segmentos, 2);
  });

  test('noite + cochilo no mesmo dia: AMBÍGUO, nenhum instante é escolhido (regra 23)', () {
    final r = consolidarSegmentosDeSono([
      iv(23, 0, 7, 0, diaFim: 9), // noite
      iv(13, 0, 14, 0, diaIni: 9, diaFim: 9), // cochilo à tarde
    ], janelaUniao: trinta);

    expect(r.segmentos, 2);
    expect(r.ambiguo, true);
    expect(r.inicio, isNull, reason: 'o app não arbitra qual segmento é "a noite"');
    expect(r.fim, isNull);
  });

  test('intervalo com fim antes do início é ignorado, não derruba a noite', () {
    final r = consolidarSegmentosDeSono([
      iv(23, 0, 7, 0, diaFim: 9),
      (inicio: DateTime(2026, 7, 9, 10), fim: DateTime(2026, 7, 9, 9)), // inválido
    ], janelaUniao: trinta);

    expect(r.segmentos, 1);
    expect(r.fim, DateTime(2026, 7, 9, 7));
  });

  test('não altera a lista recebida', () {
    final entrada = [iv(2, 0, 4, 0, diaIni: 9, diaFim: 9), iv(23, 0, 2, 0, diaFim: 9)];
    consolidarSegmentosDeSono(entrada, janelaUniao: trinta);
    expect(entrada.first.inicio, DateTime(2026, 7, 9, 2));
  });
}
