import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/domain/auth/authentication_failure.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_state.dart';

void main() {
  late FakeAuthenticationAppService service;
  late AuthController controller;

  setUp(() {
    service = FakeAuthenticationAppService();
    controller = AuthController(authenticationAppService: service);
  });

  tearDown(() {
    controller.dispose();
    service.authState.close();
  });

  test('starts in initializing state without a user', () {
    expect(controller.state.status, AuthStatus.initializing);
    expect(controller.state.user, isNull);
    expect(controller.state.isBusy, isFalse);
    expect(controller.state.error, isNull);
  });

  test(
    'initialize maps an empty restored session to unauthenticated',
    () async {
      final AuthUserDto? restored = await controller.initialize();

      expect(restored, isNull);
      expect(service.calls, <String>['restoreSession']);
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.error, isNull);
    },
  );

  test('initialize publishes a restored user', () async {
    service.restoreResult = testUser;

    await controller.initialize();

    expect(controller.state.status, AuthStatus.authenticated);
    expect(controller.state.user, testUser);
    expect(controller.state.isAuthenticated, isTrue);
  });

  test('a completed initialize is idempotent', () async {
    await controller.initialize();
    await controller.initialize();

    expect(service.calls, <String>['restoreSession']);
  });

  test('login publishes the returned user and delegates the input', () async {
    service.loginResult = testUser;
    const LoginInput input = LoginInput(
      email: 'user@example.com',
      password: 'secret',
    );

    final AuthUserDto result = await controller.login(input);

    expect(result, testUser);
    expect(service.calls, <String>['login']);
    expect(service.loginInput, input);
    expect(controller.state.status, AuthStatus.authenticated);
    expect(controller.state.user, testUser);
    expect(controller.state.isBusy, isFalse);
    expect(controller.state.error, isNull);
  });

  test('register publishes the auto-logged-in user', () async {
    service.registerResult = RegistrationResult(
      user: testUser,
      verificationDispatchStatus: VerificationDispatchStatus.requested,
    );

    final RegistrationResult result = await controller.register(
      const RegisterInput(
        email: 'user@example.com',
        displayName: 'User',
        password: 'secret',
        confirmPassword: 'secret',
      ),
    );

    expect(result.user, testUser);
    expect(
      result.verificationDispatchStatus,
      VerificationDispatchStatus.requested,
    );
    expect(controller.state.status, AuthStatus.authenticated);
    expect(controller.state.user, testUser);
  });

  test('maps provider failures without retaining the raw exception', () async {
    service.failures['login'] = const AuthenticationFailure(
      AuthenticationFailureCode.invalidCredentials,
    );

    await expectLater(
      () => controller.login(
        const LoginInput(email: 'user@example.com', password: 'wrong'),
      ),
      throwsA(isA<AuthenticationFailure>()),
    );

    expect(
      controller.state.error,
      const AuthPresentationError(AuthPresentationErrorCode.invalidCredentials),
    );
    expect(controller.state.error.toString(), contains('invalidCredentials'));
    expect(controller.state.status, AuthStatus.initializing);
  });

  test(
    'restore failure stays initializing so it is not mistaken for logout',
    () async {
      service.failures['restoreSession'] = const AuthenticationFailure(
        AuthenticationFailureCode.temporarilyUnavailable,
      );

      await expectLater(
        controller.initialize,
        throwsA(isA<AuthenticationFailure>()),
      );

      expect(controller.state.status, AuthStatus.initializing);
      expect(
        controller.state.error?.code,
        AuthPresentationErrorCode.temporarilyUnavailable,
      );
    },
  );

  test('logout failure still leaves the controller unauthenticated', () async {
    controller = AuthController(
      authenticationAppService: service,
      initialUser: testUser,
    );
    service.failures['logout'] = const AuthenticationFailure(
      AuthenticationFailureCode.temporarilyUnavailable,
    );

    await expectLater(controller.logout, throwsA(isA<AuthenticationFailure>()));

    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(
      controller.state.error?.code,
      AuthPresentationErrorCode.temporarilyUnavailable,
    );
  });

  test(
    'initial user bypasses restore for the local compatibility mode',
    () async {
      controller = AuthController(
        authenticationAppService: service,
        initialUser: testUser,
      );

      final AuthUserDto? restored = await controller.initialize();

      expect(restored, testUser);
      expect(service.calls, isEmpty);
      expect(controller.state.status, AuthStatus.authenticated);
    },
  );

  test(
    'local compatibility logout clears the session without a provider',
    () async {
      controller.dispose();
      controller = AuthController(
        authenticationAppService: null,
        initialUser: testUser,
      );

      await controller.logout();

      expect(controller.state.status, AuthStatus.unauthenticated);
    },
  );

  group('operation races', () {
    test(
      'a hub unauthenticated event during login keeps the operation busy',
      () async {
        final Completer<AuthUserDto> gate = Completer<AuthUserDto>();
        service.loginGate = gate;
        final Future<AuthUserDto> login = controller.login(
          const LoginInput(email: 'user@example.com', password: 'secret'),
        );
        await pumpEventQueue();

        service.authState.add(null);
        await pumpEventQueue();

        expect(controller.state.status, AuthStatus.unauthenticated);
        expect(controller.state.isBusy, isTrue);
        await expectLater(controller.refreshIdentity(), throwsStateError);

        gate.complete(testUser);
        final AuthUserDto user = await login;

        expect(user, testUser);
        expect(controller.state.status, AuthStatus.authenticated);
        expect(controller.state.user, testUser);
        expect(controller.state.isBusy, isFalse);
        expect(controller.state.error, isNull);
      },
    );

    test(
      'a stale login error after logout does not overwrite the logout state',
      () async {
        final Completer<AuthUserDto> gate = Completer<AuthUserDto>();
        service.loginGate = gate;
        final List<AuthState> states = <AuthState>[];
        controller.addListener(() => states.add(controller.state));
        final Future<AuthUserDto> login = controller.login(
          const LoginInput(email: 'a@example.com', password: 'secret'),
        );
        await pumpEventQueue();

        await controller.logout();
        gate.completeError(
          const AuthenticationFailure(
            AuthenticationFailureCode.unauthenticated,
          ),
        );

        await expectLater(login, throwsA(isA<AuthenticationFailure>()));
        expect(controller.state.status, AuthStatus.unauthenticated);
        expect(controller.state.isBusy, isFalse);
        expect(controller.state.error, isNull);
        expect(states.where((AuthState state) => state.error != null), isEmpty);
      },
    );

    test(
      'a normal login still emits exactly one authenticated state',
      () async {
        service.loginResult = testUser;
        final List<AuthState> states = <AuthState>[];
        controller.addListener(() => states.add(controller.state));

        await controller.login(
          const LoginInput(email: 'user@example.com', password: 'secret'),
        );

        expect(states.map((AuthState state) => state.status), <AuthStatus>[
          AuthStatus.initializing,
          AuthStatus.authenticated,
        ]);
        expect(states.last.user, testUser);
        expect(states.last.isBusy, isFalse);
        expect(states.last.error, isNull);
      },
    );
  });

  group('initialize races', () {
    test('a restore resolving after logout returns its user without re-authenticating', () async {
      final Completer<AuthUserDto?> gate = Completer<AuthUserDto?>();
      service.restoreGate = gate;
      final List<AuthState> states = <AuthState>[];
      controller.addListener(() => states.add(controller.state));
      final Future<AuthUserDto?> restore = controller.initialize();
      await pumpEventQueue();

      await controller.logout();
      gate.complete(testUser);
      final AuthUserDto? restored = await restore;

      expect(restored, testUser);
      expect(service.calls, <String>['restoreSession', 'logout']);
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.user, isNull);
      expect(controller.state.isBusy, isFalse);
      expect(controller.state.error, isNull);
      expect(
        states
            .where(
              (AuthState state) => state.status == AuthStatus.authenticated,
            )
            .length,
        0,
      );
      expect(states.last.status, AuthStatus.unauthenticated);
    });

    test('a restore failing after logout throws to its caller without a stale error', () async {
      final Completer<AuthUserDto?> gate = Completer<AuthUserDto?>();
      service.restoreGate = gate;
      final List<AuthState> states = <AuthState>[];
      controller.addListener(() => states.add(controller.state));
      final Future<AuthUserDto?> restore = controller.initialize();
      await pumpEventQueue();

      await controller.logout();
      gate.completeError(
        const AuthenticationFailure(
          AuthenticationFailureCode.temporarilyUnavailable,
        ),
      );

      await expectLater(restore, throwsA(isA<AuthenticationFailure>()));
      expect(service.calls, <String>['restoreSession', 'logout']);
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.user, isNull);
      expect(controller.state.isBusy, isFalse);
      expect(controller.state.error, isNull);
      expect(states.where((AuthState state) => state.error != null), isEmpty);
    });

    test('initialize during a pending login is rejected without a provider restore', () async {
      final Completer<AuthUserDto> gate = Completer<AuthUserDto>();
      service.loginGate = gate;
      final Future<AuthUserDto> login = controller.login(
        const LoginInput(email: 'user@example.com', password: 'secret'),
      );
      await pumpEventQueue();

      await expectLater(controller.initialize, throwsStateError);
      expect(service.calls, <String>[
        'login',
      ], reason: 'the pending login must not be superseded by a restore');

      gate.complete(testUser);
      expect(await login, testUser);
      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user, testUser);
      expect(controller.state.isBusy, isFalse);
    });

    test('initialize during a pending registration is rejected and metadata is kept', () async {
      final Completer<RegistrationResult> gate =
          Completer<RegistrationResult>();
      service.registerGate = gate;
      final Future<RegistrationResult> registration = controller.register(
        const RegisterInput(
          email: 'new@example.com',
          displayName: ' New User ',
          password: 'secret',
          confirmPassword: 'secret',
        ),
      );
      await pumpEventQueue();

      await expectLater(controller.initialize, throwsStateError);
      expect(
        service.calls,
        <String>['register'],
        reason: 'the pending registration must not be superseded by a restore',
      );

      gate.complete(
        RegistrationResult(
          user: testUser,
          verificationDispatchStatus: VerificationDispatchStatus.requested,
          profileSetupPending: true,
        ),
      );
      final RegistrationResult result = await registration;
      expect(result.user, testUser);
      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.pendingProfileDisplayName, 'New User');
    });

    test(
      'login during a pending initialize is rejected without superseding it',
      () async {
        final Completer<AuthUserDto?> gate = Completer<AuthUserDto?>();
        service.restoreGate = gate;
        final Future<AuthUserDto?> initialize = controller.initialize();
        await pumpEventQueue();

        await expectLater(
          () => controller.login(
            const LoginInput(email: 'user@example.com', password: 'secret'),
          ),
          throwsStateError,
        );
        expect(service.calls, <String>['restoreSession']);

        gate.complete(testUser);
        expect(await initialize, testUser);
        expect(controller.state.status, AuthStatus.authenticated);
        expect(controller.state.user, testUser);
      },
    );

    test('concurrent initialize calls share one restoreSession run', () async {
      final Completer<AuthUserDto?> gate = Completer<AuthUserDto?>();
      service.restoreGate = gate;
      final List<AuthState> states = <AuthState>[];
      controller.addListener(() => states.add(controller.state));
      final Future<AuthUserDto?> first = controller.initialize();
      final Future<AuthUserDto?> second = controller.initialize();
      await pumpEventQueue();

      expect(
        service.calls.where((String name) => name == 'restoreSession').length,
        1,
      );

      gate.complete(testUser);
      final List<AuthUserDto?> restored = await Future.wait(
        <Future<AuthUserDto?>>[first, second],
      );

      expect(restored, <AuthUserDto?>[testUser, testUser]);
      expect(
        service.calls.where((String name) => name == 'restoreSession').length,
        1,
      );
      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user, testUser);
      expect(controller.state.isBusy, isFalse);
      expect(controller.state.error, isNull);
      expect(states.map((AuthState state) => state.status), <AuthStatus>[
        AuthStatus.initializing,
        AuthStatus.authenticated,
      ]);
    });

    test(
      'a failed initialize clears the shared restore so a retry succeeds',
      () async {
        service.failures['restoreSession'] = const AuthenticationFailure(
          AuthenticationFailureCode.temporarilyUnavailable,
        );

        await expectLater(
          controller.initialize,
          throwsA(isA<AuthenticationFailure>()),
        );

        service.failures.remove('restoreSession');
        service.restoreResult = testUser;

        final AuthUserDto? restored = await controller.initialize();

        expect(restored, testUser);
        expect(service.calls, <String>['restoreSession', 'restoreSession']);
        expect(controller.state.status, AuthStatus.authenticated);
        expect(controller.state.user, testUser);
        expect(controller.state.isBusy, isFalse);
        expect(controller.state.error, isNull);
      },
    );

    test(
      'a normal initialize completes with authenticated exactly once',
      () async {
        service.restoreResult = testUser;
        final List<AuthState> states = <AuthState>[];
        controller.addListener(() => states.add(controller.state));

        final AuthUserDto? restored = await controller.initialize();

        expect(restored, testUser);
        expect(states.map((AuthState state) => state.status), <AuthStatus>[
          AuthStatus.initializing,
          AuthStatus.authenticated,
        ]);
        expect(
          states
              .where(
                (AuthState state) => state.status == AuthStatus.authenticated,
              )
              .length,
          1,
        );
        expect(states.last.user, testUser);
        expect(states.last.isBusy, isFalse);
        expect(states.last.error, isNull);
      },
    );
  });

  group('auth state stream', () {
    test('subscribes to the service stream on construction', () {
      expect(service.hasAuthStateListener, isTrue);
    });

    test('publishes an authenticated state for a signed-in event', () async {
      await controller.initialize();
      expect(controller.state.status, AuthStatus.unauthenticated);

      service.authState.add(testUser);
      await pumpEventQueue();

      expect(controller.state.status, AuthStatus.authenticated);
      expect(controller.state.user, testUser);
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.error, isNull);
    });

    test('publishes an unauthenticated state for a null event', () async {
      await controller.initialize();
      service.authState.add(testUser);
      await pumpEventQueue();
      expect(controller.state.status, AuthStatus.authenticated);

      service.authState.add(null);
      await pumpEventQueue();

      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.user, isNull);
      expect(controller.state.error, isNull);
    });

    test('maps a stream failure to a presentation error', () async {
      await controller.initialize();

      service.authState.addError(
        const AuthenticationFailure(
          AuthenticationFailureCode.identityUnavailable,
        ),
      );
      await pumpEventQueue();

      expect(
        controller.state.error,
        const AuthPresentationError(
          AuthPresentationErrorCode.identityUnavailable,
        ),
      );
      expect(
        controller.state.error.toString(),
        contains('identityUnavailable'),
      );
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.user, isNull);
    });

    test('cancels the subscription and stops reacting after dispose', () async {
      final FakeAuthenticationAppService streamedService =
          FakeAuthenticationAppService();
      final AuthController streamedController = AuthController(
        authenticationAppService: streamedService,
      );
      addTearDown(streamedService.authState.close);

      expect(streamedService.hasAuthStateListener, isTrue);

      streamedController.dispose();
      await pumpEventQueue();

      expect(streamedService.hasAuthStateListener, isFalse);
      streamedService.authState.add(testUser);
      await pumpEventQueue();

      expect(streamedController.state.status, AuthStatus.initializing);
      expect(streamedController.state.user, isNull);
      expect(streamedController.state.error, isNull);
    });
  });
}

