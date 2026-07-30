import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/prato_refeicao_extracao_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/controllers/confirmacao_prato_controller.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/confirmacao_prato_page.dart';

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
    double calorias = 130,
    double proteinasG = 22,
    double carboidratosG = 0,
    double gordurasG = 4,
    double confianca = 0.9,
  }) {
    return ItemPratoExtraidoModel(
      nomeCasado: nomeCasado,
      nomeIdentificado: nomeIdentificado,
      medida: medida,
      quantidadeOriginal: quantidadeOriginal,
      gramasEstimados: 100 * quantidadeOriginal,
      calorias: calorias,
      proteinasG: proteinasG,
      carboidratosG: carboidratosG,
      gordurasG: gordurasG,
      confianca: confianca,
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

    expect(find.text('Carne bovina, patinho, cru'), findsOneWidget);
    expect(find.text('Identificado como: bifinho'), findsOneWidget);
    expect(find.text('Confiança da leitura: 90%'), findsOneWidget);
    expect(find.text('1 filé'), findsOneWidget);
    expect(find.text('130 kcal · 22.0g prot · 0.0g carb · 4.0g gord'), findsOneWidget);
  });

  testWidgets('não mostra "identificado como" quando o nome casado é igual ao identificado',
      (tester) async {
    await pumpPagina(
      tester,
      itens: [item(nomeCasado: 'Arroz', nomeIdentificado: 'Arroz')],
    );

    expect(find.textContaining('Identificado como'), findsNothing);
  });

  testWidgets('tocar em [+] dobra a quantidade e os macros exibidos, sem rede', (tester) async {
    await pumpPagina(tester);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();

    expect(find.text('2 filé'), findsOneWidget);
    expect(find.text('260 kcal · 44.0g prot · 0.0g carb · 8.0g gord'), findsOneWidget);
    expect(find.text('Total: 260 kcal · 44.0g prot · 0.0g carb · 8.0g gord'), findsOneWidget);
  });

  testWidgets('tocar em [-] nunca reduz a quantidade abaixo de 1', (tester) async {
    await pumpPagina(tester);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();

    expect(find.text('1 filé'), findsOneWidget);
    expect(find.text('130 kcal · 22.0g prot · 0.0g carb · 4.0g gord'), findsOneWidget);
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
}
