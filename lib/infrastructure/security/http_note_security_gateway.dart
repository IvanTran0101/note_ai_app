import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/notes/note_access.dart';
import '../../application/notes/note_security_gateway.dart';
import '../../application/sync/sync_snapshot.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_identity.dart';
import '../sync/sync_http_mapper.dart';
import 'note_jwt_subject.dart';

final class _Proof {
  const _Proof(this.token, this.lease);
  final String token;
  final NoteUnlockLease lease;
  @override
  String toString() => '<note proof redacted>';
}

/// Grant strings are transient and owned only here, never returned in app DTOs.
final class HttpNoteSecurityGateway implements INoteSecurityGateway {
  HttpNoteSecurityGateway({
    required this.baseUri,
    required this.accountId,
    required this.tokenProvider,
    required this.isCurrentSession,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
  }
  final Uri baseUri;
  final String accountId;
  final Future<String?> Function({required bool forceRefresh}) tokenProvider;
  final bool Function() isCurrentSession;
  final http.Client _client;
  final bool _ownsClient;
  final _proofs = <String, _Proof>{};
  int _generation = 0;

  @override
  bool hasAuthority(String id, NoteProtection p, NoteOperation operation) {
    final proof = _proofs[id];
    return isCurrentSession() &&
        proof != null &&
        proof.lease.protection == p &&
        proof.lease.expiresAt.isAfter(DateTime.now()) &&
        proof.lease.operations.contains(operation);
  }

  /// Infrastructure transport bridge; callers still enforce their own fresh
  /// session/snapshot guard and the server intersects current ACL every time.
  String? grantHeader(String id, NoteProtection p, NoteOperation operation) {
    if (!isCurrentSession()) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    if (!p.enabled) return null;
    if (!hasAuthority(id, p, operation)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
    }
    return _proofs[id]!.token;
  }

  @override
  void invalidate(String? id) {
    _generation++;
    if (id == null) {
      _proofs.clear();
    } else {
      _proofs.remove(id);
    }
  }

  void close() {
    invalidate(null);
    if (_ownsClient) _client.close();
  }

  @override
  Future<NoteProtection> metadata(String id) async =>
      _metadata(await _request(id, 'protection'));
  @override
  Future<SyncNoteSnapshot> content(String id) async => decodeSyncNoteSnapshot(
    await _request(id, 'content', operation: NoteOperation.read),
    authorizedContent: true,
  );
  @override
  Future<NoteProtection> enable(
    String id,
    String password,
    int revision,
  ) async => _metadata(
    await _request(
      id,
      'protection/enable',
      body: {'password': password, 'expectedContentRevision': revision},
    ),
  );
  @override
  Future<NoteUnlockLease> unlock(
    String id,
    String password,
    Set<NoteOperation> operations,
  ) async => _lease(
    id,
    await _request(
      id,
      'protection/unlock',
      body: {
        'password': password,
        'operations': operations.map((o) => o.name).toList(),
      },
    ),
  );
  @override
  Future<NoteProtection> change(
    String id,
    String password,
    String next,
    int epoch,
  ) async {
    final result = _metadata(
      await _request(
        id,
        'protection/change',
        operation: NoteOperation.manage,
        body: {
          'currentPassword': password,
          'newPassword': next,
          'expectedProtectionRevision': epoch,
        },
      ),
    );
    invalidate(id);
    return result;
  }

  @override
  Future<NoteProtection> disable(String id, String password, int epoch) async {
    final result = _metadata(
      await _request(
        id,
        'protection/disable',
        operation: NoteOperation.manage,
        body: {
          'currentPassword': password,
          'expectedProtectionRevision': epoch,
        },
      ),
    );
    invalidate(id);
    return result;
  }

  @override
  Future<NoteRecoveryChallenge> requestRecovery(String id) async {
    final r = await _request(id, 'protection/reset/request', body: {});
    return _decode(
      () => NoteRecoveryChallenge(
        r['challengeId'] as String,
        _expiry(r['expiresAt']),
      ),
    );
  }

  @override
  Future<NoteUnlockLease> confirmRecovery(
    String id,
    String challengeId,
    String code,
    String password,
  ) async => _lease(
    id,
    await _request(
      id,
      'protection/reset/confirm',
      body: {'challengeId': challengeId, 'code': code, 'newPassword': password},
    ),
  );

  NoteUnlockLease _lease(String id, Map<String, Object?> r) => _decode(() {
    final token = r['grant'];
    if (token is! String || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    final raw = r['operations'] as List;
    final operations = raw
        .map((o) => NoteOperation.values.firstWhere((v) => v.name == o))
        .toSet();
    final lease = NoteUnlockLease(
      protection: _metadata(r),
      operations: operations,
      expiresAt: _expiry(r['expiresAt']),
    );
    if (!lease.protection.enabled || operations.isEmpty) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    _proofs[id] = _Proof(token, lease);
    return lease;
  });

  static T _decode<T>(T Function() read) {
    try {
      return read();
    } on NoteSecurityFailure {
      rethrow;
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
  }

  static NoteProtection _metadata(Map<String, Object?> r) => _decode(
    () => NoteProtection(
      enabled: r['enabled'] as bool,
      revision: r['revision'] as int,
    ),
  );
  static DateTime _expiry(Object? value) {
    if (value is! int) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    if (!expiry.isAfter(DateTime.now()) ||
        expiry.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.expired);
    }
    return expiry;
  }

  Future<Map<String, Object?>> _request(
    String id,
    String action, {
    Map<String, Object?>? body,
    NoteOperation? operation,
  }) async {
    final start = _generation;
    void requireSession() {
      if (start != _generation || !isCurrentSession()) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
      }
    }

    try {
      requireSession();
      String? token = await tokenProvider(forceRefresh: false)
          .timeout(const Duration(seconds: 15));
      requireSession();
      if (token == null || noteJwtSubject(token) != accountId) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      Future<http.Response> send(String token) async {
        requireSession();
        final grant = operation == null ? null : _proofs[id];
        if (operation != null &&
            grant != null &&
            !hasAuthority(id, grant.lease.protection, operation)) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.expired);
        }
        final prefix = baseUri.path.endsWith('/')
            ? baseUri.path
            : '${baseUri.path}/';
        final request = http.Request(
          body == null ? 'GET' : 'POST',
          baseUri.replace(
            path:
                '${prefix}notes/${Uri.encodeComponent(NoteIdentity.resolve(id, accountId).noteId)}/$action',
            queryParameters: {
              if (NoteIdentity.resolve(id, accountId).ownerId != accountId)
                'ownerId': NoteIdentity.resolve(id, accountId).ownerId,
              if (action == 'content') 'wireVersion': '2',
            },
          ),
        );
        request.followRedirects = false;
        request.maxRedirects = 0;
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        });
        if (grant != null) request.headers['X-Note-Unlock-Grant'] = grant.token;
        if (body != null) request.bodyBytes = utf8.encode(jsonEncode(body));
        final response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 30));
        requireSession();
        return response;
      }

      var response = await send(token);
      if (response.statusCode == 401) {
        token = await tokenProvider(forceRefresh: true)
            .timeout(const Duration(seconds: 15));
        requireSession();
        if (token == null || noteJwtSubject(token) != accountId) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
        }
        response = await send(token);
      }
      if (response.bodyBytes.length > 512 * 1024) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
      }
      final r = Map<String, Object?>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
      if (response.statusCode != 200) {
        throw NoteSecurityFailure(_failure(r['code']));
      }
      return r;
    } on NoteSecurityFailure {
      rethrow;
    } on TimeoutException {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.network);
    } on http.ClientException {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.network);
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
  }

  static NoteSecurityFailureCode _failure(Object? code) => switch (code) {
    'NOTE_LOCKED' => NoteSecurityFailureCode.locked,
    'NOTE_PASSWORD_INVALID' => NoteSecurityFailureCode.invalidPassword,
    'NOTE_GRANT_EXPIRED' => NoteSecurityFailureCode.expired,
    'NOTE_SECURITY_STALE' => NoteSecurityFailureCode.staleRevision,
    'NOTE_SECURITY_INPUT_INVALID' => NoteSecurityFailureCode.invalidInput,
    'NOTE_ACCESS_DENIED' || 'UNAUTHORIZED' => NoteSecurityFailureCode.denied,
    'NOTE_CHALLENGE_INVALID' => NoteSecurityFailureCode.invalidChallenge,
    'NOTE_RATE_LIMITED' => NoteSecurityFailureCode.rateLimited,
    _ => NoteSecurityFailureCode.unavailable,
  };
}
