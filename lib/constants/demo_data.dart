import 'package:atleta_gamificacao/features/gamification/models/gamification_models.dart';
import 'package:atleta_gamificacao/features/auth/models/auth_models.dart';

/// Demo/Sample data for development and testing
class DemoData {
  /// Sample user profile
  static UserProfile sampleUserProfile = UserProfile(
    id: 'demo_user_001',
    displayName: 'João Silva',
    cep: '01310-100',
    profileType: ProfileUsageType.athlete,
    isPaused: false,
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
    updatedAt: DateTime.now(),
    metadata: {
      'region': 'São Paulo',
      'state': 'SP',
      'joined_date': DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
    },
  );

  /// Sample league
  static League sampleLeague = League(
    type: LeagueType.gold,
    currentPoints: 7850,
    pointsToNextLeague: 2150,
    joinedAt: DateTime.now().subtract(const Duration(days: 15)).millisecondsSinceEpoch,
    isActive: true,
  );

  /// Sample streak
  static Streak sampleStreak = Streak(
    currentDays: 23,
    longestDays: 45,
    lastActivityDate: DateTime.now().subtract(const Duration(hours: 2)),
    isActive: true,
    bonusPoints: 140, // 2 bonus multipliers (7, 14 days)
  );

  /// Sample ranking
  static Ranking sampleRanking = Ranking(
    position: 42,
    totalPlayers: 10250,
    points: 12340,
    userId: 'demo_user_001',
    displayName: 'João Silva',
    currentLeague: LeagueType.gold,
  );

  /// Sample challenges
  static List<Challenge> sampleChallenges = [
    Challenge(
      id: 'challenge_001',
      title: 'Treinar 5km',
      description: 'Percorrer 5 quilômetros em qualquer modalidade',
      targetValue: 5000,
      currentValue: 3200,
      rewardPoints: 50,
      isCompleted: false,
      createdAt: DateTime.now(),
    ),
    Challenge(
      id: 'challenge_002',
      title: 'Fazer 50 flexões',
      description: 'Completar 50 flexões no total (podem ser divididas)',
      targetValue: 50,
      currentValue: 50,
      rewardPoints: 30,
      isCompleted: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    ),
    Challenge(
      id: 'challenge_003',
      title: 'Meditação 20min',
      description: 'Meditar ou alongar por 20 minutos',
      targetValue: 20,
      currentValue: 8,
      rewardPoints: 25,
      isCompleted: false,
      createdAt: DateTime.now(),
    ),
    Challenge(
      id: 'challenge_004',
      title: 'Beber 8 copos de água',
      description: 'Manter-se hidratado durante o dia',
      targetValue: 8,
      currentValue: 6,
      rewardPoints: 15,
      isCompleted: false,
      createdAt: DateTime.now(),
    ),
  ];

  /// Sample gamification state
  static GamificationState sampleGamificationState = GamificationState(
    totalPoints: 12340,
    currentLeague: sampleLeague,
    currentStreak: sampleStreak,
    currentRanking: sampleRanking,
    activeChallenges: sampleChallenges,
    isPaused: false,
    requiresSync: false,
  );

  /// Sample rankings for leaderboard
  static List<Ranking> sampleRankings = [
    Ranking(
      position: 1,
      totalPlayers: 10250,
      points: 28950,
      userId: 'user_001',
      displayName: 'Maria Santos',
      currentLeague: LeagueType.diamond,
    ),
    Ranking(
      position: 2,
      totalPlayers: 10250,
      points: 26340,
      userId: 'user_002',
      displayName: 'Carlos Oliveira',
      currentLeague: LeagueType.diamond,
    ),
    Ranking(
      position: 3,
      totalPlayers: 10250,
      points: 24120,
      userId: 'user_003',
      displayName: 'Ana Costa',
      currentLeague: LeagueType.platinum,
    ),
    Ranking(
      position: 42,
      totalPlayers: 10250,
      points: 12340,
      userId: 'demo_user_001',
      displayName: 'João Silva',
      currentLeague: LeagueType.gold,
    ),
    Ranking(
      position: 150,
      totalPlayers: 10250,
      points: 8920,
      userId: 'user_150',
      displayName: 'Pedro Gomes',
      currentLeague: LeagueType.silver,
    ),
  ];

  /// Sample auth states for testing
  static const AuthState initialAuthState = AuthState();

  static AuthState loadingAuthState() => AuthState.loading();

  static AuthState authenticatedState({
    required String userId,
    required ProfileUsageType profileType,
  }) =>
      AuthState.authenticated(
        userId: userId,
        profileType: profileType,
      );

  static AuthState errorAuthState(String message) =>
      AuthState.error(message);
}
