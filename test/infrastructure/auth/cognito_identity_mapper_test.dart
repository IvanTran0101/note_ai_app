import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/auth/authentication_failure.dart';
import 'package:note_ai_app/infrastructure/auth/cognito_identity_mapper.dart';

void main() {
  const CognitoIdentityMapper mapper = CognitoIdentityMapper();
  const String email = 'ada@example.com';

  AuthUser buildUser({String userId = 'cognito-sub-1'}) {
    return AuthUser(
      userId: userId,
      username: email,
      signInDetails: const CognitoSignInDetails.apiBased(username: email),
    );
  }

  AuthUserAttribute emailAttribute(String value) {
    return AuthUserAttribute(
      userAttributeKey: AuthUserAttributeKey.email,
      value: value,
    );
  }

  AuthUserAttribute verifiedAttribute(String value) {
    return AuthUserAttribute(
      userAttributeKey: AuthUserAttributeKey.emailVerified,
      value: value,
    );
  }

  Matcher throwsIdentityUnavailable() {
    return throwsA(
      isA<AuthenticationFailure>().having(
        (AuthenticationFailure failure) => failure.code,
        'code',
        AuthenticationFailureCode.identityUnavailable,
      ),
    );
  }

  group('CognitoIdentityMapper', () {
    test('uses the stable Cognito user id instead of the email', () {
      final AuthIdentity identity = mapper.map(
        user: buildUser(userId: 'cognito-sub-42'),
        attributes: <AuthUserAttribute>[
          emailAttribute(email),
          verifiedAttribute('true'),
        ],
      );

      expect(identity.userId, 'cognito-sub-42');
      expect(identity.userId, isNot(email));
    });

    test('maps the email and a verified email flag', () {
      final AuthIdentity identity = mapper.map(
        user: buildUser(),
        attributes: <AuthUserAttribute>[
          emailAttribute(email),
          verifiedAttribute('true'),
        ],
      );

      expect(identity.email, email);
      expect(identity.isEmailVerified, isTrue);
    });

    test('maps an unverified email flag', () {
      final AuthIdentity identity = mapper.map(
        user: buildUser(),
        attributes: <AuthUserAttribute>[
          emailAttribute(email),
          verifiedAttribute('false'),
        ],
      );

      expect(identity.email, email);
      expect(identity.isEmailVerified, isFalse);
    });

    test('normalizes surrounding whitespace in the fetched values', () {
      final AuthIdentity identity = mapper.map(
        user: buildUser(userId: ' cognito-sub-1 '),
        attributes: <AuthUserAttribute>[
          emailAttribute('  $email  '),
          verifiedAttribute(' TRUE '),
        ],
      );

      expect(identity.userId, 'cognito-sub-1');
      expect(identity.email, email);
      expect(identity.isEmailVerified, isTrue);
    });

    test('ignores attributes that are not part of the identity', () {
      final AuthIdentity identity = mapper.map(
        user: buildUser(),
        attributes: <AuthUserAttribute>[
          const AuthUserAttribute(
            userAttributeKey: AuthUserAttributeKey.familyName,
            value: 'Lovelace',
          ),
          emailAttribute(email),
          verifiedAttribute('false'),
        ],
      );

      expect(identity.email, email);
      expect(identity.isEmailVerified, isFalse);
    });
  });

  group('CognitoIdentityMapper failures', () {
    test('rejects a blank user id', () {
      expect(
        () => mapper.map(
          user: buildUser(userId: '   '),
          attributes: <AuthUserAttribute>[
            emailAttribute(email),
            verifiedAttribute('true'),
          ],
        ),
        throwsIdentityUnavailable(),
      );
    });

    test('rejects a missing email attribute', () {
      expect(
        () => mapper.map(
          user: buildUser(),
          attributes: <AuthUserAttribute>[verifiedAttribute('true')],
        ),
        throwsIdentityUnavailable(),
      );
    });

    test('rejects a blank email attribute', () {
      expect(
        () => mapper.map(
          user: buildUser(),
          attributes: <AuthUserAttribute>[
            emailAttribute('   '),
            verifiedAttribute('true'),
          ],
        ),
        throwsIdentityUnavailable(),
      );
    });

    test('rejects a missing email verification attribute', () {
      expect(
        () => mapper.map(
          user: buildUser(),
          attributes: <AuthUserAttribute>[emailAttribute(email)],
        ),
        throwsIdentityUnavailable(),
      );
    });

    test('rejects an email verification value that is not a flag', () {
      expect(
        () => mapper.map(
          user: buildUser(),
          attributes: <AuthUserAttribute>[
            emailAttribute(email),
            verifiedAttribute('yes'),
          ],
        ),
        throwsIdentityUnavailable(),
      );
    });

    test('rejects an empty attribute list', () {
      expect(
        () => mapper.map(user: buildUser(), attributes: const []),
        throwsIdentityUnavailable(),
      );
    });

    test('keeps provider values out of the failure', () {
      try {
        mapper.map(
          user: buildUser(),
          attributes: <AuthUserAttribute>[
            emailAttribute(email),
            verifiedAttribute('yes'),
          ],
        );
        fail('expected an AuthenticationFailure');
      } on AuthenticationFailure catch (failure) {
        expect(
          failure.toString(),
          'AuthenticationFailure(identityUnavailable)',
        );
        expect(failure.toString(), isNot(contains(email)));
      }
    });
  });
}
