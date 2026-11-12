import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/notes/sharing_gateway.dart';
import '../../domain/notes/note_identity.dart';
import '../../domain/notes/note_share_grant.dart';
import '../security/note_jwt_subject.dart';
import '../sync/share_wire_codec.dart';

final class HttpShareGateway implements ISharingGateway {
  HttpShareGateway({
    required this.baseUri,
    required this.actorId,
    required this.tokenProvider,
    required this.isCurrent,
    required this.grantHeader,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final Uri baseUri;
  final String actorId;
  final Future<String?> Function({required bool forceRefresh}) tokenProvider;
  final bool Function() isCurrent;
  final Future<String?> Function(NoteIdentity) grantHeader;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;
  void _live() {
    if (_closed || !isCurrent()) {
      throw const ShareFailure(ShareFailureCode.sessionChanged);
    }
  }

  @override
  Future<List<NoteShareGrant>> list(NoteIdentity note) async {
    final r = await _request(note);
    final rows = _decode(
      () => (r['shares'] as List)
          .map(ShareWireCodec.decode)
          .toList(growable: false),
    );
    if (rows.any((s) => s.note != note)) {
      throw const ShareFailure(ShareFailureCode.unavailable);
    }
    return rows;
  }

  @override
  Future<NoteShareGrant> apply(NoteIdentity note, ShareCommand command) async {
    final r = await _request(
      note,
      body: {
        'requestId': command.requestId,
        'action': command.action,
        'expectedAccessRevision': command.expectedAccessRevision,
        if (command.email != null) 'email': command.email,
        if (command.recipientId != null) 'recipientId': command.recipientId,
        if (command.role != null) 'role': command.role!.name,
      },
    );
    final share = _decode(() => ShareWireCodec.decode(r['share']));
    if (share.note != note) {
      throw const ShareFailure(ShareFailureCode.unavailable);
    }
    return share;
  }

  Future<Map<String, Object?>> _request(
    NoteIdentity note, {
    Map<String, Object?>? body,
  }) async {
    try {
      _live();
      if (baseUri.scheme != 'https' ||
          baseUri.host.isEmpty ||
          baseUri.hasQuery ||
          baseUri.hasFragment ||
          baseUri.userInfo.isNotEmpty ||
          note.ownerId != actorId) {
        throw const ShareFailure(ShareFailureCode.denied);
      }
      final grant = await grantHeader(note);
      _live();
      Future<http.Response> send(bool refresh) async {
        final token = await tokenProvider(forceRefresh: refresh)
            .timeout(const Duration(seconds: 15));
        _live();
        if (token == null || noteJwtSubject(token) != actorId) {
          throw const ShareFailure(ShareFailureCode.denied);
        }
        final prefix = baseUri.path.endsWith('/')
            ? baseUri.path
            : '${baseUri.path}/';
        final request = http.Request(
          body == null ? 'GET' : 'POST',
          baseUri.replace(
            path: '${prefix}notes/${Uri.encodeComponent(note.noteId)}/shares',
          ),
        );
        request.followRedirects = false;
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'X-Note-Unlock-Grant': ?grant,
        });
        if (body != null) request.body = jsonEncode(body);
        final response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 30));
        _live();
        return response;
      }

      var response = await send(false);
      if (response.statusCode == 401) response = await send(true);
      if (response.bodyBytes.length > 65536) {
        throw const ShareFailure(ShareFailureCode.unavailable);
      }
      final r = Map<String, Object?>.from(jsonDecode(response.body) as Map);
      if (response.statusCode != 200) throw ShareFailure(_failure(r['code']));
      return r;
    } on ShareFailure {
      rethrow;
    } on TimeoutException {
      throw const ShareFailure(ShareFailureCode.network);
    } on http.ClientException {
      throw const ShareFailure(ShareFailureCode.network);
    } on Object {
      throw const ShareFailure(ShareFailureCode.unavailable);
    }
  }

  static ShareFailureCode _failure(Object? code) => switch (code) {
    'SHARE_RECIPIENT_UNAVAILABLE' => ShareFailureCode.recipientUnavailable,
    'SHARE_DUPLICATE' => ShareFailureCode.duplicate,
    'SHARE_SELF_SHARE' => ShareFailureCode.selfShare,
    'SHARE_STALE_ACCESS' ||
    'NOTE_SECURITY_STALE' => ShareFailureCode.staleAccess,
    'SHARE_LIMIT' => ShareFailureCode.limit,
    'SHARE_INVALID_INPUT' => ShareFailureCode.invalidInput,
    'NOTE_ACCESS_DENIED' || 'NOTE_LOCKED' => ShareFailureCode.denied,
    _ => ShareFailureCode.unavailable,
  };
  static T _decode<T>(T Function() read) {
    try {
      return read();
    } on Object {
      throw const ShareFailure(ShareFailureCode.unavailable);
    }
  }

  void close() {
    _closed = true;
    if (_ownsClient) _client.close();
  }
}