const AuthUserDto testUser = AuthUserDto(
  userId: 'user-1',
  email: 'user@example.com',
  isEmailVerified: false,
);

final class FakeAuthenticationAppService implements IAuthenticationAppService {
  final List<String> calls = <String>[];
  final Map<String, Object> failures = <String, Object>{};

  AuthUserDto? restoreResult;
  AuthUserDto loginResult = testUser;
  RegistrationResult registerResult = const RegistrationResult(
    user: testUser,
    verificationDispatchStatus: VerificationDispatchStatus.notRequired,
  );
  LoginInput? loginInput;

  /// When set, [login] parks until the completer resolves, so a test can
  /// deliver auth-state events between the call and its completion.
  Completer<AuthUserDto>? loginGate;

  /// When set, [restoreSession] parks until the completer resolves, so a
  /// test can interleave other operations with a pending restore.
  Completer<AuthUserDto?>? restoreGate;

  /// When set, [register] parks until the completer resolves, so a test can
  /// interleave initialization with a pending registration.
  Completer<RegistrationResult>? registerGate;

  /// Application auth-state events the fake replays to its observer.
  final StreamController<AuthUserDto?> authState =
      StreamController<AuthUserDto?>.broadcast();

  bool get hasAuthStateListener => authState.hasListener;

