import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Route names (constants for type-safe navigation)
class RouteNames {
  static const String login = 'login';
  static const String cepValidation = 'cep-validation';
  static const String profileSelection = 'profile-selection';
  static const String athleteDashboard = 'athlete-dashboard';
  static const String gamification = 'gamification';
  static const String leagues = 'leagues';
  static const String rankings = 'rankings';
  static const String profile = 'profile';
  static const String clinicalDashboard = 'clinical-dashboard';
  static const String doctorDashboard = 'doctor-dashboard';
  static const String examFolder = 'exam-folder';
  static const String notFound = 'not-found';
}

/// Profile types
enum ProfileType { athlete, guardian, doctor, unknown }

/// Notifies GoRouter whenever the *current user's* `perfil_uso` changes,
/// on top of auth state changes. Subscribes to a Supabase Realtime channel
/// scoped to the signed-in user's own `anonymous_users` row, so a profile
/// switch (e.g. a caregiver flipping a patient to "Guardião Clínico") is
/// enforced immediately — gamification routes become unreachable without
/// requiring the user to navigate first.
class ProfileRefreshListenable extends ChangeNotifier {
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _profileChannel;

  ProfileRefreshListenable() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      _resubscribeToProfile(event.session?.user.id);
      notifyListeners();
    });
    _resubscribeToProfile(Supabase.instance.client.auth.currentUser?.id);
  }

  void _resubscribeToProfile(String? userId) {
    _profileChannel?.unsubscribe();
    _profileChannel = null;

    if (userId == null) return;

    _profileChannel = Supabase.instance.client
        .channel('public:anonymous_users:id=eq.$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'anonymous_users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) => notifyListeners(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileChannel?.unsubscribe();
    super.dispose();
  }
}

/// Application router with profile-aware middleware.
///
/// `redirect` is re-evaluated automatically by GoRouter on every navigation
/// attempt, AND on every event emitted by [refreshListenable] — which fires
/// on auth state changes and on realtime updates to the user's own
/// `perfil_uso`. This makes the profile-aware routing truly reactive rather
/// than only "reactive to taps".
class AppRouter {
  static final ProfileRefreshListenable _profileRefresh =
      ProfileRefreshListenable();

  static final GoRouter router = GoRouter(
    routes: _buildRoutes(),
    redirect: _handleRedirect,
    refreshListenable: _profileRefresh,
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
      // Auth Routes
      GoRoute(
        path: '/${RouteNames.login}',
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/${RouteNames.cepValidation}',
        name: RouteNames.cepValidation,
        builder: (context, state) => const CepValidationScreen(),
      ),
      GoRoute(
        path: '/${RouteNames.profileSelection}',
        name: RouteNames.profileSelection,
        builder: (context, state) => const ProfileSelectionScreen(),
      ),

      // Athlete Routes (Perfil 1)
      GoRoute(
        path: '/${RouteNames.athleteDashboard}',
        name: RouteNames.athleteDashboard,
        builder: (context, state) => const AthleteDashboardScreen(),
      ),
      GoRoute(
        path: '/${RouteNames.gamification}',
        name: RouteNames.gamification,
        builder: (context, state) => const GamificationScreen(),
      ),
      GoRoute(
        path: '/${RouteNames.leagues}',
        name: RouteNames.leagues,
        builder: (context, state) => const LeaguesScreen(),
      ),
      GoRoute(
        path: '/${RouteNames.rankings}',
        name: RouteNames.rankings,
        builder: (context, state) => const RankingsScreen(),
      ),

      // Guardian/Clinical Routes (Perfil 2)
      GoRoute(
        path: '/${RouteNames.clinicalDashboard}',
        name: RouteNames.clinicalDashboard,
        builder: (context, state) => const ClinicalDashboardScreen(),
      ),
      GoRoute(
        path: '/${RouteNames.examFolder}',
        name: RouteNames.examFolder,
        builder: (context, state) => const ExamFolderScreen(),
      ),

      // Doctor Routes (Perfil 3)
      GoRoute(
        path: '/${RouteNames.doctorDashboard}',
        name: RouteNames.doctorDashboard,
        builder: (context, state) => const DoctorDashboardScreen(),
      ),

      // Common Routes
      GoRoute(
        path: '/${RouteNames.profile}',
        name: RouteNames.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
    ];
  }

  /// Redirect logic based on profile_uso and auth state
  static Future<String?> _handleRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    // Check if user is authenticated
    final user = Supabase.instance.client.auth.currentUser;
    final isGoingToLogin = state.matchedLocation == '/${RouteNames.login}';
    final isGoingToCepValidation =
        state.matchedLocation == '/${RouteNames.cepValidation}';
    final isGoingToProfileSelection =
        state.matchedLocation == '/${RouteNames.profileSelection}';

