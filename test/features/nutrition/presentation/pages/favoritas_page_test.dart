import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/data/models/favorita_model.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/coleta_diaria_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/data/repositories/favoritas_repository.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/favoritas_page.dart';

class _MockFavoritasRepository extends Mock implements FavoritasRepository {}

class _MockColetaDiariaRepository extends Mock implements ColetaDiariaRepository {}

FavoritaModel _favorita({
  String id = 'fav-1',
  TipoRefeicao tipo = TipoRefeicao.almoco,
  String nome = 'Meu almoço',
  double calorias = 500,
}) {
  return FavoritaModel(
    id: id,
    tipoRefeicao: tipo,
    nome: nome,
    payloadJsonb: {
      'itens': [
        {'nome': 'Arroz'},
      ],
      'totais': {'calorias': calorias},
    },
    criadoEm: DateTime(2026, 8, 20),
  );
}

/// Payload completo — o mesmo formato que
/// `ConfirmacaoPratoController.payloadRevisado()` produz — necessário só
/// para o grupo "editar itens", que reabre a favorita em
/// `ConfirmacaoPratoPage` via `PratoRefeicaoExtracaoModel.fromJson` (parse
/// estrito, ao contrário de [_favorita] acima que basta pra `usar`/`trocar
/// tipo`/`excluir`, nunca reparseada como extração).
FavoritaModel _favoritaEditavel({String id = 'fav-1', String nome = 'Meu almoço'}) {
  return FavoritaModel(
    id: id,
    tipoRefeicao: TipoRefeicao.almoco,
    nome: nome,
    payloadJsonb: {
      'itens': [
        {
          'nome': 'Arroz branco cozido',
          'nome_identificado': 'arroz',
          'medida': 'colher de servir',
          'quantidade': 1,
          'gramas_estimados': 100,
          'calorias': 130,
          'proteinas_g': 2.5,
          'carboidratos_g': 28,
          'gorduras_g': 0.2,
          'confianca': 0.9,
        },
      ],
      'itens_nao_reconhecidos': const [],
      'totais': {
        'calorias': 130,
        'proteinas_g': 2.5,
        'carboidratos_g': 28,
        'gorduras_g': 0.2,
      },
    },
    criadoEm: DateTime(2026, 8, 20),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
    registerFallbackValue(TipoRefeicao.almoco);
  });

  late _MockFavoritasRepository favoritasRepository;
  late _MockColetaDiariaRepository coletaDiariaRepository;

  setUp(() {
    favoritasRepository = _MockFavoritasRepository();
    coletaDiariaRepository = _MockColetaDiariaRepository();
  });

  Widget criarApp() {
    return MaterialApp(
      home: FavoritasPage(
        favoritasRepository: favoritasRepository,
        coletaDiariaRepository: coletaDiariaRepository,
      ),
    );
  }

  testWidgets('carrega e mostra as favoritas', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => [_favorita()]);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Meu almoço'), findsOneWidget);
  });

  testWidgets('lista vazia mostra o empty state', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Nenhuma favorita salva ainda. Toque em + para criar uma, ou salve uma refeição como favorita na tela de confirmação.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('erro ao carregar mostra mensagem de erro', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenThrow(Exception('sem rede'));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    expect(find.text('Erro ao carregar suas favoritas.'), findsOneWidget);
  });

  testWidgets('filtrar por tipo recarrega com o filtro certo', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => [_favorita()]);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Jantar'));
    await tester.pumpAndSettle();

    verify(() => favoritasRepository.listar(tipoRefeicao: TipoRefeicao.jantar)).called(1);
  });

  testWidgets('usar favorita confirma, grava via gravarRefeicao e volta true', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => [_favorita()]);
    when(() => coletaDiariaRepository.gravarRefeicao(
          payloadRevisado: any(named: 'payloadRevisado'),
          confianca: any(named: 'confianca'),
        )).thenAnswer((_) async => const ColetaDiariaResult(success: true));

    late bool? resultado;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            resultado = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => FavoritasPage(
                  favoritasRepository: favoritasRepository,
                  coletaDiariaRepository: coletaDiariaRepository,
                ),
              ),
            );
          },
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Meu almoço'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();

    final favorita = _favorita();
    verify(() => coletaDiariaRepository.gravarRefeicao(
          payloadRevisado: favorita.payloadJsonb,
          confianca: null,
        )).called(1);
    expect(resultado, isTrue);
  });

  testWidgets('excluir pede confirmação e chama o repositório', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => [_favorita()]);
    when(() => favoritasRepository.excluir('fav-1'))
        .thenAnswer((_) async => const ColetaDiariaResult(success: true));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir').last);
    await tester.pumpAndSettle();

    verify(() => favoritasRepository.excluir('fav-1')).called(1);
  });

  testWidgets('trocar tipo chama atualizarTipo com o novo tipo escolhido', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => [_favorita()]);
    when(() => favoritasRepository.atualizarTipo('fav-1', TipoRefeicao.jantar))
        .thenAnswer((_) async => const ColetaDiariaResult(success: true));

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trocar tipo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jantar').last);
    await tester.pumpAndSettle();

    verify(() => favoritasRepository.atualizarTipo('fav-1', TipoRefeicao.jantar)).called(1);
  });

  // RELATÓRIO 20260823 — 1º gap: criar uma favorita do zero, direto na tela
  // de Favoritas (antes só existia o botão ⭐ em ConfirmacaoPratoPage).
  testWidgets('botão + abre CriarFavoritaPage e recarrega ao voltar com sucesso', (tester) async {
    when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
        .thenAnswer((_) async => []);

    await tester.pumpWidget(criarApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Criar Favorita'), findsOneWidget);

    // "Volta true" simulado: a própria página de criar dá pop(true) ao
    // salvar — aqui só confirmamos que FavoritasPage recarrega quando isso
    // acontece (a lógica de salvar em si é testada em
    // criar_favorita_page_test.dart).
    Navigator.of(tester.element(find.text('Criar Favorita'))).pop(true);
    await tester.pumpAndSettle();

    // 1 carga inicial + 1 recarga ao voltar com sucesso = 2.
    verify(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao'))).called(2);
  });

  // RELATÓRIO 20260823 — 2º gap: editar o CONTEÚDO (itens/quantidades) de
  // uma favorita já salva.
  group('editar itens', () {
    testWidgets('abre ConfirmacaoPratoPage em modo edição com os itens da favorita', (tester) async {
      when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
          .thenAnswer((_) async => [_favoritaEditavel()]);

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar itens'));
      await tester.pumpAndSettle();

      expect(find.text('Editar Favorita'), findsOneWidget);
      expect(find.text('arroz'), findsOneWidget); // nomeIdentificado do item
    });

    testWidgets('payload malformado mostra erro e não navega', (tester) async {
      when(() => favoritasRepository.listar(tipoRefeicao: any(named: 'tipoRefeicao')))
          .thenAnswer((_) async => [_favorita()]); // payload mínimo, não parseável como extração

      await tester.pumpWidget(criarApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar itens'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível abrir esta favorita para edição.'), findsOneWidget);
      expect(find.text('Editar Favorita'), findsNothing);
    });
  });
}
