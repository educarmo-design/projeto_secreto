import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/pages/cadastro_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/profile_selection_page.dart';
import '../../features/dashboard/presentation/pages/main_navigation_page.dart';
import 'ui_profile_switcher.dart';

/// Route names (constants for type-safe navigation)
class RouteNames {
  static const String login = 'login';
  static const String cadastro = 'cadastro';
  static const String profileSelection = 'profile-selection';
  static const String home = 'home';
}

/// Application router with profile-aware middleware.
///
/// `redirect` is re-evaluated automatically by GoRouter on every navigation
/// attempt, AND on every event emitted by [refreshListenable]. That
/// listenable is [uiProfileSwitcher] — the same global controller
/// [MainNavigationPage] and `MaterialApp` (main.dart) already react to for
/// theme/shell switching, so a `perfil_uso` change reaches the router the
/// instant it reaches everything else, with a single realtime subscription
/// behind all three instead of three independent ones that could drift out
/// of sync.
///
/// Etapa 0.5 (faxina de roteamento): as 4 rotas abaixo são as únicas que
/// correspondem a telas reais e completas do app — `MainNavigationPage` já
/// é, sozinha, a casca inteira de navegação pós-login (troca Atleta/Sênior
/// internamente via [uiProfileSwitcher], com abas em `IndexedStack`, não
/// via rotas separadas do GoRouter). As rotas antigas para
/// leagues/rankings/exam-folder/doctor-dashboard/gamification foram
/// removidas porque nunca corresponderam a telas de fato separadas — eram
/// nomes de rota apontando para rascunhos, e as abas reais que substituem
/// cada uma delas já vivem dentro de `MainNavigationPage`.
class AppRouter {
  static final GoRouter router = GoRouter(
    routes: _buildRoutes(),
    redirect: _handleRedirect,
    refreshListenable: uiProfileSwitcher,
    initialLocation: '/${RouteNames.login}',
    errorBuilder: (context, state) => const Scaffold(
      body: Center(
        child: Text('Page not found'),
      ),
    ),
  );

  /// Build all routes
  static List<RouteBase> _buildRoutes() {
    return [
      GoRoute(
        path: '/${RouteNames.login}',
        name: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/${RouteNames.cadastro}',
        name: RouteNames.cadastro,
        builder: (context, state) => const CadastroPage(),
      ),
      GoRoute(
        path: '/${RouteNames.profileSelection}',
        name: RouteNames.profileSelection,
        builder: (context, state) => const ProfileSelectionPage(),
      ),
      GoRoute(
        path: '/${RouteNames.home}',
        name: RouteNames.home,
        builder: (context, state) => const MainNavigationPage(),
      ),
    ];
  }

  /// Redirect logic based on auth state + `perfil_uso`.
  ///
  /// Lê [uiProfileSwitcher] diretamente em vez de fazer sua própria consulta
  /// ao Supabase — [uiProfileSwitcher] já É a fonte única de verdade de
  /// `perfil_uso` (ver o doc comment da própria classe) e já é o
  /// `refreshListenable` deste router; uma segunda consulta independente
  /// aqui só correria contra a que ele já faz, podendo divergir dela. Isso
  /// substitui o `_getProfileData` antigo, que reconsultava
  /// `anonymous_users` do zero a cada navegação.
  static String? _handleRedirect(
    BuildContext context,
    GoRouterState state,
  ) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGoingToLogin = state.matchedLocation == '/${RouteNames.login}';
    final isGoingToCadastro =
        state.matchedLocation == '/${RouteNames.cadastro}';
    final isGoingToProfileSelection =
        state.matchedLocation == '/${RouteNames.profileSelection}';
    final isGoingToHome = state.matchedLocation == '/${RouteNames.home}';

    // Não autenticado — só login/cadastro são alcançáveis.
    if (user == null) {
      if (isGoingToLogin || isGoingToCadastro) return null;
      return '/${RouteNames.login}';
    }

    // Autenticado, mas ainda sem `perfil_uso` resolvido.
    if (uiProfileSwitcher.profileType == null) {
      // Ainda carregando: manda para /home, cujo MainNavigationPage já sabe
      // mostrar um spinner enquanto uiProfileSwitcher termina de carregar —
      // assim que ele terminar, `refreshListenable` reavalia este redirect
      // sozinho (sem precisar de nenhuma lógica de espera aqui).
      if (uiProfileSwitcher.isLoading) {
        return isGoingToHome ? null : '/${RouteNames.home}';
      }
      // Carregou e realmente não há perfil definido: força a escolha.
      return isGoingToProfileSelection ? null : '/${RouteNames.profileSelection}';
    }

    // Autenticado com perfil definido — sai de qualquer tela de
    // auth/onboarding, MainNavigationPage cuida do resto internamente.
    if (isGoingToLogin || isGoingToCadastro || isGoingToProfileSelection) {
      return '/${RouteNames.home}';
    }
    return null;
  }
}
