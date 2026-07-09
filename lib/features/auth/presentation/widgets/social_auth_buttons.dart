import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';

/// "Ou cadastre-se com" / "Ou entre com" divider + native-styled Google and
/// Apple buttons — shared by [CadastroPage] and [LoginPage] so both screens
/// present the exact same Login Unificado, and so the OAuth wiring
/// ([CadastroController.autenticarComProvedorSocial]) has a single call
/// site shape to target.
///
/// There's no bundled Google "G" glyph in Flutter's Material icon font
/// (Google's brand guidelines require their own asset, which this project
/// has no image asset pipeline for yet) — [_GoogleGlyph] draws a plain
/// monogram instead of a placeholder icon that could be mistaken for the
/// real logo.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    super.key,
    required this.dividerLabelKey,
    required this.googleLabelKey,
    required this.appleLabelKey,
    required this.onProviderSelected,
    this.loadingProvider,
  });

  final String dividerLabelKey;
  final String googleLabelKey;
  final String appleLabelKey;
  final ValueChanged<OAuthProvider> onProviderSelected;

  /// Non-null while a specific provider's browser round trip is in flight —
  /// disables both buttons and shows a spinner only on the active one, so
  /// the user can't fire a second OAuth flow on top of the first.
  final OAuthProvider? loadingProvider;

  @override
  Widget build(BuildContext context) {
    final isBusy = loadingProvider != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                i18n.tr(dividerLabelKey),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed:
              isBusy ? null : () => onProviderSelected(OAuthProvider.google),
          icon: loadingProvider == OAuthProvider.google
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const _GoogleGlyph(),
          label: Text(i18n.tr(googleLabelKey)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed:
              isBusy ? null : () => onProviderSelected(OAuthProvider.apple),
          icon: loadingProvider == OAuthProvider.apple
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.apple, size: 20),
          label: Text(i18n.tr(appleLabelKey)),
        ),
      ],
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
