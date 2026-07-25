import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:atleta_gamificacao/core/router/auth_recovery_controller.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _FakeAuthState extends Fake implements AuthState {
  _FakeAuthState(this.event);
  @override
  final AuthChangeEvent event;
}

void main() {
  late _MockSupabaseClient supabase;
  late _MockGoTrueClient auth;
  late StreamController<AuthState> authEvents;
  late AuthRecoveryController controller;

  setUp(() {
    supabase = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    authEvents = StreamController<AuthState>.broadcast();

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.onAuthStateChange).thenAnswer((_) => authEvents.stream);

    controller = AuthRecoveryController(client: supabase);
  });

  tearDown(() async {
    controller.dispose();
    await authEvents.close();
  });

  test('começa fora de recuperação', () {
    expect(controller.emRecuperacao, isFalse);
  });

  test('AuthChangeEvent.passwordRecovery liga emRecuperacao e notifica', () async {
    var notificacoes = 0;
    controller.addListener(() => notificacoes++);

    authEvents.add(_FakeAuthState(AuthChangeEvent.passwordRecovery));
    await Future<void>.delayed(Duration.zero);

    expect(controller.emRecuperacao, isTrue);
    expect(notificacoes, 1);
  });

  test('concluir() desliga emRecuperacao e notifica', () async {
    authEvents.add(_FakeAuthState(AuthChangeEvent.passwordRecovery));
    await Future<void>.delayed(Duration.zero);
    expect(controller.emRecuperacao, isTrue);

    var notificacoes = 0;
    controller.addListener(() => notificacoes++);
    controller.concluir();

    expect(controller.emRecuperacao, isFalse);
    expect(notificacoes, 1);
  });

  test('concluir() sem estar em recuperação é um no-op silencioso', () {
    var notificacoes = 0;
    controller.addListener(() => notificacoes++);

    controller.concluir();

    expect(controller.emRecuperacao, isFalse);
    expect(notificacoes, 0);
  });

  test('signedOut durante uma recuperação encerra o estado sem travar o app', () async {
    authEvents.add(_FakeAuthState(AuthChangeEvent.passwordRecovery));
    await Future<void>.delayed(Duration.zero);
    expect(controller.emRecuperacao, isTrue);

    authEvents.add(_FakeAuthState(AuthChangeEvent.signedOut));
    await Future<void>.delayed(Duration.zero);

    expect(controller.emRecuperacao, isFalse);
  });

  test('outros eventos (ex.: signedIn normal) não afetam emRecuperacao', () async {
    authEvents.add(_FakeAuthState(AuthChangeEvent.signedIn));
    await Future<void>.delayed(Duration.zero);

    expect(controller.emRecuperacao, isFalse);
  });
}
