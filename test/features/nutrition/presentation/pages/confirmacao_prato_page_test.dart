import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/dashboard/data/models/health_payload_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/favorita_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/favoritas_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/confirmacao_prato_controller.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/confirmacao_prato_page.dart';

class _MockFavoritasRepository extends Mock implements FavoritasRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  ItemPratoExtraidoModel item({
    String nomeCasado = 'Carne bovina, patinho, cru',
    String nomeIdentificado = 'bifinho',
    String medida = 'filé',
    double quantidadeOriginal = 1,
    double? gramasEstimados,
    double calorias = 130,
    double proteinasG = 22,
    double carboidratosG = 0,
    double gordurasG = 4,
    double confianca = 0.9,
    String? unidadeMedidaPadrao,
    String? categoriaConsumo,
  }) {
    return ItemPratoExtraidoModel(
      nomeCasado: nomeCasado,
      nomeIdentificado: nomeIdentificado,
      medida: medida,
      quantidadeOriginal: quantidadeOriginal,
      gramasEstimados: gramasEstimados ?? 100 * quantidadeOriginal,
      calorias: calorias,
      proteinasG: proteinasG,
      carboidratosG: carboidratosG,
      gordurasG: gordurasG,
      confianca: confianca,
      unidadeMedidaPadrao: unidadeMedidaPadrao,
      categoriaConsumo: categoriaConsumo,
    );
  }

  Future<void> pumpPagina(
    WidgetTester tester, {
    List<ItemPratoExtraidoModel>? itens,
    List<ItemPratoNaoReconhecidoModel>? itensNaoReconhecidos,
    bool possivelFotoDeTela = false,
  }) async {
    final extracao = PratoRefeicaoExtracaoModel(
      itens: itens ?? [item()],
      itensNaoReconhecidos: itensNaoReconhecidos ?? const [],
      possivelFotoDeTela: possivelFotoDeTela,
    );
    await tester.pumpWidget(
      MaterialApp(home: ConfirmacaoPratoPage(extracao: extracao)),
    );
    await tester.pump();
  }

  testWidgets('mostra nome, medida, macros e confiança do item', (tester) async {
    await pumpPagina(tester);

    // RELATÓRIO 20260821 — corrigido pra bater com a UI real: o nome
    // IDENTIFICADO pelo Gemini ("bifinho") é o título (bare, sem prefixo
    // "Identificado como:" — isso nunca existiu na implementação, só no
    // texto antigo deste teste); o nome CASADO no catálogo aparece como
    // subtítulo só quando os dois divergem (ver `original.nomeCasado !=
    // original.nomeIdentificado` em ConfirmacaoPratoPage).
    expect(find.text('bifinho'), findsOneWidget);
    expect(find.text('Carne bovina, patinho, cru'), findsOneWidget);
    expect(find.text('Confiança da leitura: 90%'), findsOneWidget);
    expect(find.text('1 filé'), findsOneWidget);
    expect(find.text('130 kcal · 22.0g prot · 0.0g carb · 4.0g gord'), findsOneWidget);
    // RELATÓRIO 20260901_0003 (achado do teste físico) — badge mostra a
    // grandeza BASE (peso calculado + g/ml), não o nome da medida caseira
    // ("filé" continua aparecendo, mas só na linha de baixo, junto da
    // quantidade — "1 filé", já coberto no assert acima).
    expect(find.text('100g'), findsOneWidget);
  });

  // RELATÓRIO 20260901_0003 — badge do card sempre mostra g/ml, nunca o
  // nome da medida caseira (achado do teste físico: o nome não dizia nada
  // sobre o peso real).
  group('badge de unidade base (g/ml) no card', () {
    testWidgets('alimento sólido (sem categoria líquida) mostra o peso em "g"', (tester) async {
      await pumpPagina(tester, itens: [item(gramasEstimados: 250)]);

      expect(find.text('250g'), findsOneWidget);
    });

    testWidgets('unidadeMedidaPadrao "ml" mostra o peso em "ml"', (tester) async {
      await pumpPagina(
        tester,
        itens: [item(gramasEstimados: 200, unidadeMedidaPadrao: 'ml')],
      );

      expect(find.text('200ml'), findsOneWidget);
    });

    testWidgets('categoriaConsumo líquido (sem unidadeMedidaPadrao) também mostra "ml"', (tester) async {
      await pumpPagina(
        tester,
        itens: [item(gramasEstimados: 150, categoriaConsumo: 'liquido_frio')],
      );

      expect(find.text('150ml'), findsOneWidget);
    });

    testWidgets('badge acompanha o peso quando a quantidade muda (+)', (tester) async {
      await pumpPagina(tester, itens: [item(gramasEstimados: 100)]);
      expect(find.text('100g'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      // passo 0,5 (RELATÓRIO 20260901_0002): 1 -> 1,5x => 150g
      expect(find.text('150g'), findsOneWidget);
    });
  });

  testWidgets('não mostra "identificado como" quando o nome casado é igual ao identificado',
      (tester) async {
    await pumpPagina(
      tester,
      itens: [item(nomeCasado: 'Arroz', nomeIdentificado: 'Arroz')],
    );

    expect(find.textContaining('Identificado como'), findsNothing);
  });

  testWidgets('tocar em [+] avança 0,5 por toque; 2 toques dobram a quantidade e os macros', (tester) async {
    await pumpPagina(tester);

    // RELATÓRIO 20260901_0002 (achado do teste físico do fundador): passo
    // passou de 1 pra 0,5 — 1 toque já é visível...
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('1.5 filé'), findsOneWidget);

    // ...e 2 toques reproduzem o "dobra" que este teste sempre verificou.
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('2 filé'), findsOneWidget);
    expect(find.text('260 kcal · 44.0g prot · 0.0g carb · 8.0g gord'), findsOneWidget);
    expect(find.text('Total: 260 kcal · 44.0g prot · 0.0g carb · 8.0g gord'), findsOneWidget);
  });

  testWidgets('tocar em [-] nunca reduz a quantidade abaixo de 0,5', (tester) async {
    await pumpPagina(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();
    expect(find.text('0.5 filé'), findsOneWidget);
    expect(find.text('65 kcal · 11.0g prot · 0.0g carb · 2.0g gord'), findsOneWidget);

    // Um segundo toque não desce mais — 0,5 é o piso (RELATÓRIO 20260901_0002).
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();
    expect(find.text('0.5 filé'), findsOneWidget);
  });

  testWidgets('remover um item tira ele da lista e atualiza o total', (tester) async {
    await pumpPagina(tester, itens: [
      item(nomeCasado: 'Arroz', calorias: 100),
      item(nomeCasado: 'Feijão', calorias: 80),
    ]);

    expect(find.text('Total: 180 kcal · 44.0g prot · 0.0g carb · 8.0g gord'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();

    expect(find.text('Arroz'), findsNothing);
    expect(find.text('Feijão'), findsOneWidget);
    expect(find.text('Total: 80 kcal · 22.0g prot · 0.0g carb · 4.0g gord'), findsOneWidget);
  });

  testWidgets('itens não reconhecidos aparecem numa seção separada, sem editor de quantidade',
      (tester) async {
    await pumpPagina(
      tester,
      itensNaoReconhecidos: const [
        ItemPratoNaoReconhecidoModel(
          nome: 'sushi',
          medida: 'peça',
          motivo: 'alimento_nao_encontrado',
        ),
      ],
    );

    expect(find.text('Não reconhecidos'), findsOneWidget);
    expect(find.text('sushi (peça)'), findsOneWidget);
    expect(find.text('Alimento não encontrado no catálogo'), findsOneWidget);
  });

  testWidgets('aviso de possível foto de tela aparece quando o backend sinaliza', (tester) async {
    await pumpPagina(tester, possivelFotoDeTela: true);

    expect(
      find.text(
        'Isto pode ser uma foto de uma tela ou de outra foto — confira os itens com atenção antes de confirmar.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sem itens (só não reconhecidos) desabilita o botão Confirmar', (tester) async {
    await pumpPagina(
      tester,
      itens: [],
      itensNaoReconhecidos: const [
        ItemPratoNaoReconhecidoModel(nome: 'sushi', medida: 'peça', motivo: 'alimento_nao_encontrado'),
      ],
    );

    final botao = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'));
    expect(botao.onPressed, isNull);
  });

  /// Monta a tela por trás de um botão "abrir" (Navigator de verdade),
  /// injetando um [ConfirmacaoPratoController] com repositório fake — nunca
  /// toca `Supabase.instance`. Devolve o `bool` que a tela popa.
  Future<bool?> pumpEConfirmar(
    WidgetTester tester, {
    required _FakeColetaDiariaRepository fake,
  }) async {
    final controller = ConfirmacaoPratoController(
      PratoRefeicaoExtracaoModel(
        itens: [item()],
        itensNaoReconhecidos: const [],
        possivelFotoDeTela: false,
      ),
      repositorio: fake,
    );

    bool? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              resultado = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  // `extracao` é ignorado quando `controller` é passado —
                  // ver ConfirmacaoPratoPage: só usado para construir um
                  // controller próprio quando nenhum é injetado.
                  builder: (_) => ConfirmacaoPratoPage(
                    extracao: const PratoRefeicaoExtracaoModel(
                      itens: [],
                      itensNaoReconhecidos: [],
                      possivelFotoDeTela: false,
                    ),
                    controller: controller,
                  ),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirmar'));
    // `pumpAndSettle()` só continua enquanto um FRAME fica agendado — um
    // `Future.delayed` parado no meio (sem nenhuma animação em andamento)
    // não conta como isso, então ele pode voltar cedo demais e deixar o
    // Timer de 900ms pendente. Por isso avançamos o relógio simulado
    // explicitamente: cobre o atraso do fake (até 200ms nestes testes) + o
    // delay de UX pós-sucesso (900ms) numa tacada só.
    await tester.pump(const Duration(milliseconds: 1200));
    if (fake.chamadas.isNotEmpty && fake.resultado.success) {
      expect(find.text('Refeição salva com sucesso!'), findsOneWidget);
    }

    // Resolve a transição de rota do pop (ou, na falha, fica parado mesmo —
    // não há mais timer pendente nesse caso) — nenhum timer sobra ao fim.
    await tester.pumpAndSettle();
    return resultado;
  }

  testWidgets('confirmar com sucesso grava, mostra snack e fecha devolvendo true', (tester) async {
    final fake = _FakeColetaDiariaRepository(resultado: const ColetaDiariaResult(success: true));

    final resultado = await pumpEConfirmar(tester, fake: fake);

    expect(fake.chamadas, hasLength(1));
    expect((fake.chamadas.single.payload['itens'] as List), hasLength(1));
    expect(resultado, true);
    expect(find.text('abrir'), findsOneWidget); // voltou pra tela anterior
  });

  testWidgets('confirmar com falha mantém a tela aberta e mostra o erro', (tester) async {
    final fake = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(
        success: false,
        errorMessage: 'Não foi possível salvar a refeição agora. Tente novamente.',
      ),
    );

    final resultado = await pumpEConfirmar(tester, fake: fake);

    expect(resultado, isNull); // nada foi popado — a tela continua aberta
    expect(find.text('abrir'), findsNothing);
    expect(
      find.text('Não foi possível salvar a refeição agora. Tente novamente.'),
      findsOneWidget,
    );
    // O item continua na lista — nada se perde numa falha de gravação.
    expect(find.text('Carne bovina, patinho, cru'), findsOneWidget);
  });

  testWidgets('confirmar com atraso de rede: botão só reabilita depois do resultado',
      (tester) async {
    final fake = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(success: true),
      atraso: const Duration(milliseconds: 50),
    );

    final resultado = await pumpEConfirmar(tester, fake: fake);

    expect(fake.chamadas, hasLength(1)); // um único envio, mesmo com rede lenta
    expect(resultado, true);
  });

  testWidgets('mostra "Salvando..." enquanto a chamada ao repositório está em voo', (tester) async {
    final fake = _FakeColetaDiariaRepository(
      resultado: const ColetaDiariaResult(success: true),
      atraso: const Duration(milliseconds: 200),
    );
    final controller = ConfirmacaoPratoController(
      PratoRefeicaoExtracaoModel(
        itens: [item()],
        itensNaoReconhecidos: const [],
        possivelFotoDeTela: false,
      ),
      repositorio: fake,
    );

    // Navigator com uma tela "abrir" por baixo — evita popar a última rota
    // (o pop de sucesso, depois do delay de 900ms, precisa de algo por
    // baixo pra revelar).
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ConfirmacaoPratoPage(
                  // `extracao` é ignorado quando `controller` é passado.
                  extracao: const PratoRefeicaoExtracaoModel(
                    itens: [],
                    itensNaoReconhecidos: [],
                    possivelFotoDeTela: false,
                  ),
                  controller: controller,
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirmar'));
    await tester.pump(); // salvando=true já é síncrono; o atraso de 200ms ainda não venceu

    expect(find.text('Salvando...'), findsOneWidget);
    expect(find.text('Confirmar'), findsNothing);

    // Avança o relógio simulado explicitamente (ver comentário em
    // `pumpEConfirmar`) para vencer o atraso do fake (200ms) + o delay
    // pós-sucesso (900ms), e só então deixa o `pumpAndSettle` limpar o
    // resto (transição de rota, snack) sem deixar nenhum timer pendente.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
  });

  // N13 (RELATÓRIO 20260821) — "marcar como favorita ao registrar".
  group('salvar como favorita', () {
    late _MockFavoritasRepository favoritasRepository;

    setUpAll(() {
      registerFallbackValue(TipoRefeicao.almoco);
    });

    setUp(() {
      favoritasRepository = _MockFavoritasRepository();
    });

    Future<void> pumpComFavoritas(WidgetTester tester) async {
      final extracao = PratoRefeicaoExtracaoModel(
        itens: [item()],
        itensNaoReconhecidos: const [],
        possivelFotoDeTela: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConfirmacaoPratoPage(
            extracao: extracao,
            favoritasRepository: favoritasRepository,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('botão de favoritar preenchido e nome válidos salva com o tipo escolhido', (tester) async {
      when(() => favoritasRepository.salvar(
            nome: any(named: 'nome'),
            tipoRefeicao: any(named: 'tipoRefeicao'),
            payloadJsonb: any(named: 'payloadJsonb'),
          )).thenAnswer((_) async => const ColetaDiariaResult(success: true));

      await pumpComFavoritas(tester);

      await tester.tap(find.byIcon(Icons.star_outline));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Meu prato favorito');
      await tester.tap(find.widgetWithText(RadioListTile<TipoRefeicao>, 'Almoço'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Salvar'));
      await tester.pumpAndSettle();

      verify(() => favoritasRepository.salvar(
            nome: 'Meu prato favorito',
            tipoRefeicao: TipoRefeicao.almoco,
            payloadJsonb: any(named: 'payloadJsonb'),
          )).called(1);
      expect(find.text('Favorita salva com sucesso'), findsOneWidget);
    });

    testWidgets('sem nome preenchido, botão Salvar do diálogo fica desabilitado', (tester) async {
      await pumpComFavoritas(tester);

      await tester.tap(find.byIcon(Icons.star_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Café da manhã'));
      await tester.pumpAndSettle();

      final botaoSalvar = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'));
      expect(botaoSalvar.onPressed, isNull);
      verifyNever(() => favoritasRepository.salvar(
            nome: any(named: 'nome'),
            tipoRefeicao: any(named: 'tipoRefeicao'),
            payloadJsonb: any(named: 'payloadJsonb'),
          ));
    });

    testWidgets('cancelar o diálogo nunca chama o repositório', (tester) async {
      await pumpComFavoritas(tester);

      await tester.tap(find.byIcon(Icons.star_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => favoritasRepository.salvar(
            nome: any(named: 'nome'),
            tipoRefeicao: any(named: 'tipoRefeicao'),
            payloadJsonb: any(named: 'payloadJsonb'),
          ));
    });
  });

  // RELATÓRIO 20260823 — 2º gap encontrado pelo fundador testando: editar
  // o CONTEÚDO (itens/quantidades) de uma favorita já salva.
  group('editar favorita (FavoritaEmEdicao)', () {
    late _MockFavoritasRepository favoritasRepository;

    setUpAll(() {
      registerFallbackValue(TipoRefeicao.almoco);
    });

    setUp(() {
      favoritasRepository = _MockFavoritasRepository();
    });

    Future<void> pumpEditando(WidgetTester tester) async {
      final extracao = PratoRefeicaoExtracaoModel(
        itens: [item()],
        itensNaoReconhecidos: const [],
        possivelFotoDeTela: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConfirmacaoPratoPage(
            extracao: extracao,
            favoritaEmEdicao: const FavoritaEmEdicao(id: 'fav-1'),
            favoritasRepository: favoritasRepository,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('título vira "Editar Favorita" e botão ⭐ some', (tester) async {
      await pumpEditando(tester);

      expect(find.text('Editar Favorita'), findsOneWidget);
      expect(find.text('Confirmar Refeição'), findsNothing);
      expect(find.byIcon(Icons.star_outline), findsNothing);
    });

    testWidgets('botão salvar diz "Salvar alterações" e chama atualizarPayload, não gravarRefeicao',
        (tester) async {
      when(() => favoritasRepository.atualizarPayload(any(), any()))
          .thenAnswer((_) async => const ColetaDiariaResult(success: true));

      await pumpEditando(tester);

      expect(find.text('Salvar alterações'), findsOneWidget);
      expect(find.text('Confirmar'), findsNothing);

      await tester.tap(find.text('Salvar alterações'));
      await tester.pump();
      // Mesmo cuidado de `pumpEConfirmar` (grupo "confirmar refeição"
      // acima): checar o SnackBar ANTES do `pumpAndSettle()` final, que
      // resolve a transição do `pop` — depois dele o `ScaffoldMessenger`
      // desta tela já não existe mais.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Favorita atualizada com sucesso!'), findsOneWidget);
      await tester.pumpAndSettle();

      verify(() => favoritasRepository.atualizarPayload('fav-1', any())).called(1);
      verifyNever(() => favoritasRepository.salvar(
            nome: any(named: 'nome'),
            tipoRefeicao: any(named: 'tipoRefeicao'),
            payloadJsonb: any(named: 'payloadJsonb'),
          ));
    });

    testWidgets('falha ao atualizar mantém a tela e mostra o erro', (tester) async {
      when(() => favoritasRepository.atualizarPayload(any(), any())).thenAnswer(
        (_) async => const ColetaDiariaResult(
          success: false,
          errorMessage: 'Não foi possível salvar as alterações agora. Tente novamente.',
        ),
      );

      await pumpEditando(tester);

      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível salvar as alterações agora. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.text('Salvar alterações'), findsOneWidget); // ainda na tela
    });
  });

  // RELATÓRIO 20260830_0001 (N27, Regra 23 — "falhar visível, nunca
  // arbitrar" + ACEITE): item não resolvido com o alimento já casado fica
  // interativo — o usuário escolhe a medida real ou digita o peso, sem
  // bloquear o resto do prato; o total avisa quando inclui estimativa.
  group('resolver item não reconhecido manualmente (N27)', () {
    const itemComAlimentoCasado = ItemPratoNaoReconhecidoModel(
      nome: 'feijaozinho',
      medida: 'xícara',
      motivo: 'medida_nao_encontrada',
      alimentoCasado: 'Feijão, carioca, cozido',
      caloriasKcal100g: 76,
      proteinasG100g: 4.8,
      carboidratosG100g: 13.6,
      gordurasG100g: 0.5,
      medidasDisponiveis: [MedidaCaseiraModel(medida: 'concha média', gramas: 80)],
    );

    testWidgets('item sem alimento casado (alimento_nao_encontrado) não mostra botão Resolver',
        (tester) async {
      await pumpPagina(
        tester,
        itensNaoReconhecidos: const [
          ItemPratoNaoReconhecidoModel(nome: 'sushi', medida: 'peça', motivo: 'alimento_nao_encontrado'),
        ],
      );

      expect(find.text('Resolver'), findsNothing);
    });

    testWidgets('item com alimento casado mostra botão Resolver', (tester) async {
      await pumpPagina(tester, itens: [], itensNaoReconhecidos: [itemComAlimentoCasado]);

      expect(find.text('Resolver'), findsOneWidget);
    });

    testWidgets('escolher uma medida cadastrada promove o item pra lista e some de "Não reconhecidos"',
        (tester) async {
      await pumpPagina(tester, itens: [], itensNaoReconhecidos: [itemComAlimentoCasado]);

      await tester.tap(find.text('Resolver'));
      await tester.pumpAndSettle();

      expect(find.text('concha média (80g)'), findsOneWidget);
      await tester.tap(find.text('concha média (80g)'));
      await tester.pumpAndSettle();

      // Item resolvido: some da seção "Não reconhecidos", aparece na lista
      // normal, e o total reflete os macros calculados (76/100 * 80 = 60.8
      // -> exibido sem casas decimais nas calorias: 61 kcal).
      expect(find.text('Não reconhecidos'), findsNothing);
      expect(find.text('feijaozinho'), findsOneWidget);
      expect(find.textContaining('Total:'), findsOneWidget);
      final totalWidget = tester.widget<Text>(find.textContaining('Total:'));
      expect(totalWidget.data, contains('61 kcal'));
    });

    testWidgets('digitar um peso manual promove o item usando o peso digitado', (tester) async {
      await pumpPagina(tester, itens: [], itensNaoReconhecidos: [itemComAlimentoCasado]);

      await tester.tap(find.text('Resolver'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '150');
      await tester.tap(find.text('Usar este peso'));
      await tester.pumpAndSettle();

      expect(find.text('Não reconhecidos'), findsNothing);
      final totalWidget = tester.widget<Text>(find.textContaining('Total:'));
      expect(totalWidget.data, contains('114')); // 76/100 * 150 = 114
    });

    testWidgets('resolver um item não bloqueia confirmar o resto do prato', (tester) async {
      await pumpPagina(
        tester,
        itens: [item(nomeCasado: 'Arroz', calorias: 100)],
        itensNaoReconhecidos: [itemComAlimentoCasado],
      );

      // Nem precisa resolver: o item não reconhecido nunca bloqueou o
      // Confirmar (só a lista `itens` vazia bloqueia) — mas o cenário do
      // ACEITE é justamente registrar o prato inteiro COM o item resolvido.
      await tester.tap(find.text('Resolver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('concha média (80g)'));
      await tester.pumpAndSettle();

      final botao = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'));
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('total mostra marca de estimativa depois de resolver manualmente', (tester) async {
      await pumpPagina(tester, itens: [], itensNaoReconhecidos: [itemComAlimentoCasado]);

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing); // nada estimado ainda

      await tester.tap(find.text('Resolver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('concha média (80g)'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}

/// Fake em memória — nunca toca `Supabase.instance`.
class _FakeColetaDiariaRepository implements ColetaDiariaRepository {
  _FakeColetaDiariaRepository({required this.resultado, this.atraso});

  final ColetaDiariaResult resultado;
  final Duration? atraso;
  final List<({Map<String, dynamic> payload, double? confianca})> chamadas = [];

  @override
  Future<ColetaDiariaResult> gravarRefeicao({
    required Map<String, dynamic> payloadRevisado,
    required double? confianca,
    DateTime? dataColeta,
  }) async {
    if (atraso != null) await Future<void>.delayed(atraso!);
    chamadas.add((payload: payloadRevisado, confianca: confianca));
    return resultado;
  }

  // N16 (RELATÓRIO 20260819) — este teste nunca exercita hidratação;
  // implementações mínimas só para satisfazer `implements
  // ColetaDiariaRepository` (interface completa, não um mock parcial).
  @override
  Future<ColetaDiariaResult> gravarAgua({
    required int mililitros,
    DateTime? dataColeta,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> buscarTotalAguaDoDia({DateTime? data}) => throw UnimplementedError();

  @override
  Future<List<HidratacaoDia>> buscarHistoricoAgua({int dias = 7}) =>
      throw UnimplementedError();

  // N15/N12 (RELATÓRIO 20260820) — mesma justificativa dos stubs acima.
  @override
  Future<ColetaDiariaResult> gravarLeituraAparelho({
    required HealthPayloadModel payload,
    required String atributo,
    DateTime? dataColeta,
  }) =>
      throw UnimplementedError();

  @override
  Future<ConsumoDia> buscarConsumoHoje() => throw UnimplementedError();
}
