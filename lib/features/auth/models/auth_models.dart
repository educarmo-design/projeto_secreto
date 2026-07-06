import 'package:equatable/equatable.dart';

/// Profile usage types (Perfil de Uso)
enum ProfileUsageType { athlete, guardian, doctor }

/// User authentication state
class AuthState extends Equatable {
  final String? userId;
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final ProfileUsageType? profileType;

  const AuthState({
    this.userId,
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.profileType,
  });

  /// Create initial state
  factory AuthState.initial() => const AuthState();

  /// Create loading state
  factory AuthState.loading() => const AuthState(isLoading: true);

  /// Create authenticated state
  factory AuthState.authenticated({
    required String userId,
    required ProfileUsageType profileType,
  }) =>
      AuthState(
        userId: userId,
        isAuthenticated: true,
        profileType: profileType,
      );

  /// Create error state
  factory AuthState.error(String message) => AuthState(error: message);

  @override
  List<Object?> get props => [userId, isAuthenticated, isLoading, error, profileType];
}

/// CEP validation result
class CepValidationResult extends Equatable {
  final bool isValid;
  final String cep;
  final String? state;
  final String? city;
  final String? region;
  final String? errorMessage;

  const CepValidationResult({
    required this.isValid,
    required this.cep,
    this.state,
    this.city,
    this.region,
    this.errorMessage,
  });

  /// Create valid CEP result
  factory CepValidationResult.valid({
    required String cep,
    required String state,
    required String city,
    String? region,
  }) =>
      CepValidationResult(
        isValid: true,
        cep: cep,
        state: state,
        city: city,
        region: region,
      );

  /// Create invalid CEP result
  factory CepValidationResult.invalid({
    required String cep,
    required String errorMessage,
  }) =>
      CepValidationResult(
        isValid: false,
        cep: cep,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [isValid, cep, state, city, region, errorMessage];
}

/// User profile data stored in Supabase anonymous_users JSONB
class UserProfile extends Equatable {
  final String id;
  final String displayName;
  final String? cep;
  final ProfileUsageType profileType;
  final bool isPaused;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> metadata;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.cep,
    required this.profileType,
    this.isPaused = false,
    required this.createdAt,
    required this.updatedAt,
    this.metadata = const {},
  });

  /// Convert to JSON (for Supabase storage)
  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'cep': cep,
        'perfil_uso': _profileTypeToString(profileType),
        'is_paused': isPaused,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'metadata': metadata,
      };

  /// Create from JSON (from Supabase)
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] ?? '',
        displayName: json['display_name'] ?? 'Usuário Anônimo',
        cep: json['cep'],
        profileType: _parseProfileType(json['perfil_uso']),
        isPaused: json['is_paused'] ?? false,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      );

  /// Copy with method
  UserProfile copyWith({
    String? id,
    String? displayName,
    String? cep,
    ProfileUsageType? profileType,
    bool? isPaused,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) =>
      UserProfile(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        cep: cep ?? this.cep,
        profileType: profileType ?? this.profileType,
        isPaused: isPaused ?? this.isPaused,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        metadata: metadata ?? this.metadata,
      );

  @override
  List<Object?> get props => [
        id,
        displayName,
        cep,
        profileType,
        isPaused,
        createdAt,
        updatedAt,
        metadata,
      ];
}

/// Helper function to convert ProfileUsageType to string
String _profileTypeToString(ProfileUsageType type) {
  switch (type) {
    case ProfileUsageType.athlete:
      return 'Atleta/Gamificação';
    case ProfileUsageType.guardian:
      return 'Guardião Clínico';
    case ProfileUsageType.doctor:
      return 'Médico Especialista';
  }
}

/// Helper function to parse ProfileUsageType from string
ProfileUsageType _parseProfileType(dynamic profileUsageString) {
  if (profileUsageString is String) {
    if (profileUsageString.contains('Atleta') ||
        profileUsageString.toLowerCase().contains('athlete')) {
      return ProfileUsageType.athlete;
    } else if (profileUsageString.contains('Guardião') ||
        profileUsageString.toLowerCase().contains('guardian')) {
      return ProfileUsageType.guardian;
    } else if (profileUsageString.contains('Médico') ||
        profileUsageString.toLowerCase().contains('doctor')) {
      return ProfileUsageType.doctor;
    }
  }
  return ProfileUsageType.athlete; // Default fallback
}
