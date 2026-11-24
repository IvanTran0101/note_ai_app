import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

import 'dart:async';

import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/auth/cognito_authentication_service.dart';

/// Deterministic coverage for the adapter's provider-result decisions.
///
/// The adapter's provider calls cannot run without a configured Cognito user
/// pool, so only the step rules that decide "completed" versus "unsupported
/// challenge" are exercised here. Everything else in the adapter is covered by
/// the mapper tests plus the manual smoke checklist reported with this change.
void main() {
  test(
    'late signed-in identity cannot republish an account after sign-out',
    () async {
      final hub = StreamController<AuthHubEvent>.broadcast();
      Amplify.Hub.addChannel(HubChannel.Auth, hub.stream);
      addTearDown(hub.close);
      final pending = Completer<AuthIdentity?>();
      final service = CognitoAuthenticationService(
        observedIdentityReader: () => pending.future,
      );
      final events = <AuthIdentity?>[];
      final subscription = service.observeAuthState().listen(events.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      hub.add(
        AuthHubEvent.signedIn(
          const AuthUser(
            userId: 'actor',
            username: 'test',
            signInDetails: CognitoSignInDetails.apiBased(username: 'test'),
          ),
        ),
      );
      await pumpEventQueue();
      hub.add(AuthHubEvent.signedOut());
      await pumpEventQueue();
      pending.complete(
        AuthIdentity(
          userId: 'actor',
          email: 'test@example.invalid',
          isEmailVerified: false,
        ),
      );
      await pumpEventQueue();
      expect(events, <AuthIdentity?>[null]);
    },
  );

  group('CognitoAuthenticationService.isRegistrationComplete', () {
    test('accepts a sign-up that Cognito completed', () {
      expect(
        CognitoAuthenticationService.isRegistrationComplete(
          const SignUpResult(
            isSignUpComplete: true,
            nextStep: AuthNextSignUpStep(signUpStep: AuthSignUpStep.done),
          ),
        ),
        isTrue,
      );
    });

    test('rejects a sign-up confirmation challenge', () {
      expect(
        CognitoAuthenticationService.isRegistrationComplete(
          const SignUpResult(
            isSignUpComplete: false,
            nextStep: AuthNextSignUpStep(
              signUpStep: AuthSignUpStep.confirmSignUp,
            ),
          ),
        ),
        isFalse,
      );
    });

    test('rejects an incomplete sign-up that reports the done step', () {
      expect(
        CognitoAuthenticationService.isRegistrationComplete(
          const SignUpResult(
            isSignUpComplete: false,
            nextStep: AuthNextSignUpStep(signUpStep: AuthSignUpStep.done),
          ),
        ),
        isFalse,
      );
    });
  });

  group('CognitoAuthenticationService.isSignInComplete', () {
    test('accepts a signed-in result with no further step', () {
      expect(
        CognitoAuthenticationService.isSignInComplete(
          const SignInResult(
            isSignedIn: true,
            nextStep: AuthNextSignInStep(signInStep: AuthSignInStep.done),
          ),
        ),
        isTrue,
      );
    });

    test('rejects a sign-in that still needs a challenge', () {
      expect(
        CognitoAuthenticationService.isSignInComplete(
          const SignInResult(
            isSignedIn: true,
            nextStep: AuthNextSignInStep(
              signInStep: AuthSignInStep.confirmSignInWithSmsMfaCode,
            ),
          ),
        ),
        isFalse,
      );
    });

    test('rejects a result that is not signed in', () {
      expect(
        CognitoAuthenticationService.isSignInComplete(
          const SignInResult(
            isSignedIn: false,
            nextStep: AuthNextSignInStep(signInStep: AuthSignInStep.done),
          ),
        ),
        isFalse,
      );
    });
  });
}
