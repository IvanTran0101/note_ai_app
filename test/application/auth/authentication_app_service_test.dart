import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/auth/authentication_failure.dart';
import 'package:note_ai_app/domain/auth/authentication_service.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/domain/users/user_profile_repository.dart';

void main() {
  late FakeAuthenticationService authentication;
  late FakeUserProfileRepository profiles;
  late CurrentUserSession session;
  late AuthenticationAppService service;

  setUp(() {
    authentication = FakeAuthenticationService();
    profiles = FakeUserProfileRepository();
    session = CurrentUserSession();
    service = AuthenticationAppService(
      authenticationService: authentication,
      currentUserSession: session,
      userProfileRepository: profiles,
    );
    addTearDown(authentication.authState.close);
  });

  group('login', () {
    test(
      'authenticates, publishes the identity, and returns provider facts',
      () async {
        authentication.loginResult = identity(isEmailVerified: true);

        final AuthUserDto user = await service.login(
          const LoginInput(email: '  user@example.com ', password: ' secret '),
        );

        expect(authentication.calls, <String>['login']);
        expect(authentication.input('login.email'), 'user@example.com');
        expect(authentication.input('login.password'), ' secret ');
        expect(user.userId, 'user-1');
        expect(user.email, 'user@example.com');
        expect(user.isEmailVerified, isTrue);
        expect(session.identity, same(authentication.loginResult));
      },
    );

    test(
      'keeps the previous session when the provider rejects the login',
      () async {
        final AuthIdentity previous = identity(userId: 'user-9');
        session.setIdentity(previous);
        authentication.failures['login'] = Exception('rejected');

        await expectLater(
          () => service.login(
            const LoginInput(email: 'user@example.com', password: 'wrong'),
          ),
          throwsA(isA<Exception>()),
        );

        expect(session.identity, same(previous));
      },
    );
  });

  group('logout', () {
    test(
      'clears the local session even when provider sign-out fails',
      () async {
        session.setIdentity(identity());
        authentication.failures['logout'] = Exception('network');

        await expectLater(service.logout, throwsA(isA<Exception>()));

        expect(session.isAuthenticated, isFalse);
        expect(authentication.calls, <String>['logout']);
      },
    );
  });

  group('restoreSession', () {
    test(
      'clears the session and returns null without a provider identity',
      () async {
        session.setIdentity(identity());

        final AuthUserDto? user = await service.restoreSession();

        expect(user, isNull);
        expect(session.isAuthenticated, isFalse);
        expect(authentication.calls, <String>['getCurrentIdentity']);
      },
    );

    test('publishes an existing provider identity', () async {
      authentication.storedIdentity = identity(isEmailVerified: true);

      final AuthUserDto? user = await service.restoreSession();

      expect(user?.userId, 'user-1');
      expect(user?.isEmailVerified, isTrue);
      expect(session.identity, same(authentication.storedIdentity));
    });

    test(
      'propagates a provider failure without touching the session',
      () async {
        final AuthIdentity previous = identity(userId: 'user-9');
        session.setIdentity(previous);
        authentication.failures['getCurrentIdentity'] = Exception(
          'unavailable',
        );

        await expectLater(service.restoreSession, throwsA(isA<Exception>()));

        expect(session.identity, same(previous));
      },
    );
  });

  group('observeAuthState', () {
    test('does not publish or clear the session before an event arrives', () {
      final AuthIdentity previous = identity(userId: 'user-9');
      session.setIdentity(previous);

      service.observeAuthState();

      expect(session.identity, same(previous));
      expect(authentication.calls, isEmpty);
    });

    test('maps a signed-in identity into the session and the event', () async {
      final AuthIdentity signedIn = identity(isEmailVerified: true);
      final Future<List<AuthUserDto?>> received = service
          .observeAuthState()
          .take(1)
          .toList();
      // Let the returned stream attach to the provider stream before emitting.
      await pumpEventQueue();

      authentication.authState.add(signedIn);

      final List<AuthUserDto?> events = await received;
      expect(events, hasLength(1));
      expect(events.single?.userId, 'user-1');
      expect(events.single?.email, 'user@example.com');
      expect(events.single?.isEmailVerified, isTrue);
      expect(session.identity, same(signedIn));
      expect(session.userId, 'user-1');
      expect(session.isAuthenticated, isTrue);
    });

    test(
      'maps a null sign-out to a null event and clears the session',
      () async {
        session.setIdentity(identity(userId: 'user-9'));
        final Future<List<AuthUserDto?>> received = service
            .observeAuthState()
            .take(1)
            .toList();
        await pumpEventQueue();

        authentication.authState.add(null);

        expect(await received, <AuthUserDto?>[null]);
        expect(session.identity, isNull);
        expect(session.userId, isNull);
        expect(session.isAuthenticated, isFalse);
      },
    );

    test('publishes every provider event in order', () async {
      final AuthIdentity signedIn = identity(userId: 'user-2');
      final Future<List<AuthUserDto?>> received = service
          .observeAuthState()
          .take(2)
          .toList();
      await pumpEventQueue();

      authentication.authState.add(signedIn);
      authentication.authState.add(null);

      final List<AuthUserDto?> events = await received;
      expect(events.map((AuthUserDto? user) => user?.userId), <String?>[
        'user-2',
        null,
      ]);
      expect(session.isAuthenticated, isFalse);
    });

    test('updates the session before delivering the mapped user', () async {
      final AuthIdentity signedIn = identity();
      AuthIdentity? identityAtDelivery;
      final Future<void> delivered = service.observeAuthState().first.then((
        AuthUserDto? _,
      ) {
        identityAtDelivery = session.identity;
      });
      await pumpEventQueue();

      authentication.authState.add(signedIn);
      await delivered;

      expect(identityAtDelivery, same(signedIn));
    });

    test(
      'propagates a provider stream failure without touching the session',
      () async {
        final AuthIdentity previous = identity(userId: 'user-9');
        session.setIdentity(previous);
        final Completer<Object> failure = Completer<Object>();
        final StreamSubscription<AuthUserDto?> subscription = service
            .observeAuthState()
            .listen(
              (AuthUserDto? _) {},
              onError: (Object error) => failure.complete(error),
            );
        addTearDown(subscription.cancel);
        await pumpEventQueue();

        authentication.authState.addError(Exception('stream failed'));

        expect(await failure.future, isA<Exception>());
        expect(session.identity, same(previous));
      },
    );
  });

  group('refreshIdentity', () {
    test('republishes the refreshed identity', () async {
      session.setIdentity(identity(isEmailVerified: false));
      authentication.refreshResult = identity(isEmailVerified: true);

      final AuthUserDto user = await service.refreshIdentity();

      expect(user.isEmailVerified, isTrue);
      expect(session.identity, same(authentication.refreshResult));
    });

    test(
      'rejects an unauthenticated caller before the provider call',
      () async {
        await expectLater(
          service.refreshIdentity,
          throwsA(isA<UnauthenticatedException>()),
        );

        expect(authentication.calls, isEmpty);
      },
    );
  });

  group('register', () {
    const RegisterInput input = RegisterInput(
      email: '  new@example.com ',
      displayName: '  New User ',
      password: ' secret-1 ',
      confirmPassword: ' secret-1 ',
    );

    test(
      'registers, signs in, saves the profile, and requests verification',
      () async {
        authentication.loginResult = identity(isEmailVerified: false);

        final RegistrationResult result = await service.register(input);

        expect(authentication.calls, <String>[
          'register',
          'login',
          'requestEmailVerification',
        ]);
        expect(authentication.input('register.email'), 'new@example.com');
        expect(authentication.input('register.password'), ' secret-1 ');
        expect(authentication.input('login.email'), 'new@example.com');
        expect(profiles.saved.single.userId, 'user-1');
        expect(profiles.saved.single.displayName, 'New User');
        expect(session.userId, 'user-1');
        expect(result.user.userId, 'user-1');
        expect(
          result.verificationDispatchStatus,
          VerificationDispatchStatus.requested,
        );
      },
    );

    test(
      'skips verification when the provider reports a verified identity',
      () async {
        authentication.loginResult = identity(isEmailVerified: true);

        final RegistrationResult result = await service.register(input);

        expect(authentication.calls, <String>['register', 'login']);
        expect(
          result.verificationDispatchStatus,
          VerificationDispatchStatus.notRequired,
        );
        expect(session.isAuthenticated, isTrue);
      },
    );

    test('keeps the registration when the verification dispatch is temporarily '
        'unavailable', () async {
      authentication.loginResult = identity(isEmailVerified: false);
      authentication.failures['requestEmailVerification'] =
          const AuthenticationFailure(
            AuthenticationFailureCode.temporarilyUnavailable,
          );

      final RegistrationResult result = await service.register(input);

      expect(
        result.verificationDispatchStatus,
        VerificationDispatchStatus.pending,
      );
      expect(result.user.userId, 'user-1');
      expect(session.userId, 'user-1');
      expect(profiles.saved.single.userId, 'user-1');
    });

    test('propagates a non-temporary verification dispatch failure', () async {
      authentication.loginResult = identity(isEmailVerified: false);
      const AuthenticationFailure failure = AuthenticationFailure(
        AuthenticationFailureCode.unsupportedChallenge,
      );
      authentication.failures['requestEmailVerification'] = failure;

      await expectLater(
        () => service.register(input),
        throwsA(
          isA<AuthenticationFailure>().having(
            (AuthenticationFailure exception) => exception.code,
            'code',
            AuthenticationFailureCode.unsupportedChallenge,
          ),
        ),
      );

      expect(session.userId, 'user-1');
      expect(profiles.saved.single.userId, 'user-1');
    });

    test('propagates an untyped verification dispatch failure', () async {
      authentication.loginResult = identity(isEmailVerified: false);
      authentication.failures['requestEmailVerification'] = Exception(
        'dispatch failed',
      );

      await expectLater(
        () => service.register(input),
        throwsA(isA<Exception>()),
      );

      expect(session.userId, 'user-1');
      expect(profiles.saved.single.userId, 'user-1');
    });

    test('publishes the session only after the profile is saved', () async {
      authentication.loginResult = identity(isEmailVerified: true);
      bool authenticatedDuringSave = true;
      profiles.onSave = () => authenticatedDuringSave = session.isAuthenticated;

      await service.register(input);

      expect(authenticatedDuringSave, isFalse);
      expect(session.isAuthenticated, isTrue);
    });

    test(
      'leaves the session unauthenticated when the profile save fails',
      () async {
        authentication.loginResult = identity(isEmailVerified: true);
        profiles.saveFailure = Exception('storage failed');

        await expectLater(
          () => service.register(input),
          throwsA(isA<Exception>()),
        );

        expect(session.isAuthenticated, isFalse);
        expect(profiles.saved, isEmpty);
      },
    );

    test(
      'leaves the session unauthenticated when provider registration fails',
      () async {
        authentication.failures['register'] = Exception('already registered');

        await expectLater(
          () => service.register(input),
          throwsA(isA<Exception>()),
        );

        expect(session.isAuthenticated, isFalse);
        expect(authentication.countOf('login'), 0);
      },
    );
  });

  group('validation', () {
    test('rejects blank login fields before any provider call', () async {
      await expectLater(
        () => service.login(const LoginInput(email: '   ', password: 'secret')),
        throwsA(reasonIs(AuthValidationReason.emailRequired)),
      );
      await expectLater(
        () => service.login(
          const LoginInput(email: 'user@example.com', password: '  '),
        ),
        throwsA(reasonIs(AuthValidationReason.passwordRequired)),
      );

      expect(authentication.calls, isEmpty);
    });

    test('rejects blank and mismatched registration fields', () async {
      await expectLater(
        () => service.register(
          const RegisterInput(
            email: 'new@example.com',
            displayName: '  ',
            password: 'secret-1',
            confirmPassword: 'secret-1',
          ),
        ),
        throwsA(reasonIs(AuthValidationReason.displayNameRequired)),
      );
      await expectLater(
        () => service.register(
          const RegisterInput(
            email: 'new@example.com',
            displayName: 'New User',
            password: 'secret-1',
            confirmPassword: 'secret-2',
          ),
        ),
        throwsA(reasonIs(AuthValidationReason.passwordConfirmationMismatch)),
      );

      expect(authentication.calls, isEmpty);
      expect(profiles.saved, isEmpty);
    });

    test('requires a verification code and the current password', () async {
      session.setIdentity(identity());

      await expectLater(
        () => service.confirmEmailVerification(code: '  '),
        throwsA(reasonIs(AuthValidationReason.verificationCodeRequired)),
      );
      await expectLater(
        () => service.changePassword(
          currentPassword: '',
          newPassword: 'new-secret',
          confirmPassword: 'new-secret',
        ),
        throwsA(reasonIs(AuthValidationReason.currentPasswordRequired)),
      );

      expect(authentication.calls, isEmpty);
    });

    test('rejects a mismatched password reset confirmation', () async {
      await expectLater(
        () => service.confirmPasswordReset(
          email: 'user@example.com',
          code: '123456',
          newPassword: 'new-secret',
          confirmPassword: 'other-secret',
        ),
        throwsA(reasonIs(AuthValidationReason.passwordConfirmationMismatch)),
      );

      expect(authentication.calls, isEmpty);
    });
  });

  group('confirmEmailVerification', () {
    test('refreshes the identity after a confirmed code', () async {
      session.setIdentity(identity(isEmailVerified: false));
      authentication.refreshResult = identity(isEmailVerified: true);

      final AuthUserDto user = await service.confirmEmailVerification(
        code: ' 123456 ',
      );

      expect(authentication.calls, <String>[
        'confirmEmailVerification',
        'refreshIdentity',
      ]);
      expect(authentication.input('confirmEmailVerification.code'), '123456');
      expect(user.isEmailVerified, isTrue);
      expect(session.identity, same(authentication.refreshResult));
    });

    test(
      'rejects an unauthenticated caller before the provider call',
      () async {
        await expectLater(
          () => service.confirmEmailVerification(code: '123456'),
          throwsA(isA<UnauthenticatedException>()),
        );

        expect(authentication.calls, isEmpty);
      },
    );
  });

  group('resendEmailVerification', () {
    test('requires an authenticated user', () async {
      await expectLater(
        service.resendEmailVerification,
        throwsA(isA<UnauthenticatedException>()),
      );

      expect(authentication.calls, isEmpty);
    });

    test('requests verification for the authenticated user', () async {
      session.setIdentity(identity());

      await service.resendEmailVerification();

      expect(authentication.calls, <String>['requestEmailVerification']);
    });
  });

  group('password reset', () {
    test('requests a reset while signed out', () async {
      await service.requestPasswordReset(email: '  user@example.com ');

      expect(
        authentication.input('requestPasswordReset.email'),
        'user@example.com',
      );
      expect(authentication.countOf('login'), 0);
      expect(session.isAuthenticated, isFalse);
    });

    test('confirms a reset without signing in', () async {
      await service.confirmPasswordReset(
        email: ' user@example.com ',
        code: ' 123456 ',
        newPassword: ' new-secret ',
        confirmPassword: ' new-secret ',
      );

      expect(authentication.calls, <String>['confirmPasswordReset']);
      expect(
        authentication.input('confirmPasswordReset.email'),
        'user@example.com',
      );
      expect(authentication.input('confirmPasswordReset.code'), '123456');
      expect(
        authentication.input('confirmPasswordReset.newPassword'),
        ' new-secret ',
      );
      expect(session.isAuthenticated, isFalse);
    });
  });

  group('changePassword', () {
    test('requires an authenticated user', () async {
      await expectLater(
        () => service.changePassword(
          currentPassword: 'old-secret',
          newPassword: 'new-secret',
          confirmPassword: 'new-secret',
        ),
        throwsA(isA<UnauthenticatedException>()),
      );

      expect(authentication.calls, isEmpty);
    });

    test('delegates current and new passwords only', () async {
      final AuthIdentity previous = identity();
      session.setIdentity(previous);

      await service.changePassword(
        currentPassword: 'old-secret',
        newPassword: 'new-secret',
        confirmPassword: 'new-secret',
      );

      expect(authentication.calls, <String>['changePassword']);
      expect(
        authentication.input('changePassword.currentPassword'),
        'old-secret',
      );
      expect(authentication.input('changePassword.newPassword'), 'new-secret');
      expect(session.identity, same(previous));
    });
  });
}

