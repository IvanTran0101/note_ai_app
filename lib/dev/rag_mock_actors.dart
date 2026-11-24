/// Synthetic identities, token minting, and the debug/loopback guard for the
/// explicit offline RAG mock root.
///
/// Nothing here is a real account, a provider token, or a provenance claim:
/// both actors are fixed UUIDs with `example.invalid` addresses, the JWT body is
/// unsigned (`alg: none`), and no signature is ever verified inside the mock.
/// The transport that accepts these tokens also lives only in this debug-only
/// runtime, never in the production entrypoint.
library;

import 'dart:convert';

/// The only logical host the offline RAG mock answers to.
///
/// It is intentionally not a resolvable public host: the in-process mock
/// transport refuses every other host before any request can be handled, and it
/// owns no network client of its own.
final Uri ragMockLogicalBase = Uri.parse('https://rag-mock.invalid');

/// The two synthetic users the offline RAG mock root can select.
enum RagMockUser {
  /// The primary fixture actor.
  owner,

  /// The second, fully isolated fixture actor.
  other,
}

/// One fixed synthetic actor of the offline RAG mock.
final class RagMockActor {
  const RagMockActor._({
    required this.user,
    required this.userId,
    required this.email,
  });

  /// Which synthetic user this actor is.
  final RagMockUser user;

  /// Fixed UUID used as the actor id; no real provider issued it.
  final String userId;

  /// Synthetic `example.invalid` address; no mail is ever sent to it.
  final String email;

  @override
  String toString() => 'RagMockActor(${user.name}, $email)';
}

/// The primary synthetic actor.
const RagMockActor ragMockOwner = RagMockActor._(
  user: RagMockUser.owner,
  userId: '6f6f6d6f-0000-4000-8000-000000000001',
  email: 'rag-mock-owner@example.invalid',
);

/// The second, fully isolated synthetic actor.
const RagMockActor ragMockOther = RagMockActor._(
  user: RagMockUser.other,
  userId: '6f6f6d6f-0000-4000-8000-000000000002',
  email: 'rag-mock-other@example.invalid',
);

/// The fixed actor for [user].
RagMockActor ragMockActorFor(RagMockUser user) => switch (user) {
  RagMockUser.owner => ragMockOwner,
  RagMockUser.other => ragMockOther,
};

/// Resolves the configured `RAG_MOCK_USER` value, refusing anything else.
RagMockUser resolveRagMockUser(String configured) => switch (configured) {
  'owner' => RagMockUser.owner,
  'other' => RagMockUser.other,
  _ => throw StateError('Use --dart-define=RAG_MOCK_USER=owner or other.'),
};

/// The actor selected by `--dart-define=RAG_MOCK_USER`, defaulting to owner.
RagMockActor ragMockActorFromEnvironment() => ragMockActorFor(
  resolveRagMockUser(
    const String.fromEnvironment('RAG_MOCK_USER', defaultValue: 'owner'),
  ),
);

/// The actor whose fixed [userId] matches [subject], or null.
RagMockActor? ragMockActorFromUserId(String? subject) {
  if (subject == ragMockOwner.userId) return ragMockOwner;
  if (subject == ragMockOther.userId) return ragMockOther;
  return null;
}

/// Whether [host] is a loopback host the Web debug root may be served from.
bool ragMockIsLoopbackHost(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

/// The reason the current runtime cannot host the offline RAG mock, or null.
///
/// This is a pure helper so the root and its test share one implementation of
/// the two hard gates (debug build, loopback on Web) instead of duplicating
/// them.
String? ragMockGuardProblem({
  required bool isDebugMode,
  required bool isWeb,
  required Uri baseUri,
}) {
  if (!isDebugMode) {
    return 'The offline RAG mock requires a debug build.';
  }
  if (isWeb && !ragMockIsLoopbackHost(baseUri.host)) {
    return 'The offline RAG mock must be served on a loopback Web host.';
  }
  return null;
}

/// Throws a [StateError] when [ragMockGuardProblem] refuses the runtime.
void requireRagMockRuntime({
  required bool isDebugMode,
  required bool isWeb,
  required Uri baseUri,
}) {
  final String? problem = ragMockGuardProblem(
    isDebugMode: isDebugMode,
    isWeb: isWeb,
    baseUri: baseUri,
  );
  if (problem != null) {
    throw StateError(problem);
  }
}

/// Mints the unsigned synthetic access token for [actor].
///
/// The claims are exactly the ones the real RAG and sync adapters read
/// (`sub`, `token_use`, `exp`), so the very same token-validation code paths run
/// against the mock. The signature is the literal `rag-mock`; nothing verifies
/// it, and the token must never be presented to a real backend.
String ragMockAccessToken(RagMockActor actor, {DateTime? now}) {
  final DateTime issued = (now ?? DateTime.now()).toUtc();
  final int expires =
      issued.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  final String header = _base64UrlJson(<String, Object?>{
    'alg': 'none',
    'typ': 'JWT',
  });
  final String payload = _base64UrlJson(<String, Object?>{
    'sub': actor.userId,
    'email': actor.email,
    'token_use': 'access',
    'iss': 'rag-mock.invalid',
    'exp': expires,
  });
  return '$header.$payload.rag-mock';
}

/// Reads only the `sub` claim of [token], or null when it is not decodable.
///
/// This is deliberately not a verification: the offline mock has no secret and
/// makes no authenticity claim.
String? ragMockJwtSubject(String token) {
  final List<String> parts = token.split('.');
  if (parts.length != 3) return null;
  final Object? payload = _decodeSegment(parts[1]);
  if (payload is! Map<String, dynamic>) return null;
  final Object? subject = payload['sub'];
  return subject is String && subject.isNotEmpty ? subject : null;
}

String _base64UrlJson(Map<String, Object?> value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Object? _decodeSegment(String segment) {
  try {
    return jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segment))),
    );
  } on Object {
    return null;
  }
}
