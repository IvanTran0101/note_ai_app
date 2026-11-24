part of 'rag_http_gateway.dart';

// The token claims one egress decision needs.
//
// Reading them is one responsibility, separate from the request lifecycle:
// a wrong account, an ID token, or an expired token must never leave the
// process, and the backend still owns the signature check.

/// The three claims one egress decision needs; the signature is the backend's.
final class _TokenClaims {
  const _TokenClaims({
    required this.subject,
    required this.isAccessToken,
    required this.isLive,
  });

  /// Reads the claims of [token], or null when it is not a decodable JWT.
  ///
  /// Only `sub`, `token_use`, and `exp` are read, and nothing is logged or
  /// thrown: a malformed token is simply not authorized.
  static _TokenClaims? read(String token, DateTime now) {
    if (token.length > _maxTokenChars) {
      return null;
    }
    final List<String> parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final Object? payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) {
        return null;
      }
      final Object? subject = payload['sub'];
      final Object? use = payload['token_use'];
      final Object? expires = payload['exp'];
      if (subject is! String ||
          subject.isEmpty ||
          use is! String ||
          expires is! int ||
          expires < 0) {
        return null;
      }
      return _TokenClaims(
        subject: subject,
        isAccessToken: use == 'access',
        isLive: DateTime.fromMillisecondsSinceEpoch(
          expires * 1000,
          isUtc: true,
        ).isAfter(now),
      );
    } on Object {
      return null;
    }
  }

  final String subject;
  final bool isAccessToken;
  final bool isLive;
}

/// Anything longer than any real access token is not decoded at all.
const int _maxTokenChars = 8192;