/// Matcher for an [AuthValidationException] carrying [reason].
Matcher reasonIs(AuthValidationReason reason) {
  return isA<AuthValidationException>().having(
    (AuthValidationException exception) => exception.reason,
    'reason',
    reason,
  );
}

AuthIdentity identity({
  String userId = 'user-1',
  String email = 'user@example.com',
  bool isEmailVerified = false,
}) {
  return AuthIdentity(
    userId: userId,
    email: email,
    isEmailVerified: isEmailVerified,
  );
}

/// Hand-written provider double: records calls and inputs, replays canned
/// identities, and throws any failure registered in [failures] by call name.
final class FakeAuthenticationService implements IAuthenticationService {
  final List<String> calls = <String>[];
  final Map<String, Object?> inputs = <String, Object?>{};
  final Map<String, Object> failures = <String, Object>{};

  AuthIdentity? storedIdentity;
  AuthIdentity loginResult = identity();
  AuthIdentity refreshResult = identity();

  /// Provider auth-state events the fake replays to its observer.
  final StreamController<AuthIdentity?> authState =
      StreamController<AuthIdentity?>.broadcast();

  String? input(String key) => inputs[key] as String?;

  int countOf(String call) =>
      calls.where((String recorded) => recorded == call).length;

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    _record('register', <String, Object?>{
      'register.email': email,
      'register.password': password,
    });
  }

  @override
  Future<AuthIdentity> login({
    required String email,
    required String password,
  }) async {
    _record('login', <String, Object?>{
      'login.email': email,
      'login.password': password,
    });
    return loginResult;
  }

  @override
  Future<void> logout() async {
    _record('logout');
  }

  @override
  Future<AuthIdentity?> getCurrentIdentity() async {
    _record('getCurrentIdentity');
    return storedIdentity;
  }

  @override
  Stream<AuthIdentity?> observeAuthState() => authState.stream;

  @override
  Future<void> requestEmailVerification() async {
    _record('requestEmailVerification');
  }

  @override
  Future<void> confirmEmailVerification({required String code}) async {
    _record('confirmEmailVerification', <String, Object?>{
      'confirmEmailVerification.code': code,
    });
  }

  @override
  Future<AuthIdentity> refreshIdentity() async {
    _record('refreshIdentity');
    return refreshResult;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    _record('requestPasswordReset', <String, Object?>{
      'requestPasswordReset.email': email,
    });
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    _record('confirmPasswordReset', <String, Object?>{
      'confirmPasswordReset.email': email,
      'confirmPasswordReset.code': code,
      'confirmPasswordReset.newPassword': newPassword,
    });
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _record('changePassword', <String, Object?>{
      'changePassword.currentPassword': currentPassword,
      'changePassword.newPassword': newPassword,
    });
  }

  void _record(
    String call, [
    Map<String, Object?> input = const <String, Object?>{},
  ]) {
    calls.add(call);
    inputs.addAll(input);
    final Object? failure = failures[call];
    if (failure != null) {
      throw failure;
    }
  }
}

/// Hand-written profile double recording saved profiles and optional failures.
final class FakeUserProfileRepository implements IUserProfileRepository {
  final List<UserProfile> saved = <UserProfile>[];

  Object? saveFailure;
  void Function()? onSave;

  @override
  Future<UserProfile?> findByUserId(String userId) async {
    return saved.isEmpty ? null : saved.last;
  }

  @override
  Future<void> save(UserProfile profile) async {
    onSave?.call();
    final Object? failure = saveFailure;
    if (failure != null) {
      throw failure;
    }
    saved.add(profile);
  }
}
