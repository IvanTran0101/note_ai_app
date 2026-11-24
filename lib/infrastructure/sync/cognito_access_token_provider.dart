/// Cognito-backed access-token supply for the remote sync adapter.
///
/// This library is the second and last place in the app that calls Amplify
/// (the first is the auth adapter), and the only place that reads a Cognito
/// token. Provider types stop here: the sync adapter only ever sees a
/// `Future<String?>` callback, exactly like `SyncAccessTokenProvider` in
/// `http_remote_note_data_source.dart`.
///
/// The token is handed to the caller and never cached, stored, logged, or
/// copied into an exception. Amplify remains the single owner of the session.
library;

// The Cognito plugin barrel re-exports the Amplify Core auth types
// (`AuthSession`, `SignedOutException`, `CognitoAuthSession`, ...), so the
// session read needs no separate `amplify_flutter` import for those.
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

/// Reads the current Cognito access token on demand.
final class CognitoAccessTokenProvider {
  /// Creates the stateless provider over the configured Amplify singleton.
  const CognitoAccessTokenProvider();

  /// Returns the raw access-token string, or `null` when there is no session.
  ///
  /// [forceRefresh] is passed straight through to Amplify: `false` accepts the
  /// cached session, `true` makes Amplify ignore it and re-issue credentials.
  /// The sync adapter uses `true` once, after a `401`.
  ///
  /// `null` means "no usable token" and covers both provider states that mean
  /// it: a signed-out session, and a session Amplify reports as gone. Every
  /// other provider failure is left to propagate so the caller can classify it;
  /// it is never converted into a token-shaped value here.
  Future<String?> call({required bool forceRefresh}) async {
    final AuthSession session;
    try {
      session = await Amplify.Auth.fetchAuthSession(
        options: FetchAuthSessionOptions(forceRefresh: forceRefresh),
      );
    } on SignedOutException {
      return null;
    } on SessionExpiredException {
      // The refresh token is gone too, so a forced refresh cannot help: the
      // user has to sign in again. Reporting "no token" is what makes the sync
      // adapter surface `unauthorized`.
      return null;
    }

    if (!session.isSignedIn) {
      return null;
    }
    if (session is! CognitoAuthSession) {
      // The configured auth plugin is not Cognito, so it cannot mint the
      // Cognito access token this app's API authorizer expects.
      return null;
    }
    // `valueOrNull` keeps an unsuccessful token read (an unusable refresh
    // token, for example) as "no token" rather than an exception that would
    // carry provider text.
    return session.userPoolTokensResult.valueOrNull?.accessToken.raw;
  }
}
