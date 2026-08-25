import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutrition/presentation/pages/escolher_metodo_refeicao_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  testWidgets('mostra os 4 métodos', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EscolherMetodoRefeicaoPage(onFotoPrato: () async {})),
    );
    await tester.pump();

    expect(find.text('Descrever'), findsOneWidget);
    expect(find.text('Falar'), findsOneWidget);
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Fotografar'), findsOneWidget);
  });

  testWidgets('tocar em "Descrever" abre DescreverRefeicaoPage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EscolherMetodoRefeicaoPage(onFotoPrato: () async {})),
    );
    await tester.pump();

    await tester.tap(find.text('Descrever'));
    await tester.pumpAndSettle();

    expect(find.text('Descrever Refeição'), findsOneWidget);
  });

  testWidgets('tocar em "Fotografar" chama onFotoPrato e depois fecha esta tela', (tester) async {
    var chamou = false;
    late bool? resultado;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            resultado = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => EscolherMetodoRefeicaoPage(
                  onFotoPrato: () async {
                    chamou = true;
                  },
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

    // A grade 2x2 (tiles quadrados, `GridView.count` sem `childAspectRatio`)
    // não cabe inteira na altura padrão de teste (800x600) — o tile
    // "Fotografar" (2ª linha) fica abaixo da viewport e precisa de scroll
    // antes do tap, senão o hit-test cai fora da área visível.
    await tester.ensureVisible(find.text('Fotografar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fotografar'));
    await tester.pumpAndSettle();

    expect(chamou, true);
    expect(resultado, true);
  });
}
