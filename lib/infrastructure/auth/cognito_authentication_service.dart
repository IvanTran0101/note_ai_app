/// AWS Cognito implementation of the NoteFlow authentication boundary.
///
/// This library is the only place in the application that calls Amplify. It
/// owns the translation in both directions: provider calls in, and
/// [AuthIdentity]/[AuthenticationFailure] values out. Provider exceptions,
/// sessions, and tokens stop here — Amplify keeps the session, its tokens are
/// never read, stored, or copied into a failure, and no provider message is
/// logged or rethrown as-is.
///
/// The adapter creates no profile and performs no automatic sign-in after
/// registration: those are Application decisions.
library;

import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import '../../domain/auth/auth_identity.dart';
import '../../domain/auth/authentication_failure.dart';
import '../../domain/auth/authentication_service.dart';
import 'cognito_auth_failure_mapper.dart';
import 'cognito_identity_mapper.dart';

/// [IAuthenticationService] backed by the Amplify Auth Cognito plugin.
final class CognitoAuthenticationService implements IAuthenticationService {
  /// Creates the adapter over the Amplify singleton configured by
  /// `configureAmplifyAuthCognito`.
  const CognitoAuthenticationService();

  /// Translates Cognito user data into NoteFlow identities.
  static const CognitoIdentityMapper _identities = CognitoIdentityMapper();

  /// Translates Cognito failures into NoteFlow failure codes.
  static const CognitoAuthFailureMapper _failures = CognitoAuthFailureMapper();

  /// Whether [result] completes a registration for this adapter.
  ///
  /// The NoteFlow backend auto-confirms sign-ups, so `done` is the only next
  /// step that completes one. Any other step means the deployed user pool asks
  /// for a flow this adapter does not implement, and the caller must not treat
  /// the account as registered.
  static bool isRegistrationComplete(SignUpResult result) =>
      result.isSignUpComplete &&
      result.nextStep.signUpStep == AuthSignUpStep.done;

