/// Maps Cognito user data onto the provider-neutral NoteFlow identity.
///
/// The mapper is deliberately free of Amplify calls, sessions, and tokens: it
/// only translates values the adapter already fetched. Provider-specific
/// attribute names, the provider's `email_verified` encoding, and the decision
/// of what counts as a usable identity all stop here, so the Domain boundary
/// receives an [AuthIdentity] or an [AuthenticationFailure] and nothing else.
library;

import 'package:amplify_flutter/amplify_flutter.dart';

import '../../domain/auth/auth_identity.dart';
import '../../domain/auth/authentication_failure.dart';

/// Builds [AuthIdentity] values from Cognito user data.
final class CognitoIdentityMapper {
  /// Creates the stateless mapper.
  const CognitoIdentityMapper();

  /// The failure used when Cognito does not describe a usable identity.
  ///
  /// It carries no provider text, so it is safe to surface and log.
  static const AuthenticationFailure _identityUnavailable =
      AuthenticationFailure(AuthenticationFailureCode.identityUnavailable);

  /// Maps [user] and its fetched [attributes] onto an [AuthIdentity].
  ///
  /// The identity uses [AuthUser.userId] — the stable Cognito user pool `sub`
  /// claim — and never the email or username, so an email change cannot
  /// re-identify the account.
  ///
  /// Throws [AuthenticationFailure] with
  /// [AuthenticationFailureCode.identityUnavailable] when the user id, the
  /// email attribute, or the email-verification attribute is missing or
  /// unusable. Failures carry no attribute value, provider message, or token.
  AuthIdentity map({
    required AuthUser user,
    required List<AuthUserAttribute> attributes,
  }) {
    final String userId = user.userId.trim();
    if (userId.isEmpty) {
      throw _identityUnavailable;
    }

    String? email;
    bool? isEmailVerified;
    for (final AuthUserAttribute attribute in attributes) {
      final AuthUserAttributeKey key = attribute.userAttributeKey;
      if (key == AuthUserAttributeKey.email) {
        email = _readEmail(attribute.value);
      } else if (key == AuthUserAttributeKey.emailVerified) {
        isEmailVerified = _readEmailVerified(attribute.value);
      }
    }

    if (email == null || isEmailVerified == null) {
      throw _identityUnavailable;
    }
    return AuthIdentity(
      userId: userId,
      email: email,
      isEmailVerified: isEmailVerified,
    );
  }

  /// Returns the normalized email, or `null` when Cognito sent none.
  String? _readEmail(String value) {
    final String email = value.trim();
    return email.isEmpty ? null : email;
  }

  /// Reads Cognito's `email_verified` flag.
  ///
  /// Cognito reports the flag as the string `'true'` or `'false'`; anything
  /// else means the identity cannot be described honestly.
  bool _readEmailVerified(String value) {
    switch (value.trim().toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
      default:
        throw _identityUnavailable;
    }
  }
}
