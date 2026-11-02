import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/data/models/anamnese_models.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/widgets/revisao_smartwatch_page.dart';

/// RELATÓRIO 20261101_0002 — a tarefa reportou "o leitor de dados do
/// relógio... replica a string 'duas ocorrências em três semanas' para
/// todas as atividades". Investigação completa (SQL de
/// `processar_medias_smartwatch` nas 2 versões existentes + todo o
/// pipeline Dart de parsing/exibição — `AtividadeSmartwatch.fromJson`,
/// `MediasSmartwatchResultado.fromJson`, `_RevisaoSmartwatchPageState`)
/// NÃO encontrou nenhum bug de agrupamento — tanto o SQL (`group by dow,
/// modalidade`, denominador de semanas por `dow` via `contagem_dow`)
/// quanto o Dart (cada `AtividadeSmartwatch` é um objeto distinto, lido do
/// seu próprio item de JSON) calculam/exibem `ocorrencias_totais`/
/// `semanas_do_periodo` corretamente, um valor por atividade.
///
/// Este teste prova isso com evidência: monta um resultado com 2
/// modalidades em dias DIFERENTES, com `ocorrencias`/`semanas`
/// DIFERENTES, e confirma que a tela mostra os 2 textos distintos — nunca
/// o mesmo texto repetido. Nenhuma mudança de código foi necessária para
/// este bug (ver relatório) — este teste existe para travar a ausência do
/// bug, e pegar uma regressão real se um dia for introduzida.
void main() {
  setUpAll(() async {
    await i18n.initialize('pt');
  });

  const catalogo = [
    TipoAtividadeItem(id: 30, nomeExibicao: 'Corrida', nomeCodigo: 'RUNNING'),
    TipoAtividadeItem(id: 42, nomeExibicao: 'Natação', nomeCodigo: 'SWIMMING'),
  ];

  testWidgets('cada atividade mostra sua PRÓPRIA contagem de ocorrências/semanas, nunca a mesma string repetida',
      (tester) async {
    const resultado = MediasSmartwatchResultado(
      metricas: {},
      atividadesPorDiaSemana: {
        0: [],
        1: [
          AtividadeSmartwatch(
            modalidadeCodigo: 'RUNNING',
            diaSemana: 1,
            ocorrenciasTotais: 2,
            duracaoTotalMinutos: 90,
            semanasDoPeriodo: 3,
            mediaDuracaoMinutosPorSemana: 30,
            duracaoMediaPorSessaoMinutos: 45,
          ),
        ],
        2: [],
        3: [
          AtividadeSmartwatch(
            modalidadeCodigo: 'SWIMMING',
            diaSemana: 3,
            ocorrenciasTotais: 5,
            duracaoTotalMinutos: 150,
            semanasDoPeriodo: 4,
            mediaDuracaoMinutosPorSemana: 37.5,
            duracaoMediaPorSessaoMinutos: 30,
          ),
        ],
        4: [],
        5: [],
        6: [],
      },
      duracaoMediaPorSessaoDia: {0: null, 1: 45, 2: null, 3: 30, 4: null, 5: null, 6: null},
      cargaAtleta: CargaAtletaSmartwatch(horasTotaisPeriodo: 4, semanasNoPeriodo: 4, mediaSemanalHoras: 1),
    );

    // A tela é um ListView relativamente longo (Sono + Carga de Treino +
    // Atividades) — no viewport padrão de teste (800×600) os itens de
    // atividade ficam além do `cacheExtent` do Sliver e nem chegam a ser
    // montados (mesmo gotcha já documentado em
    // `anamnese_self_service_page_test.dart`).
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: RevisaoSmartwatchPage(
          resultado: resultado,
          catalogoAtividades: catalogo,
          atividadesJaAdicionadas: [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Segunda · Corrida'), findsOneWidget);
    expect(find.text('Quarta · Natação'), findsOneWidget);
    // Corrida (segunda): 2 ocorrências em 3 semanas.
    expect(find.text('2 ocorrência(s) em 3 semana(s) do período.'), findsOneWidget);
    // Natação (quarta): 5 ocorrências em 4 semanas — valores DIFERENTES,
    // não a string da Corrida repetida.
    expect(find.text('5 ocorrência(s) em 4 semana(s) do período.'), findsOneWidget);
  });
}
