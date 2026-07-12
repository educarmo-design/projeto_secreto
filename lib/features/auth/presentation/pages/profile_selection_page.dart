import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/router/ui_profile_switcher.dart';
import '../../models/auth_models.dart' show ProfileUsageType;

/// Seletor de `perfil_uso` de primeira visita — mostrado por
/// `AppRouter._handleRedirect` sempre que o usuário está autenticado mas
/// ainda não tem um perfil definido em `anonymous_users.profile_data`
/// (tipicamente logo após o cadastro).
///
/// Não introduz nenhuma regra de negócio nova: reaproveita
/// [UiProfileSwitcher.switchProfile] — o mesmo método já testado e
/// server-side que [ConfiguracoesPerfilPage] usa para trocar de perfil mais
/// tarde (persiste `perfil_uso`, congela/reativa a gamificação sem punição).
/// Esta tela só acrescenta o enquadramento de "primeira escolha" e, de
/// propósito, oferece as duas mesmas opções de [ConfiguracoesPerfilPage]
/// (Atleta/Guardião) — "Médico Especialista" não é uma escolha do próprio
/// usuário em nenhuma das duas telas.
class ProfileSelectionPage extends StatelessWidget {
  const ProfileSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: uiProfileSwitcher,
          builder: (context, _) {
            final isSwitching = uiProfileSwitcher.isSwitching;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      i18n.tr('auth.profile_selection'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      i18n.tr('profile.mode_switch_description'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    _ProfileChoiceCard(
                      icon: Icons.emoji_events_outlined,
                      label: i18n.tr('profile.mode_athlete_label'),
                      isBusy: isSwitching,
                      onTap: () => uiProfileSwitcher
                          .switchProfile(ProfileUsageType.athlete),
                    ),
                    const SizedBox(height: 16),
                    _ProfileChoiceCard(
                      icon: Icons.favorite_outline,
                      label: i18n.tr('profile.mode_senior_label'),
                      isBusy: isSwitching,
                      onTap: () => uiProfileSwitcher
                          .switchProfile(ProfileUsageType.guardian),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileChoiceCard extends StatelessWidget {
  const _ProfileChoiceCard({
    required this.icon,
    required this.label,
    required this.isBusy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (isBusy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
