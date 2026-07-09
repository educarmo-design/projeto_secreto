import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/models/auth_models.dart' show ProfileUsageType;
import '../theme/senior_theme.dart' show seniorFontScaleFactor;

/// Global, reactive controller for the `perfil_uso` tag — PRD Mestre §1/§2/§4.
///
/// This is the single source of truth every other layer reacts to:
/// - [MainNavigationPage] swaps its whole shell (Atleta competitivo vs.
///   Guardião Clínico/Sênior) off of [profileType].
/// - `AtletaGamificacaoApp` (main.dart) listens to this same instance to
///   flip `MaterialApp.themeMode`/font scale instantaneously.
/// - `AppRouter` uses this instance as its `refreshListenable`, so a
///   `perfil_uso` change re-runs the redirect guard immediately and blinda
///   (shields) gamification routes without waiting for the user to
///   navigate.
///
/// There used to be two independent classes doing this (a `ProfileNotifier`
/// reading `perfil_uso` and a separate `ProfileRefreshListenable` driving
/// GoRouter) — two realtime subscriptions to the same row, with no
/// guarantee they'd ever agree. They're consolidated here on purpose: one
/// subscription, one value, three listeners.
///
/// Perfil <-> tag mapping (the app's [ProfileUsageType] enum already covers
/// exactly the three tags this switcher manages):
/// - `Atleta`     -> [ProfileUsageType.athlete]  — layout competitivo.
/// - `Senior`     -> [ProfileUsageType.guardian] — Guardião Clínico/Sênior;
///   tema acessível, Pasta Digital de Exames, jogo travado.
/// - `Assincrono` -> [ProfileUsageType.doctor]   — profissional que revisa
///   dados do paciente de forma assíncrona (não joga, não é Sênior).
class UiProfileSwitcher extends ChangeNotifier {
  UiProfileSwitcher({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _authSubscription = _client.auth.onAuthStateChange.listen((event) {
      _resubscribe(event.session?.user.id);
    });
    _resubscribe(_client.auth.currentUser?.id);
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _profileChannel;

  ProfileUsageType? _profileType;
  bool _isLoading = false;
  bool _isSwitching = false;

  ProfileUsageType? get profileType => _profileType;
  bool get isLoading => _isLoading;

  /// `true` enquanto [switchProfile] está em voo — usado por
  /// [ConfiguracoesPerfilPage] para desabilitar o seletor durante a troca.
  bool get isSwitching => _isSwitching;

  bool get isSenior => _profileType == ProfileUsageType.guardian;
  bool get isAtleta => _profileType == ProfileUsageType.athlete;
  bool get isAssincrono => _profileType == ProfileUsageType.doctor;

  /// Requisito (1): tema/fontes do MaterialApp mudam instantaneamente.
  ThemeMode get themeMode => isSenior ? ThemeMode.light : ThemeMode.dark;

  /// Fator de escala de fonte do perfil ativo — mesmo valor já embutido no
  /// `TextTheme` de [getSeniorTheme]. Exposto aqui só para telas que
  /// precisem do número bruto (fora de uma árvore de `Theme`).
  double get fontScaleFactor => isSenior ? seniorFontScaleFactor : 1.0;

  Future<void> _resubscribe(String? userId) async {
    _profileChannel?.unsubscribe();
    _profileChannel = null;

    if (userId == null) {
      _profileType = null;
      notifyListeners();
      return;
    }

    await _loadProfile(userId);

    _profileChannel = _client
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
          callback: (payload) {
            final profileData =
                payload.newRecord['profile_data'] as Map<String, dynamic>?;
            _applyProfileData(profileData);
          },
        )
        .subscribe();
  }

  Future<void> _loadProfile(String userId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client
          .from('anonymous_users')
          .select('profile_data')
          .eq('id', userId)
          .maybeSingle();
      _applyProfileData(response?['profile_data'] as Map<String, dynamic>?);
    } on PostgrestException catch (e) {
      debugPrint('Erro ao carregar perfil_uso: ${e.message}');
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyProfileData(Map<String, dynamic>? profileData) {
    _isLoading = false;
    final raw = profileData?['perfil_uso'] as String?;
    _profileType = _parseProfileType(raw);
    notifyListeners();
  }

  /// Troca `perfil_uso` na tela de Configurações. Executa, nesta ordem:
  ///
  /// 1. Persiste o novo perfil em `anonymous_users.profile_data` (merge —
  ///    nunca sobrescreve outras chaves do JSONB).
  /// 2. Congela (Guardião/Sênior/Assíncrono) ou reativa (Atleta) a
  ///    gamificação em `progresso_gamificacao`, sem punição — Modo
  ///    Recuperação Humano implícito, mesmo vocabulário já usado por
  ///    `EsteiraTrialController` para o congelamento local do trial.
  /// 3. `notifyListeners()` uma única vez, só depois de 1 confirmar no
  ///    banco — isso é o que faz o `MaterialApp.themeMode` (main.dart) e o
  ///    redirect do GoRouter (que relê `anonymous_users` do zero a cada
  ///    avaliação) mudarem de forma consistente, não apenas "otimista".
  Future<void> switchProfile(ProfileUsageType novoPerfil) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _isSwitching = true;
    notifyListeners();

    try {
      await _persistPerfilUso(userId, novoPerfil);
      _profileType = novoPerfil;
      await _congelarGamificacaoSemPunicao(userId, novoPerfil);
    } finally {
      _isSwitching = false;
      notifyListeners();
    }
  }

  Future<void> _persistPerfilUso(
    String userId,
    ProfileUsageType novoPerfil,
  ) async {
    final atual = await _client
        .from('anonymous_users')
        .select('profile_data')
        .eq('id', userId)
        .maybeSingle();

    final profileData = Map<String, dynamic>.from(
      (atual?['profile_data'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    profileData['perfil_uso'] = _profileTypeToTag(novoPerfil);

    await _client.from('anonymous_users').upsert(
      {'id': userId, 'profile_data': profileData},
      onConflict: 'id',
    );
  }

  /// Perfil Atleta reativa a gamificação; qualquer outro perfil (Sênior,
  /// Assíncrono) congela sem punição — o streak/liga fica pausado, não
  /// zerado, exatamente como o Modo Recuperação já garante localmente.
  Future<void> _congelarGamificacaoSemPunicao(
    String userId,
    ProfileUsageType novoPerfil,
  ) async {
    final congelar = novoPerfil != ProfileUsageType.athlete;
    try {
      await _client.from('progresso_gamificacao').upsert({
        'usuario_id_anonimo': userId,
        'status_usuario': congelar ? 'pausado_sem_penalidade' : 'ativo',
        'detalhes_recuperacao_jsonb': congelar
            ? {
                'motivo': 'troca_perfil_uso',
                'congelado_em': DateTime.now().toIso8601String(),
              }
            : null,
      }, onConflict: 'usuario_id_anonimo');
    } on PostgrestException catch (e) {
      debugPrint('Erro ao congelar gamificação: ${e.message}');
    }
  }

  static String _profileTypeToTag(ProfileUsageType type) {
    switch (type) {
      case ProfileUsageType.athlete:
        return 'Atleta';
      case ProfileUsageType.guardian:
        return 'Senior';
      case ProfileUsageType.doctor:
        return 'Assincrono';
    }
  }

  static ProfileUsageType? _parseProfileType(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    if (lower.contains('atleta') || lower.contains('athlete')) {
      return ProfileUsageType.athlete;
    }
    if (lower.contains('senior') ||
        lower.contains('sênior') ||
        lower.contains('guardi')) {
      return ProfileUsageType.guardian;
    }
    if (lower.contains('assincrono') ||
        lower.contains('assíncrono') ||
        lower.contains('medic') ||
        lower.contains('doctor')) {
      return ProfileUsageType.doctor;
    }
    return null;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileChannel?.unsubscribe();
    super.dispose();
  }
}

/// Singleton instance — the one [UiProfileSwitcher] the whole app (theme,
/// router, dashboard shell) shares.
final uiProfileSwitcher = UiProfileSwitcher();
