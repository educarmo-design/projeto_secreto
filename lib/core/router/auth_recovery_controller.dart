import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks whether the app is currently inside a "password recovery" session
/// — the state Supabase Auth puts the client into the instant it opens the
/// deep link from a "Esqueci minha senha" e-mail
/// (`AppConfig.oauthRedirectUrl`, intercepted automatically by
/// `supabase_flutter` once `AndroidManifest.xml` hands the URI to
/// `MainActivity`). [AuthChangeEvent.passwordRecovery] is a one-shot signal,
/// not a persistent flag Supabase exposes anywhere else — this controller
/// is what turns it into state [AppRouter] can gate on.
///
/// Why this can't be inferred from `currentUser`/`currentSession` alone: a
/// recovery deep link DOES establish a real, non-null session (that's how
/// [DefinirNovaSenhaPage] is allowed to call `auth.updateUser` at all) — so
/// [AppRouter]'s normal "user != null -> home" redirect would happily send
/// someone straight into the dashboard on their OLD password, skipping the
/// screen that's the entire point of the link they just tapped, without
/// this extra bit of state to stop it.
///
/// [emRecuperacao] clears itself on [concluir] (called by
/// [DefinirNovaSenhaPage] once `updateUser` succeeds) or on a subsequent
/// normal sign-in/sign-out — never on its own, since the user must actually
/// finish setting a new password first.
class AuthRecoveryController extends ChangeNotifier {
  AuthRecoveryController({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _emRecuperacao = true;
        notifyListeners();
      } else if (state.event == AuthChangeEvent.signedOut) {
        // Sessão de recuperação encerrada sem concluir (ex.: usuário
        // deslogou manualmente) — não deixa o app preso tentando voltar
        // pra uma tela de "definir nova senha" sem sessão nenhuma.
        if (_emRecuperacao) {
          _emRecuperacao = false;
          notifyListeners();
        }
      }
    });
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;

  bool _emRecuperacao = false;
  bool get emRecuperacao => _emRecuperacao;

  /// Chamado por [DefinirNovaSenhaPage] depois que `auth.updateUser` troca
  /// a senha com sucesso — a partir daqui o redirect do [AppRouter] volta a
  /// tratar a sessão como um login normal.
  void concluir() {
    if (!_emRecuperacao) return;
    _emRecuperacao = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Singleton instance — o mesmo padrão de [uiProfileSwitcher]: uma única
/// inscrição em `onAuthStateChange` para o app inteiro (roteador e tela de
/// definir-nova-senha compartilham este estado, nunca duas independentes).
final authRecoveryController = AuthRecoveryController();
