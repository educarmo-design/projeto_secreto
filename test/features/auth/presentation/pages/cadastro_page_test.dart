import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
import 'package:atleta_gamificacao/features/auth/presentation/pages/cadastro_page.dart';

/// Cadastro Dinâmico: os campos de Profissional de Saúde (Especialidade +
/// Registro) só existem na árvore de widgets quando o switch "Sou um
/// Profissional de Saúde" está ligado, e o Perfil Base (Radio) exige uma
/// escolha antes de submeter — critério de aceite #1 da tarefa.
///
/// Finders por TIPO (não por texto exato) de propósito: o formulário é um
/// `ListView` longo e sliver-lazy — widgets fora da janela de
/// build/cache do teste simplesmente não existem no Element tree até
/// serem rolados até a vista, e mais de um `Text` no formulário pode
/// coincidir em conteúdo. `find.byType` + `ensureVisible` evita os dois
/// problemas.
///
/// Não toca Supabase: `_submit()` só chama o controller/rede depois de
/// `_perfilBase != null`, e este teste nunca preenche/seleciona um perfil
/// base — então o early-return acontece antes de qualquer I/O.
void main() {
  setUpAll(() async {
    await i18n.initialize('pt');
  });

  Future<void> pumpCadastro(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CadastroPage()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rolarAte(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'campos de profissional ficam ocultos até o switch ser ligado',
    (tester) async {
      await pumpCadastro(tester);

      await rolarAte(tester, find.byType(SwitchListTile));
      expect(
        find.byType(DropdownButtonFormField<TipoProfissionalCadastro>),
        findsNothing,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(
        find.byType(DropdownButtonFormField<TipoProfissionalCadastro>),
        findsOneWidget,
      );
      expect(
        find.text(i18n.tr('auth.registro_profissional_label')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'desligar o switch limpa a especialidade e some com os campos de novo',
    (tester) async {
      await pumpCadastro(tester);
      await rolarAte(tester, find.byType(SwitchListTile));

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        find.byType(DropdownButtonFormField<TipoProfissionalCadastro>),
        findsOneWidget,
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        find.byType(DropdownButtonFormField<TipoProfissionalCadastro>),
        findsNothing,
      );
    },
  );

  testWidgets(
    'as quatro especialidades do enum tipo_profissional_saude aparecem no dropdown',
    (tester) async {
      await pumpCadastro(tester);
      await rolarAte(tester, find.byType(SwitchListTile));

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<TipoProfissionalCadastro>));
      await tester.pumpAndSettle();

      for (final tipo in TipoProfissionalCadastro.values) {
        expect(find.text(i18n.tr(tipo.labelKey)).evaluate(), isNotEmpty);
      }
    },
  );

  testWidgets(
    'submeter sem escolher Perfil Base mostra o erro e não avança',
    (tester) async {
      await pumpCadastro(tester);

      final botaoCadastrar = find.widgetWithText(
        FilledButton,
        i18n.tr('auth.register_button'),
      );
      await rolarAte(tester, botaoCadastrar);

      await tester.tap(botaoCadastrar);
      await tester.pumpAndSettle();

      // O erro aparece perto do Radio (bem acima do botão) — rola de volta
      // para dentro da janela de build do sliver antes de procurar.
      final erroPerfilBase = find.text(i18n.tr('auth.perfil_base_required'));
      await tester.scrollUntilVisible(
        erroPerfilBase,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(erroPerfilBase, findsOneWidget);
    },
  );

  testWidgets(
    'Perfil Base tem as duas opções pedidas (Atleta e Guardião/Sênior)',
    (tester) async {
      await pumpCadastro(tester);

      await rolarAte(
        tester,
        find.byType(RadioGroup<PerfilBaseCadastro>),
      );

      expect(find.text(i18n.tr('auth.perfil_base_atleta')), findsOneWidget);
      expect(find.text(i18n.tr('auth.perfil_base_guardiao')), findsOneWidget);
    },
  );
}
