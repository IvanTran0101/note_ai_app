import 'dart:convert';

/// Client consistency only; API Gateway performs the actual JWT verification.
String? noteJwtSubject(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return payload is Map && payload['sub'] is String
        ? payload['sub'] as String
        : null;
  } on Object {
    return null;
  }
}