  /// Whether [result] completes a sign-in with no further challenge.
  static bool isSignInComplete(SignInResult result) =>
      result.isSignedIn && result.nextStep.signInStep == AuthSignInStep.done;

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    final SignUpResult result = await _guard(
      () => Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(
          userAttributes: <AuthUserAttributeKey, String>{
            AuthUserAttributeKey.email: email,
          },
        ),
      ),
    );
    if (!isRegistrationComplete(result)) {
      throw const AuthenticationFailure(
        AuthenticationFailureCode.unsupportedChallenge,
      );
    }
    // Registration deliberately stops here: no sign-in, no profile, and no
    // session. Application decides what the new account gets.
  }

  @override
  Future<AuthIdentity> login({
    required String email,
    required String password,
  }) async {
    final SignInResult result = await _guard(
      () => Amplify.Auth.signIn(username: email, password: password),
    );
    if (!isSignInComplete(result)) {
      throw const AuthenticationFailure(
        AuthenticationFailureCode.unsupportedChallenge,
      );
    }
    return _readRequiredIdentity();
  }

  @override
  Future<void> logout() async {
    final SignOutResult result = await _guard(() => Amplify.Auth.signOut());
    if (result is CognitoFailedSignOut) {
      // The provider reports that the user is still signed in; a silent success
      // here would leave the app believing the session ended.
      throw _failures.map(result.exception);
    }
  }

  @override
  Future<AuthIdentity?> getCurrentIdentity() async {
    final AuthUser? user = await _readCurrentUser();
    if (user == null) {
      return null;
    }
    return _mapIdentity(user);
  }

  @override
  Stream<AuthIdentity?> observeAuthState() {
    late final StreamController<AuthIdentity?> controller;
    StreamSubscription<AuthHubEvent>? subscription;

    Future<void> publishIdentity() async {
      try {
        final AuthIdentity? identity = await getCurrentIdentity();
        if (!controller.isClosed) {
          controller.add(identity);
        }
      } on AuthenticationFailure catch (failure) {
        // A signed-in event whose identity cannot be read is reported as an
        // error rather than as a signed-out value: claiming "no user" would
        // drop a session that may still be valid.
        if (!controller.isClosed) {
          controller.addError(failure);
        }
      }
    }

    controller = StreamController<AuthIdentity?>(
      onListen: () {
        subscription = Amplify.Hub.listen(HubChannel.Auth, (
          AuthHubEvent event,
        ) {
          switch (event.type) {
            case AuthHubEventType.signedIn:
              unawaited(publishIdentity());
            case AuthHubEventType.signedOut:
            case AuthHubEventType.sessionExpired:
            case AuthHubEventType.userDeleted:
              if (!controller.isClosed) {
                controller.add(null);
              }
          }
        });
      },
      onCancel: () async {
        // The Hub listener is cancelled with the subscription, so a screen that
        // stops listening does not leave a listener behind.
        await subscription?.cancel();
        subscription = null;
      },
    );
    return controller.stream;
  }

  @override
  Future<void> requestEmailVerification() async {
    // Sign-ups are auto-confirmed, so the code that is still outstanding is the
    // verified-email attribute, not the sign-up confirmation.
    await _guard(
      () => Amplify.Auth.sendUserAttributeVerificationCode(
        userAttributeKey: AuthUserAttributeKey.email,
      ),
    );
  }

  @override
  Future<void> confirmEmailVerification({required String code}) async {
    await _guard(
      () => Amplify.Auth.confirmUserAttribute(
        userAttributeKey: AuthUserAttributeKey.email,
        confirmationCode: code,
      ),
    );
  }

  @override
  Future<AuthIdentity> refreshIdentity() async {
    // Amplify owns the session, so the supported force-refresh call is the way
    // to make it re-issue credentials. The returned session is deliberately
    // ignored: no token is read, kept, or logged.
    await _guard(
      () => Amplify.Auth.fetchAuthSession(
        options: const FetchAuthSessionOptions(forceRefresh: true),
      ),
    );
    return _readRequiredIdentity();
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    await _guard(() => Amplify.Auth.resetPassword(username: email));
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    // The confirmation field is not part of this contract: Application already
    // checked it, and the provider only ever receives the new password.
    await _guard(
      () => Amplify.Auth.confirmResetPassword(
        username: email,
        newPassword: newPassword,
        confirmationCode: code,
      ),
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _guard(
      () => Amplify.Auth.updatePassword(
        oldPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
  }

  /// Runs one provider call and classifies the failures Amplify reports.
  ///
  /// Provider exceptions never leave the adapter: they become
  /// [AuthenticationFailure] values that carry a stable code only.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AuthException catch (error) {
      throw _failures.map(error);
    } on AmplifyException {
      // Amplify failures outside the Auth category (for example a plugin that
      // was never configured) have no more specific domain meaning.
      throw const AuthenticationFailure(AuthenticationFailureCode.unknown);
    }
  }

  /// Reads the current provider user, or `null` when nobody is signed in.
  ///
  /// Only the provider's signed-out condition becomes `null`; every other
  /// provider failure is classified and thrown.
  Future<AuthUser?> _readCurrentUser() async {
    try {
      return await Amplify.Auth.getCurrentUser();
    } on SignedOutException {
      return null;
    } on AuthException catch (error) {
      throw _failures.map(error);
    } on AmplifyException {
      throw const AuthenticationFailure(AuthenticationFailureCode.unknown);
    }
  }

  /// Reads the authenticated identity, failing when none is present.
  Future<AuthIdentity> _readRequiredIdentity() async {
    final AuthUser? user = await _readCurrentUser();
    if (user == null) {
      throw const AuthenticationFailure(
        AuthenticationFailureCode.unauthenticated,
      );
    }
    return _mapIdentity(user);
  }

  /// Fetches the provider attributes and maps them onto an identity.
  Future<AuthIdentity> _mapIdentity(AuthUser user) async {
    final List<AuthUserAttribute> attributes = await _guard(
      () => Amplify.Auth.fetchUserAttributes(),
    );
    return _identities.map(user: user, attributes: attributes);
  }
}
