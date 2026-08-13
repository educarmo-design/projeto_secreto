import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/router/ui_profile_switcher.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../auth/models/auth_models.dart' show ProfileUsageType;
import '../../../nutricao/presentation/pages/anamnese_self_service_page.dart';
import '../../../nutricao/presentation/pages/meta_bem_estar_page.dart';
import '../../../nutrition/presentation/pages/manual_food_search_page.dart';
import '../../../vinculos/presentation/pages/gerir_vinculos_page.dart';
import 'perfil_usuario_page.dart';
import 'teste_frequencia_cardiaca_page.dart';
import 'teste_peso_page.dart';
import 'teste_sono_page.dart';

/// Tela de Configurações de Perfil — PRD Mestre §1/§2/§4.
///
/// Seletor visual único: alterna instantaneamente entre "Atleta
/// Competitivo" e "Guardião Clínico / Sênior" via
/// [UiProfileSwitcher.switchProfile], que por sua vez muda o
/// `ThemeMode`/fontes do `MaterialApp`, congela a gamificação sem punição, e
/// blinda as rotas de jogo no GoRouter — tudo a partir desta única ação.
class ConfiguracoesPerfilPage extends StatefulWidget {
  const ConfiguracoesPerfilPage({super.key});

  @override
  State<ConfiguracoesPerfilPage> createState() => _ConfiguracoesPerfilPageState();
}

class _ConfiguracoesPerfilPageState extends State<ConfiguracoesPerfilPage> {
  bool _isSigningOut = false;

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.tr('profile.logout_confirm_title')),
        content: Text(i18n.tr('profile.logout_confirm_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(i18n.tr('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(i18n.tr('profile.logout')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSigningOut = true);

    try {
      await supabaseManager.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(i18n.tr('profile.logout_error')),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isSigningOut = false);
      }
    }
  }

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
                // RELATÓRIO 20260810_0006 — altura_cm alimenta o cálculo de
                // IMC em HealthSyncService._buscarAlturaMetros; sem essa
                // tela o único jeito de preencher era SQL manual.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.height),
                  title: Text(i18n.tr('profile.physical_data_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PerfilUsuarioPage()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.favorite_border),
                  title: Text(i18n.tr('profile.heart_rate_test_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TesteFrequenciaCardiacaPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.monitor_weight_outlined),
                  title: Text(i18n.tr('profile.weight_test_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TestePesoPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text(i18n.tr('profile.sleep_test_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TesteSonoPage(),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.search_outlined),
                  title: Text(i18n.tr('profile.manual_food_search_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ManualFoodSearchPage(),
                    ),
                  ),
                ),
                // N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional
                // Versionada, self-service.
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.assignment_outlined),
                  title: Text(i18n.tr('profile.anamnese_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AnamneseSelfServicePage(),
                    ),
                  ),
                ),
                // N11 (RELATÓRIO 20260812_0010) — Meta de Bem-Estar
                // self-service (Motor de Exceções N08).
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(i18n.tr('profile.meta_bem_estar_item')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MetaBemEstarPage(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(
                    i18n.tr('profile.logout'),
                    style: const TextStyle(color: Colors.red),
                  ),
                  enabled: !_isSigningOut,
                  onTap: _isSigningOut ? null : _handleLogout,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
