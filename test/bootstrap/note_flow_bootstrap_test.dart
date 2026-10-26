/// Tests for the startup bootstrap root: a retryable failure must land on a
/// visible retry screen (never a blank window), a terminal configuration
/// failure must direct a reload without offering an impossible retry, a
/// successful boot must mount the app shell exactly once, and the root must
/// release every abandoned AuthController result. The real bootstrap and the
/// real app shell are both injected away; these tests never touch Amplify.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/infrastructure/auth/amplify_auth_initializer.dart';
import 'package:note_ai_app/main.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';

final AuthIdentity _identity = AuthIdentity(
  userId: 'bootstrap-user',
  email: 'bootstrap-user@noteflow.local',
  isEmailVerified: true,
);

typedef _BootstrapResult = ({
  AuthController authController,
  CurrentUserSession currentUserSession,
});

_BootstrapResult _resultFor(AuthController controller) {
  final CurrentUserSession session = CurrentUserSession()
    ..setIdentity(_identity);
  return (currentUserSession: session, authController: controller);
}

Widget _testApp({
  required AuthController authController,
  required CurrentUserSession currentUserSession,
}) {
  return const KeyedSubtree(key: Key('bootstrap-test-app'), child: SizedBox());
}

void main() {
  testWidgets('a retryable bootstrap failure shows the retry screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      NoteFlowBootstrapRoot(
        bootstrapRunner: () => throw StateError('temporarily unavailable'),
        appBuilder: _testApp,
      ),
    );
    // initState starts the run; one pump settles the loading frame, the next
    // settles the error frame.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bootstrap-test-app')), findsNothing);
    expect(find.text('NoteFlow could not start.'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-retry')), findsOneWidget);
    expect(
      find.textContaining('Retry cannot repair configuration.'),
      findsNothing,
    );
  });

  testWidgets(
    'a terminal SDK configuration failure directs reload and offers no retry',
    (tester) async {
      await tester.pumpWidget(
        NoteFlowBootstrapRoot(
          bootstrapRunner: () async =>
              throw const AmplifyAuthInitializationFailure(
                cause: 'malformed configuration',
              ),
          appBuilder: _testApp,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bootstrap-test-app')), findsNothing);
      expect(find.text('NoteFlow could not start.'), findsOneWidget);
      expect(
        find.textContaining('Retry cannot repair configuration.'),
        findsOneWidget,
      );
      // A retry cannot reconfigure this process, so it is not offered.
      expect(find.byKey(const Key('bootstrap-retry')), findsNothing);
    },
  );

  testWidgets('a successful bootstrap mounts the app exactly once', (
    tester,
  ) async {
    final _TrackingAuthService service = _TrackingAuthService();
    addTearDown(service.authState.close);
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );
    int runs = 0;
    Widget? mounted;
    await tester.pumpWidget(
      NoteFlowBootstrapRoot(
        bootstrapRunner: () async {
          runs += 1;
          return _resultFor(controller);
        },
        appBuilder: ({required authController, required currentUserSession}) {
          final Widget app = _testApp(
            authController: authController,
            currentUserSession: currentUserSession,
          );
          // Record the instance: repeated builds must reuse the first one.
          mounted ??= app;
          return mounted!;
        },
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(runs, 1);
    expect(find.byKey(const Key('bootstrap-test-app')), findsOneWidget);
    // Further frames reuse the memoized child: no second mount.
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('bootstrap-test-app')), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-retry')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(service.hasAuthStateListener, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid double retry never runs the bootstrap concurrently and recovers',
    (tester) async {
      int attempts = 0;
      final Completer<_BootstrapResult> firstRetry =
          Completer<_BootstrapResult>();
      bool firstRetryGate = true;

      Future<_BootstrapResult> runner() async {
        attempts += 1;
        if (firstRetryGate) {
          // First retry stays in flight until the test releases it.
          return firstRetry.future;
        }
        return _resultFor(_localController());
      }

      // Initial boot fails with a retryable-looking error (a partial-failure
      // style "plugin already added" refusal is retriable, not permanent).
      Object? initialError = StateError('plugin already added');
      await tester.pumpWidget(
        NoteFlowBootstrapRoot(
          bootstrapRunner: () async {
            final Object? error = initialError;
            initialError = null;
            if (error != null) {
              throw error;
            }
            return runner();
          },
          appBuilder: _testApp,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(attempts, 0, reason: 'the failed boot never reached the runner');
      expect(
        find.text('NoteFlow could not start.'),
        findsOneWidget,
        reason: 'error pane should be visible before retrying',
      );

      // Two rapid retry taps while the first retry is still in flight: the
      // guard must collapse them into one run.
      await tester.tap(find.byKey(const Key('bootstrap-retry')));
      await tester.pump();
      // The in-flight retry renders the loading state, so the second tap must
      // be a no-op against the guard rather than a second run.
      if (find.byKey(const Key('bootstrap-retry')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('bootstrap-retry')));
      }
      await tester.pump();
      expect(attempts, 1);

      firstRetryGate = false;
      firstRetry.complete(_resultFor(_localController()));
      await tester.pumpAndSettle();

      expect(attempts, 1, reason: 'the second tap started no extra run');
      expect(find.byKey(const Key('bootstrap-test-app')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unmounting before a late result disposes the abandoned controller',
    (tester) async {
      final _TrackingAuthService service = _TrackingAuthService();
      addTearDown(service.authState.close);
      final AuthController controller = AuthController(
        authenticationAppService: service,
      );
      final Completer<_BootstrapResult> gate = Completer<_BootstrapResult>();

      await tester.pumpWidget(
        NoteFlowBootstrapRoot(
          bootstrapRunner: () => gate.future,
          appBuilder: _testApp,
        ),
      );
      await tester.pump();
      expect(service.hasAuthStateListener, isTrue);

      await tester.pumpWidget(const SizedBox());
      gate.complete(_resultFor(controller));
      await tester.pump();
      await tester.pump();

      // The late result never reached the shell: its subscription is gone.
      expect(service.hasAuthStateListener, isFalse);
      expect(service.restoreCalls, 0);
      await expectLater(controller.initialize(), throwsStateError);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an appBuilder throw releases the bootstrap result', (
    tester,
  ) async {
    final _TrackingAuthService service = _TrackingAuthService();
    addTearDown(service.authState.close);
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );

    await tester.pumpWidget(
      NoteFlowBootstrapRoot(
        bootstrapRunner: () async => _resultFor(controller),
        appBuilder: ({required authController, required currentUserSession}) {
          throw StateError('shell composition failed');
        },
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bootstrap-test-app')), findsNothing);
    expect(find.text('NoteFlow could not start.'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-retry')), findsOneWidget);
    expect(service.hasAuthStateListener, isFalse);
    await expectLater(controller.initialize(), throwsStateError);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful teardown disposes the root-owned controller once', (
    tester,
  ) async {
    final _TrackingAuthService service = _TrackingAuthService();
    addTearDown(service.authState.close);
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );

    await tester.pumpWidget(
      NoteFlowBootstrapRoot(
        bootstrapRunner: () async => _resultFor(controller),
        appBuilder: _testApp,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bootstrap-test-app')), findsOneWidget);
    expect(service.hasAuthStateListener, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    // Root ownership disposes exactly once; a double dispose would assert
    // inside ChangeNotifier and surface through takeException.
    expect(service.hasAuthStateListener, isFalse);
    expect(service.restoreCalls, 0);
    await expectLater(controller.initialize(), throwsStateError);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two roots never share a bootstrap controller result', (
    tester,
  ) async {
    final _TrackingAuthService serviceA = _TrackingAuthService();
    final _TrackingAuthService serviceB = _TrackingAuthService();
    addTearDown(serviceA.authState.close);
    addTearDown(serviceB.authState.close);
    final AuthController controllerA = AuthController(
      authenticationAppService: serviceA,
    );
    final AuthController controllerB = AuthController(
      authenticationAppService: serviceB,
    );
    final Completer<_BootstrapResult> gateA = Completer<_BootstrapResult>();
    final Completer<_BootstrapResult> gateB = Completer<_BootstrapResult>();

    await tester.pumpWidget(
      NoteFlowBootstrapRoot(
        key: const ValueKey<String>('root-a'),
        bootstrapRunner: () => gateA.future,
        appBuilder: _testApp,
      ),
    );
    await tester.pump();
    // Replacing the root disposes root A's state while its run is in flight.
    await tester.pumpWidget(
      NoteFlowBootstrapRoot(
        key: const ValueKey<String>('root-b'),
        bootstrapRunner: () => gateB.future,
        appBuilder: _testApp,
      ),
    );
    await tester.pump();

    gateA.complete(_resultFor(controllerA));
    gateB.complete(_resultFor(controllerB));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(controllerA, isNot(same(controllerB)));
    expect(serviceA.hasAuthStateListener, isFalse);
    expect(serviceB.hasAuthStateListener, isTrue);
    expect(find.byKey(const Key('bootstrap-test-app')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(serviceB.hasAuthStateListener, isFalse);
    expect(tester.takeException(), isNull);
  });
}

AuthController _localController() {
  return AuthController(
    authenticationAppService: null,
    initialUser: AuthUserDto.fromIdentity(_identity),
  );
}

final class _TrackingAuthService implements IAuthenticationAppService {
  int restoreCalls = 0;
  final StreamController<AuthUserDto?> authState =
      StreamController<AuthUserDto?>.broadcast();

  bool get hasAuthStateListener => authState.hasListener;

  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    return RegistrationResult(
      user: AuthUserDto.fromIdentity(_identity),
      verificationDispatchStatus: VerificationDispatchStatus.notRequired,
    );
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    return AuthUserDto.fromIdentity(_identity);
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUserDto?> restoreSession() async {
    restoreCalls++;
    return null;
  }

  @override
  Stream<AuthUserDto?> observeAuthState() => authState.stream;

  @override
  Future<AuthUserDto> refreshIdentity() async {
    return AuthUserDto.fromIdentity(_identity);
  }

  @override
  Future<void> resendEmailVerification() async {}

  @override
  Future<AuthUserDto> confirmEmailVerification({required String code}) async {
    return AuthUserDto.fromIdentity(_identity);
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {}

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {}
}
