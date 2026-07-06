import 'package:equatable/equatable.dart';

/// League types with competitive tiers
enum LeagueType { bronze, silver, gold, platinum, diamond }

/// User league status
class League extends Equatable {
  final LeagueType type;
  final int currentPoints;
  final int pointsToNextLeague;
  final int joinedAt;
  final bool isActive;

  const League({
    required this.type,
    required this.currentPoints,
    required this.pointsToNextLeague,
    required this.joinedAt,
    this.isActive = true,
  });

  /// Get league display name
  String getDisplayName(String locale) {
    switch (locale) {
      case 'pt':
        switch (type) {
          case LeagueType.bronze:
            return 'Liga Bronze';
          case LeagueType.silver:
            return 'Liga Prata';
          case LeagueType.gold:
            return 'Liga Ouro';
          case LeagueType.platinum:
            return 'Liga Platina';
          case LeagueType.diamond:
            return 'Liga Diamante';
        }
      case 'en':
        switch (type) {
          case LeagueType.bronze:
            return 'Bronze League';
          case LeagueType.silver:
            return 'Silver League';
          case LeagueType.gold:
            return 'Gold League';
          case LeagueType.platinum:
            return 'Platinum League';
          case LeagueType.diamond:
            return 'Diamond League';
        }
      case 'es':
        switch (type) {
          case LeagueType.bronze:
            return 'Liga Bronce';
          case LeagueType.silver:
            return 'Liga Plata';
          case LeagueType.gold:
            return 'Liga Oro';
          case LeagueType.platinum:
            return 'Liga Platino';
          case LeagueType.diamond:
            return 'Liga Diamante';
        }
      default:
        return type.toString();
    }
  }

  /// Check if user can advance to next league
  bool canAdvance() => currentPoints >= pointsToNextLeague;

  /// Calculate progress percentage (0-100)
  double getProgressPercentage() {
    if (pointsToNextLeague == 0) return 100;
    return (currentPoints / pointsToNextLeague) * 100;
  }

  @override
  List<Object?> get props => [type, currentPoints, pointsToNextLeague, joinedAt, isActive];
}

/// User streak (fire 🔥)
class Streak extends Equatable {
  final int currentDays;
  final int longestDays;
  final DateTime lastActivityDate;
  final bool isActive;
  final int bonusPoints;

  const Streak({
    required this.currentDays,
    required this.longestDays,
    required this.lastActivityDate,
    this.isActive = true,
    this.bonusPoints = 0,
  });

  /// Check if streak is maintained (activity within last 24 hours)
  bool isMaintained() {
    final now = DateTime.now();
    final difference = now.difference(lastActivityDate).inHours;
    return difference < 24;
  }

  /// Calculate next bonus threshold (e.g., every 7 days)
  int getNextBonusThreshold() {
    const bonusInterval = 7;
    return ((currentDays ~/ bonusInterval) + 1) * bonusInterval;
  }

  @override
  List<Object?> get props => [currentDays, longestDays, lastActivityDate, isActive, bonusPoints];
}

/// Ranking information
class Ranking extends Equatable {
  final int position;
  final int totalPlayers;
  final int points;
  final String userId;
  final String displayName;
  final LeagueType currentLeague;

  const Ranking({
    required this.position,
    required this.totalPlayers,
    required this.points,
    required this.userId,
    required this.displayName,
    required this.currentLeague,
  });

  /// Get percentile rank (0-100)
  double getPercentile() {
    if (totalPlayers == 0) return 0;
    return ((totalPlayers - position) / totalPlayers) * 100;
  }

  /// Check if user is in top 10
  bool isTopTen() => position <= 10;

  /// Check if user is in top 100
  bool isTopHundred() => position <= 100;

  @override
  List<Object?> get props =>
      [position, totalPlayers, points, userId, displayName, currentLeague];
}

/// Daily challenge
class Challenge extends Equatable {
  final String id;
  final String title;
  final String description;
  final int targetValue;
  final int currentValue;
  final int rewardPoints;
  final bool isCompleted;
  final DateTime createdAt;

  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.targetValue,
    required this.currentValue,
    required this.rewardPoints,
    this.isCompleted = false,
    required this.createdAt,
  });

  /// Calculate progress percentage
  double getProgress() {
    if (targetValue == 0) return 0;
    return (currentValue / targetValue).clamp(0.0, 1.0);
  }

  /// Check if challenge can be completed
  bool canComplete() => currentValue >= targetValue;

  @override
  List<Object?> get props =>
      [id, title, description, targetValue, currentValue, rewardPoints, isCompleted, createdAt];
}

/// User gamification state (aggregated)
class GamificationState extends Equatable {
  final int totalPoints;
  final League currentLeague;
  final Streak currentStreak;
  final Ranking currentRanking;
  final List<Challenge> activeChallenges;
  final bool isPaused;
  final bool requiresSync;

  const GamificationState({
    required this.totalPoints,
    required this.currentLeague,
    required this.currentStreak,
    required this.currentRanking,
    required this.activeChallenges,
    this.isPaused = false,
    this.requiresSync = false,
  });

  /// Calculate next milestone
  int getPointsToNextMilestone(int milestoneInterval) {
    final nextMilestone = ((totalPoints ~/ milestoneInterval) + 1) * milestoneInterval;
    return nextMilestone - totalPoints;
  }

  @override
  List<Object?> get props => [
        totalPoints,
        currentLeague,
        currentStreak,
        currentRanking,
        activeChallenges,
        isPaused,
        requiresSync,
      ];
}