  void _record(String name) {
    calls.add(name);
    final Object? failure = failures[name];
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    _record('register');
    final Completer<RegistrationResult>? gate = registerGate;
    if (gate != null) {
      return gate.future;
    }
    return registerResult;
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    _record('login');
    loginInput = input;
    final Completer<AuthUserDto>? gate = loginGate;
    if (gate != null) {
      return gate.future;
    }
    return loginResult;
  }

  @override
  Future<void> logout() async {
    _record('logout');
  }

  @override
  Future<AuthUserDto?> restoreSession() async {
    _record('restoreSession');
    final Completer<AuthUserDto?>? gate = restoreGate;
    if (gate != null) {
      return gate.future;
    }
    return restoreResult;
  }

  @override
  Stream<AuthUserDto?> observeAuthState() => authState.stream;

  @override
  Future<AuthUserDto> refreshIdentity() async {
    _record('refreshIdentity');
    return loginResult;
  }

  @override
  Future<void> resendEmailVerification() async {
    _record('resendEmailVerification');
  }

  @override
  Future<AuthUserDto> confirmEmailVerification({required String code}) async {
    _record('confirmEmailVerification');
    return loginResult;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    _record('requestPasswordReset');
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _record('confirmPasswordReset');
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _record('changePassword');
  }
}