    // Not authenticated - redirect to login
    if (user == null) {
      if (isGoingToLogin ||
          isGoingToCepValidation ||
          isGoingToProfileSelection) {
        return null; // Allow navigation to auth routes
      }
      return '/${RouteNames.login}';
    }

    // Authenticated but no profile selected
    final profileData = await _getProfileData(user.id);
    if (profileData == null || profileData['perfil_uso'] == null) {
      if (isGoingToCepValidation || isGoingToProfileSelection) {
        return null; // Allow navigation to setup routes
      }
      return '/${RouteNames.profileSelection}';
    }

    // Profile selected - apply profile-specific routing
    final profileType =
        _parseProfileType(profileData['perfil_uso'] as String?);

    switch (profileType) {
      case ProfileType.athlete:
        // Athlete profile: allow gamification routes
        if (isGoingToLogin ||
            isGoingToCepValidation ||
            isGoingToExamFolder(state)) {
          return '/${RouteNames.athleteDashboard}'; // Redirect away from non-athlete routes
        }
        return null; // Allow athlete routes

      case ProfileType.guardian:
        // Guardian profile: competitive/gamification routes are unreachable.
        // Gamification is paused without penalty — the user is redirected to
        // the Pasta Digital de Exames (Digital Exam Folder), not merely to a
        // generic clinical screen.
        if (isGoingToGameRoutes(state)) {
          return '/${RouteNames.examFolder}';
        }
        if (isGoingToLogin || isGoingToCepValidation) {
          return '/${RouteNames.clinicalDashboard}'; // Redirect away from auth
        }
        return null; // Allow clinical/exam-folder routes

      case ProfileType.doctor:
        // Doctor profile: show doctor dashboard
        if (isGoingToGameRoutes(state) || isGoingToExamFolder(state)) {
          return '/${RouteNames.doctorDashboard}'; // Redirect to doctor
        }
        if (isGoingToLogin || isGoingToCepValidation) {
          return '/${RouteNames.doctorDashboard}'; // Redirect away from auth
        }
        return null; // Allow doctor routes

      case ProfileType.unknown:
        return '/${RouteNames.profileSelection}'; // Force profile selection
    }
  }

  /// Check if current route is a gamification route
  static bool isGoingToGameRoutes(GoRouterState state) {
    return state.matchedLocation.contains(RouteNames.gamification) ||
        state.matchedLocation.contains(RouteNames.leagues) ||
        state.matchedLocation.contains(RouteNames.rankings);
  }

  /// Check if going to exam folder
  static bool isGoingToExamFolder(GoRouterState state) {
    return state.matchedLocation.contains(RouteNames.examFolder);
  }

  /// Get profile data from Supabase
  static Future<Map<String, dynamic>?> _getProfileData(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('anonymous_users')
          .select('profile_data')
          .eq('id', userId)
          .single();
      return response['profile_data'] as Map<String, dynamic>?;
    } on PostgrestException catch (e) {
      debugPrint('Error fetching profile data: ${e.message}');
      return null;
    }
  }

  /// Parse profile type from string
  static ProfileType _parseProfileType(String? profileUso) {
    if (profileUso == null) return ProfileType.unknown;
    if (profileUso.contains('Atleta') || profileUso.contains('Athlete')) {
      return ProfileType.athlete;
    } else if (profileUso.contains('Guardião') ||
        profileUso.contains('Guardian')) {
      return ProfileType.guardian;
    } else if (profileUso.contains('Médico') || profileUso.contains('Doctor')) {
      return ProfileType.doctor;
    }
    return ProfileType.unknown;
  }
}

// Placeholder screens (will be implemented in features)
class LoginScreen extends StatelessWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Login Screen')),
    );
  }
}

class CepValidationScreen extends StatelessWidget {
  const CepValidationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('CEP Validation Screen')),
    );
  }
}

class ProfileSelectionScreen extends StatelessWidget {
  const ProfileSelectionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Profile Selection Screen')),
    );
  }
}

class AthleteDashboardScreen extends StatelessWidget {
  const AthleteDashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Athlete Dashboard')),
    );
  }
}

class GamificationScreen extends StatelessWidget {
  const GamificationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Gamification Screen')),
    );
  }
}

class LeaguesScreen extends StatelessWidget {
  const LeaguesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Leagues Screen')),
    );
  }
}

class RankingsScreen extends StatelessWidget {
  const RankingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Rankings Screen')),
    );
  }
}

class ClinicalDashboardScreen extends StatelessWidget {
  const ClinicalDashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Clinical Dashboard')),
    );
  }
}

class ExamFolderScreen extends StatelessWidget {
  const ExamFolderScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Exam Folder Screen')),
    );
  }
}

class DoctorDashboardScreen extends StatelessWidget {
  const DoctorDashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Doctor Dashboard')),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Profile Screen')),
    );
  }
}
