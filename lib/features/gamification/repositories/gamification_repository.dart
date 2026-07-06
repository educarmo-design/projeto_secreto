import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/gamification_models.dart';

/// Repository for managing gamification data
/// Handles offline caching and sync state
class GamificationRepository {
  static final GamificationRepository _instance =
      GamificationRepository._internal();

  factory GamificationRepository() => _instance;

  GamificationRepository._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Cache keys
  static const String _leagueKey = 'gamification_league';
  static const String _streakKey = 'gamification_streak';
  static const String _rankingKey = 'gamification_ranking';
  static const String _challengesKey = 'gamification_challenges';
  static const String _syncPendingKey = 'gamification_sync_pending';

  /// Get cached league data
  Future<League?> getCachedLeague() async {
    try {
      final json = await _secureStorage.read(key: _leagueKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        return _leagueFromJson(data);
      }
    } catch (e) {
      debugPrint('Error reading cached league: $e');
    }
    return null;
  }

  /// Cache league data
  Future<void> cacheLeague(League league) async {
    try {
      final json = jsonEncode(_leagueToJson(league));
      await _secureStorage.write(key: _leagueKey, value: json);
    } catch (e) {
      debugPrint('Error caching league: $e');
    }
  }

  /// Get cached streak data
  Future<Streak?> getCachedStreak() async {
    try {
      final json = await _secureStorage.read(key: _streakKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        return _streakFromJson(data);
      }
    } catch (e) {
      debugPrint('Error reading cached streak: $e');
    }
    return null;
  }

  /// Cache streak data
  Future<void> cacheStreak(Streak streak) async {
    try {
      final json = jsonEncode(_streakToJson(streak));
      await _secureStorage.write(key: _streakKey, value: json);
    } catch (e) {
      debugPrint('Error caching streak: $e');
    }
  }

  /// Get cached ranking
  Future<Ranking?> getCachedRanking() async {
    try {
      final json = await _secureStorage.read(key: _rankingKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        return _rankingFromJson(data);
      }
    } catch (e) {
      debugPrint('Error reading cached ranking: $e');
    }
    return null;
  }

  /// Cache ranking data
  Future<void> cacheRanking(Ranking ranking) async {
    try {
      final json = jsonEncode(_rankingToJson(ranking));
      await _secureStorage.write(key: _rankingKey, value: json);
    } catch (e) {
      debugPrint('Error caching ranking: $e');
    }
  }

  /// Get cached challenges
  Future<List<Challenge>> getCachedChallenges() async {
    try {
      final json = await _secureStorage.read(key: _challengesKey);
      if (json != null) {
        final data = jsonDecode(json) as List<dynamic>;
        return data
            .map((e) => _challengeFromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error reading cached challenges: $e');
    }
    return [];
  }

  /// Cache challenges
  Future<void> cacheChallenges(List<Challenge> challenges) async {
    try {
      final json = jsonEncode(challenges.map(_challengeToJson).toList());
      await _secureStorage.write(key: _challengesKey, value: json);
    } catch (e) {
      debugPrint('Error caching challenges: $e');
    }
  }

  /// Check if sync is pending
  Future<bool> isSyncPending() async {
    try {
      final value = await _secureStorage.read(key: _syncPendingKey);
      return value == 'true';
    } catch (e) {
      return false;
    }
  }

  /// Mark sync as pending/complete
  Future<void> setSyncPending(bool pending) async {
    try {
      await _secureStorage.write(
        key: _syncPendingKey,
        value: pending.toString(),
      );
    } catch (e) {
      debugPrint('Error setting sync pending flag: $e');
    }
  }

  /// Clear all cached gamification data
  Future<void> clearCache() async {
    try {
      await Future.wait([
        _secureStorage.delete(key: _leagueKey),
        _secureStorage.delete(key: _streakKey),
        _secureStorage.delete(key: _rankingKey),
        _secureStorage.delete(key: _challengesKey),
        _secureStorage.delete(key: _syncPendingKey),
      ]);
    } catch (e) {
      debugPrint('Error clearing gamification cache: $e');
    }
  }

  /// JSON conversion helpers
  League _leagueFromJson(Map<String, dynamic> json) {
    return League(
      type: _parseLeagueType(json['type'] as String?),
      currentPoints: (json['current_points'] as int?) ?? 0,
      pointsToNextLeague: (json['points_to_next_league'] as int?) ?? 0,
      joinedAt: (json['joined_at'] as int?) ?? 0,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> _leagueToJson(League league) {
    return {
      'type': league.type.toString(),
      'current_points': league.currentPoints,
      'points_to_next_league': league.pointsToNextLeague,
      'joined_at': league.joinedAt,
      'is_active': league.isActive,
    };
  }

  Streak _streakFromJson(Map<String, dynamic> json) {
    return Streak(
      currentDays: (json['current_days'] as int?) ?? 0,
      longestDays: (json['longest_days'] as int?) ?? 0,
      lastActivityDate: DateTime.parse(
        (json['last_activity_date'] as String?) ??
            DateTime.now().toIso8601String(),
      ),
      isActive: (json['is_active'] as bool?) ?? true,
      bonusPoints: (json['bonus_points'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> _streakToJson(Streak streak) {
    return {
      'current_days': streak.currentDays,
      'longest_days': streak.longestDays,
      'last_activity_date': streak.lastActivityDate.toIso8601String(),
      'is_active': streak.isActive,
      'bonus_points': streak.bonusPoints,
    };
  }

  Ranking _rankingFromJson(Map<String, dynamic> json) {
    return Ranking(
      position: (json['position'] as int?) ?? 0,
      totalPlayers: (json['total_players'] as int?) ?? 0,
      points: (json['points'] as int?) ?? 0,
      userId: (json['user_id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      currentLeague: _parseLeagueType(json['current_league'] as String?),
    );
  }

  Map<String, dynamic> _rankingToJson(Ranking ranking) {
    return {
      'position': ranking.position,
      'total_players': ranking.totalPlayers,
      'points': ranking.points,
      'user_id': ranking.userId,
      'display_name': ranking.displayName,
      'current_league': ranking.currentLeague.toString(),
    };
  }

  Challenge _challengeFromJson(Map<String, dynamic> json) {
    return Challenge(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      targetValue: (json['target_value'] as int?) ?? 0,
      currentValue: (json['current_value'] as int?) ?? 0,
      rewardPoints: (json['reward_points'] as int?) ?? 0,
      isCompleted: (json['is_completed'] as bool?) ?? false,
      createdAt: DateTime.parse(
        (json['created_at'] as String?) ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> _challengeToJson(Challenge challenge) {
    return {
      'id': challenge.id,
      'title': challenge.title,
      'description': challenge.description,
      'target_value': challenge.targetValue,
      'current_value': challenge.currentValue,
      'reward_points': challenge.rewardPoints,
      'is_completed': challenge.isCompleted,
      'created_at': challenge.createdAt.toIso8601String(),
    };
  }

  LeagueType _parseLeagueType(String? value) {
    if (value == null) return LeagueType.bronze;
    return LeagueType.values.firstWhere(
      (e) => e.toString() == value,
      orElse: () => LeagueType.bronze,
    );
  }
}

// Singleton instance
final gamificationRepository = GamificationRepository();
