import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/nutricao/presentation/widgets/refeicoes_habituais_widget.dart';

/// RELATÓRIO 20261103_0001 (item 1) — "Hora da refeição" em cada linha
/// passa a usar a máscara `HH:mm` + validação de horário (00:00 a 23:59).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await i18n.initialize('pt');
  });

  final formKey = GlobalKey<FormState>();

  Widget criarApp() {
    return MaterialApp(
      home: Scaffold(
        body: Form(
          key: formKey,
          child: RefeicoesHabituaisWidget(
            numeroRefeicoes: 1,
            resultadoNotifier: ValueNotifier(const []),
          ),
        ),
      ),
    );
  }

  testWidgets('digitar 4 dígitos insere o ":" sozinho no formato HH:mm', (tester) async {
    await tester.pumpWidget(criarApp());

    await tester.enterText(find.byType(TextFormField).first, '2230');
    await tester.pump();

    expect(find.text('22:30'), findsOneWidget);
  });

  testWidgets('não deixa digitar mais de 4 dígitos', (tester) async {
    await tester.pumpWidget(criarApp());

    await tester.enterText(find.byType(TextFormField).first, '223059');
    await tester.pump();

    expect(find.text('22:30'), findsOneWidget);
  });

  testWidgets('campo vazio é válido (horário é opcional)', (tester) async {
    await tester.pumpWidget(criarApp());

    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('Use o formato HH:mm (ex.: 22:30)'), findsNothing);
  });

  testWidgets('formato incompleto mostra erro de validação', (tester) async {
    await tester.pumpWidget(criarApp());

    await tester.enterText(find.byType(TextFormField).first, '22');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Use o formato HH:mm (ex.: 22:30)'), findsOneWidget);
  });

  testWidgets('horário fora da faixa (ex. 25:70) mostra erro de intervalo', (tester) async {
    await tester.pumpWidget(criarApp());

    await tester.enterText(find.byType(TextFormField).first, '2570');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    expect(find.text('Informe um horário válido (00:00 a 23:59)'), findsOneWidget);
  });

  testWidgets('horário válido (23:59) passa a validação', (tester) async {
    await tester.pumpWidget(criarApp());

    await tester.enterText(find.byType(TextFormField).first, '2359');
    expect(formKey.currentState!.validate(), isTrue);
  });
}
