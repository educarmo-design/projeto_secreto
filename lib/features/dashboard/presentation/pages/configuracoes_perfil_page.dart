import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/router/ui_profile_switcher.dart';
import '../../../auth/models/auth_models.dart' show ProfileUsageType;
import '../../../vinculos/presentation/pages/gerir_vinculos_page.dart';

/// Tela de Configurações de Perfil — PRD Mestre §1/§2/§4.
///
/// Seletor visual único: alterna instantaneamente entre "Atleta
/// Competitivo" e "Guardião Clínico / Sênior" via
/// [UiProfileSwitcher.switchProfile], que por sua vez muda o
/// `ThemeMode`/fontes do `MaterialApp`, congela a gamificação sem punição, e
/// blinda as rotas de jogo no GoRouter — tudo a partir desta única ação.
class ConfiguracoesPerfilPage extends StatelessWidget {
  const ConfiguracoesPerfilPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('profile.title'))),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: uiProfileSwitcher,
          builder: (context, _) {
            final perfilAtual = uiProfileSwitcher.profileType;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  i18n.tr('profile.switch_profile'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  i18n.tr('profile.mode_switch_description'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                SegmentedButton<ProfileUsageType>(
                  segments: [
                    ButtonSegment(
                      value: ProfileUsageType.athlete,
                      label: Text(i18n.tr('profile.mode_athlete_label')),
                      icon: const Icon(Icons.emoji_events_outlined),
                    ),
                    ButtonSegment(
                      value: ProfileUsageType.guardian,
                      label: Text(i18n.tr('profile.mode_senior_label')),
                      icon: const Icon(Icons.favorite_outline),
                    ),
                  ],
                  selected: {perfilAtual ?? ProfileUsageType.athlete},
                  onSelectionChanged: uiProfileSwitcher.isSwitching
                      ? null
                      : (selection) =>
                          uiProfileSwitcher.switchProfile(selection.first),
                ),
                if (uiProfileSwitcher.isSwitching) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(i18n.tr('profile.switching')),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(i18n.tr('profile.manage_links_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GerirVinculosPage()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
