/// Consolidação de segmentos de sono em UMA noite (N43 Etapa 2, regra G.9).
///
/// O Health Connect devolve o sono como vários estágios (leve, profundo, REM,
/// acordado), cada um com início e fim. Para guardar `sono_inicio`/`sono_fim`
/// em `metricas_saude_diarias` é preciso decidir se esses estágios formam UMA
/// noite. A regra é: segmentos separados por MENOS de [janelaUniao] viram um
/// só (lacunas curtas são falha de captura do relógio, não um novo sono);
/// intervalos que se tocam ou se sobrepõem sempre se unem. A
/// janela vem de `configuracoes_sistema` (regra 16) — esta função nunca tem um
/// valor padrão próprio.
///
/// Regra 23 ("falhar visível, nunca arbitrar"): se, depois da união, sobrar
/// MAIS DE UM segmento (ex.: a noite e um cochilo que caem no mesmo
/// `data_referencia`), a noite é AMBÍGUA — esta função NÃO escolhe um deles.
/// Devolve [SonoConsolidado.segmentos] > 1 com [SonoConsolidado.inicio] e
/// [SonoConsolidado.fim] nulos, e quem grava registra a contagem para o
/// problema ficar visível no banco.
library;

/// Um intervalo cru de sono, como o Health Connect entregou.
typedef IntervaloSono = ({DateTime inicio, DateTime fim});

class SonoConsolidado {
  const SonoConsolidado({required this.segmentos, this.inicio, this.fim});

  /// Quantos segmentos restaram depois da união. 0 = nenhum intervalo.
  final int segmentos;

  /// Início do primeiro e fim do último estágio. Só preenchidos quando
  /// [segmentos] == 1; nulos se não houve dado OU se a noite é ambígua.
  final DateTime? inicio;
  final DateTime? fim;

  /// Mais de um segmento depois da união: não dá para dizer qual é "a noite".
  bool get ambiguo => segmentos > 1;
}

/// Une [intervalos] cuja distância (do fim de um ao início do próximo) seja
/// MENOR que [janelaUniao]; intervalos sobrepostos sempre se unem. Não altera
/// a lista recebida. Intervalos com fim anterior ao início são ignorados —
/// quem chama é responsável por avisar (log) que eles existiram.
SonoConsolidado consolidarSegmentosDeSono(
  List<IntervaloSono> intervalos, {
  required Duration janelaUniao,
}) {
  final validos = intervalos.where((i) => !i.fim.isBefore(i.inicio)).toList()
    ..sort((a, b) => a.inicio.compareTo(b.inicio));
  if (validos.isEmpty) return const SonoConsolidado(segmentos: 0);

  var segmentos = 1;
  final inicioGeral = validos.first.inicio;
  var fimDoSegmento = validos.first.fim;
  var fimGeral = fimDoSegmento;

  for (final intervalo in validos.skip(1)) {
    final lacuna = intervalo.inicio.difference(fimDoSegmento);
    if (lacuna <= Duration.zero || lacuna < janelaUniao) {
      if (intervalo.fim.isAfter(fimDoSegmento)) fimDoSegmento = intervalo.fim;
    } else {
      segmentos++;
      fimDoSegmento = intervalo.fim;
    }
    if (intervalo.fim.isAfter(fimGeral)) fimGeral = intervalo.fim;
  }

  if (segmentos > 1) return SonoConsolidado(segmentos: segmentos);
  return SonoConsolidado(
    segmentos: 1,
    inicio: inicioGeral,
    fim: fimGeral,
  );
}
