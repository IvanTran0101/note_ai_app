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

  tearDown(() => controller.dispose());

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
    return registerResult;
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    _record('login');
    loginInput = input;
    return loginResult;
  }

  @override
  Future<void> logout() async {
    _record('logout');
  }

  @override
  Future<AuthUserDto?> restoreSession() async {
    _record('restoreSession');
    return restoreResult;
  }

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
