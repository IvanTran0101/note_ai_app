import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

/// AppSync Events uses an ID token; Amplify remains the credential owner.
final class CognitoIdTokenProvider {
  const CognitoIdTokenProvider();
  Future<String?> call({required bool forceRefresh}) async {
    final AuthSession session;
    try {
      session = await Amplify.Auth.fetchAuthSession(
        options: FetchAuthSessionOptions(forceRefresh: forceRefresh),
      );
    } on SignedOutException {
      return null;
    } on SessionExpiredException {
      return null;
    }
    if (!session.isSignedIn || session is! CognitoAuthSession) return null;
    return session.userPoolTokensResult.valueOrNull?.idToken.raw;
  }
}
