import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_state.dart';

// Reuse the gated provider double from the application-service suite so these
// tests exercise the real epoch fencing in AuthenticationAppService.
import '../../../application/auth/authentication_app_service_test.dart'
    as support;

void main() {
  late support.FakeAuthenticationService provider;
  late AuthenticationAppService service;
  late AuthController controller;

  setUp(() {
    provider = support.FakeAuthenticationService();
    service = AuthenticationAppService(
      authenticationService: provider,
      currentUserSession: CurrentUserSession(),
      userProfileRepository: support.FakeUserProfileRepository(),
    );
    controller = AuthController(authenticationAppService: service);
  });

  tearDown(() async {
    controller.dispose();
    await provider.authState.close();
  });

  /// Reproduces the startup race: the hub reports signed out while the
  /// identity read is pending, so the real service rejects the stale read
  /// after the controller has already marked initialization complete.
  Future<void> failRestoreAfterHubSignOut() async {
    final Completer<AuthIdentity?> identityRead = Completer<AuthIdentity?>();
    provider.getCurrentIdentityGate = identityRead;
    final Future<void> rejected = expectLater(
      controller.initialize(),
      throwsA(support.unauthenticatedFailure()),
    );
    await pumpEventQueue();

    provider.authState.add(null);
    await pumpEventQueue();
    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(controller.state.isBusy, isTrue);

    identityRead.complete(null);
    await rejected;

    expect(controller.state.status, AuthStatus.initializing);
    expect(controller.state.error, isNotNull);
    expect(provider.countOf('getCurrentIdentity'), 1);
  }

  test(
    'Retry reads identity again after a hub sign-out rejected the restore',
    () async {
      await failRestoreAfterHubSignOut();

      provider.getCurrentIdentityGate = null;
      expect(await controller.initialize(), isNull);

      expect(
        provider.countOf('getCurrentIdentity'),
        2,
        reason: 'Retry must not short-circuit on the failed restore completion',
      );
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.error, isNull);
      expect(controller.state.isBusy, isFalse);
    },
  );

  test('concurrent Retry callers share one identity read', () async {
    await failRestoreAfterHubSignOut();

    final Completer<AuthIdentity?> retryGate = Completer<AuthIdentity?>();
    provider.getCurrentIdentityGate = retryGate;
    final Future<AuthUserDto?> first = controller.initialize();
    final Future<AuthUserDto?> second = controller.initialize();
    await pumpEventQueue();

    expect(
      provider.countOf('getCurrentIdentity'),
      2,
      reason: 'both Retry callers must coalesce on one provider read',
    );

    retryGate.complete(null);
    expect(
      await Future.wait(<Future<AuthUserDto?>>[first, second]),
      <AuthUserDto?>[null, null],
    );
    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(controller.state.error, isNull);
    expect(controller.state.isBusy, isFalse);
  });

  test('a late restore error after logout does not reset the completed initialization', () async {
    final Completer<AuthIdentity?> identityRead = Completer<AuthIdentity?>();
    provider.getCurrentIdentityGate = identityRead;
    final List<AuthState> states = <AuthState>[];
    controller.addListener(() => states.add(controller.state));
    final Future<AuthUserDto?> restore = controller.initialize();
    await pumpEventQueue();

    provider.authState.add(null);
    await pumpEventQueue();
    await controller.logout();

    final Future<void> rejected = expectLater(
      restore,
      throwsA(support.unauthenticatedFailure()),
    );
    identityRead.complete(null);
    await rejected;

    expect(provider.countOf('getCurrentIdentity'), 1);
    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(controller.state.error, isNull);
    expect(states.where((AuthState state) => state.error != null), isEmpty);

    // The hub sign-out already completed initialization; the superseded
    // restore failure must not clear that completion and force another read.
    expect(await controller.initialize(), isNull);
    expect(provider.countOf('getCurrentIdentity'), 1);
  });
}
