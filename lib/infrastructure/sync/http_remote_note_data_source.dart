/// Cross-platform HTTP adapter for the remote note sync port.
///
/// One implementation serves iOS, macOS, and Web: `package:http` picks the
/// platform client, so this library never imports `dart:io` and needs no
/// conditional import per platform.
///
/// The adapter owns transport only. It attaches credentials, routes requests,
/// and classifies failures; every wire shape is decoded by
/// `sync_http_mapper.dart`, and every value crossing the boundary is an
/// Application contract type. It never logs: an access token, note content, a
/// request body, a cursor in a query string, and raw exception text are all
/// kept out of thrown values because the only field a [SyncFailure] carries is
/// whatever safe message the mapper chose to expose.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../application/sync/remote_note_data_source.dart';
import '../../application/sync/shared_label_projection_source.dart';
import '../../application/sync/local_note_state.dart';
import '../../application/sync/sync_failure.dart';
import '../../application/sync/sync_mutation.dart';
import '../../application/sync/sync_result.dart';
import '../../application/sync/sync_snapshot.dart';
import 'sync_http_mapper.dart';
import '../../application/notes/note_access.dart';

part 'http_sync_transport.dart';

/// Supplies the bearer token for one sync call.
///
/// `forceRefresh` asks the provider to ignore any cached session and re-issue
/// credentials. Returning `null` means "no usable token"; the adapter turns
/// that into [SyncErrorCode.unauthorized] without issuing a request.
///
/// `CognitoAccessTokenProvider` in `cognito_access_token_provider.dart` is the
/// production implementation.
typedef SyncAccessTokenProvider = Future<String?> Function({
  required bool forceRefresh,
});

/// [IRemoteNoteDataSource] over the frozen M1.0 HTTP contract.
///
/// Routes: `POST /sync/mutations` (one mutation per request, idempotent by
/// `mutationId`) and `GET /sync/changes` (opaque cursor paging).
final class HttpRemoteNoteDataSource
    implements
        IRemoteNoteDataSource,
        ISharedLabelProjectionSource,
        ISyncWireNegotiation {
  /// Creates the adapter over [baseUri], for example
  /// `https://abc123.execute-api.ap-southeast-1.amazonaws.com/prod`.
  ///
  /// [client] is optional: when it is omitted the adapter creates and owns one,
  /// and [close] releases it. An injected client is borrowed for its lifetime
  /// and is never closed here. [timeout] bounds one whole send-and-read; it
  /// defaults to 30 seconds.
  factory HttpRemoteNoteDataSource({
    required Uri baseUri,
    required SyncAccessTokenProvider tokenProvider,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
    String? expectedAccountUserId,
    Future<String?> Function(SyncMutation)? mutationGrant,
    void Function()? requireSession,
    bool labelsEnabled = false,
    bool documentsEnabled = false,
    String? Function(LocalNoteState)? projectionGrant,
  }) {
    return HttpRemoteNoteDataSource._(
      baseUri: baseUri,
      tokenProvider: tokenProvider,
      client: client ?? http.Client(),
      ownsClient: client == null,
      timeout: timeout,
      expectedAccountUserId: expectedAccountUserId,
      mutationGrant: mutationGrant,
      requireSession: requireSession,
      labelsEnabled: labelsEnabled,
      documentsEnabled: documentsEnabled,
      projectionGrant: projectionGrant,
    );
  }

  /// Assigns the collaborators and the client-ownership decision resolved by
  /// the public factory.
  HttpRemoteNoteDataSource._({
    required this._baseUri,
    required this._tokenProvider,
    required this._client,
    required this._ownsClient,
    required this._timeout,
    required this._expectedAccountUserId,
    required this.mutationGrant,
    required this.requireSession,
    required this.labelsEnabled,
    required this.documentsEnabled,
    required this.projectionGrant,
  });

  /// Change-feed route.
  static const String _changesPath = 'sync/changes';

  /// The only media type this adapter sends and accepts.
  static const String _jsonContentType = 'application/json';

  final Uri _baseUri;
  final SyncAccessTokenProvider _tokenProvider;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;
  final String? _expectedAccountUserId;
  final Future<String?> Function(SyncMutation)? mutationGrant;
  final void Function()? requireSession;
  final bool labelsEnabled;
  final bool documentsEnabled;
  int? _negotiatedVersion;
  final String? Function(LocalNoteState)? projectionGrant;

  @override
  Future<int> negotiateWireVersion() => _classify(() async {
    final legacyVersion = labelsEnabled ? 2 : 1;
    if (!documentsEnabled) return _negotiatedVersion = legacyVersion;
    final response = await _send(
      method: 'GET',
      uri: _endpoint('sync/v3/changes', query: {'limit': '1'}),
    );
    if (const [404, 405, 501].contains(response.statusCode)) {
      return _negotiatedVersion = legacyVersion;
    }
    if (!_isSuccess(response.statusCode)) throw _decodeError(response);
    final page = decodeChangesPage(_readBody(response));
    if (page.wireVersion != 3) {
      throw const FormatException('V3 capability negotiation failed.');
    }
    // This probe is intentionally not applied and never advances the cursor.
    return _negotiatedVersion = 3;
  });

  @override
  Future<List<SyncNoteSnapshot>> refreshLabels(
    Iterable<LocalNoteState> notes,
  ) => _classify(() async {
    final refs = notes
        .where(
          (n) =>
              !n.isDeleted &&
              n.contentAvailable &&
              (n.share?.isActive == true || n.protection.enabled),
        )
        .toList();
    final snapshots = <SyncNoteSnapshot>[];
    for (var offset = 0; offset < refs.length; offset += 50) {
      requireSession?.call();
      final batch = refs.skip(offset).take(50).toList();
      final request = <Map<String, Object?>>[];
      for (final note in batch) {
        String? grant;
        try {
          grant = projectionGrant?.call(note);
        } on NoteSecurityFailure {
          continue;
        }
        request.add({
          'ownerId': note.ownerId,
          'noteId': note.id,
          'grant': ?grant,
        });
      }
      if (request.isEmpty) continue;
      final response = await _send(
        method: 'POST',
        uri: _endpoint('sync/v2/label-projections'),
        body: {'wireVersion': 2, 'notes': request},
      );
      if (!_isSuccess(response.statusCode)) throw _decodeError(response);
      final page = decodeChangesPage(
        _readBody(response),
        authorizedContent: true,
      );
      if (page.wireVersion != 2 || page.labels.isNotEmpty) {
        throw const FormatException('Scoped Note response required.');
      }
      for (final snapshot in page.snapshots) {
        // Owned wire snapshots use the authenticated actor as implicit owner.
        // Never infer a missing owner from the requested resource itself.
        final owner = snapshot.ownerId ?? _expectedAccountUserId;
        final ref = request
            .where((r) => r['ownerId'] == owner && r['noteId'] == snapshot.id)
            .firstOrNull;
        final note = batch
            .where((n) => n.ownerId == owner && n.id == snapshot.id)
            .firstOrNull;
        if (ref == null || note == null || !snapshot.includesLabels) {
          throw const SyncFailure(code: SyncErrorCode.forbidden);
        }
        // A local lock during HTTP must invalidate even an authorized response.
        if (projectionGrant?.call(note) != ref['grant']) {
          throw const SyncFailure(code: SyncErrorCode.forbidden);
        }
      }
      snapshots.addAll(page.snapshots);
    }
    return snapshots;
  });

  @override
  Future<SyncMutationResult> push(SyncMutation mutation) {
    return _classify(() async {
      if (requiresSyncWireV3(mutation)) {
        final version = _negotiatedVersion ?? await negotiateWireVersion();
        if (version != 3) {
          throw const SyncFailure(code: SyncErrorCode.documentRequiresUpgrade);
        }
      }
      final http.Response response = await _send(
        method: 'POST',
        uri: _endpoint(syncMutationPath(mutation)),
        body: encodeSyncMutation(mutation),
        mutation: mutation,
      );
      // A stale `baseRevision` is a result, not a failure: the mapper turns the
      // 409 envelope into `SyncMutationResult.conflict`, which the caller
      // reconciles against the remote snapshot it carries.
      final securityConflict =
          response.statusCode == 409 &&
          _decodeError(response).code == SyncErrorCode.forbidden;
      if (_isSuccess(response.statusCode) ||
          (response.statusCode == 409 && !securityConflict)) {
        final result = decodeSyncMutationResponse(
          statusCode: response.statusCode,
          body: _readBody(response),
          mutationId: mutation.mutationId,
        );
        if (mutation.isLabel && result.label == null && result.isApplied ||
            !mutation.isLabel && result.label != null) {
          throw const FormatException('Entity outcome mismatch.');
        }
        if (mutation.payload?.includesLabels == true &&
            result.note?.includesLabels != true &&
            result.isApplied) {
          throw const SyncFailure(code: SyncErrorCode.invalidMutation);
        }
        if (requiresSyncWireV3(mutation) &&
            result.isApplied &&
            result.note?.includesDocument != true) {
          throw const SyncFailure(code: SyncErrorCode.documentRequiresUpgrade);
        }
        if (mutation.ownerId != null) {
          final snapshot = result.note ?? result.conflictRemote;
          if (result.mutationId != mutation.mutationId ||
              (snapshot != null &&
                  (snapshot.ownerId != mutation.ownerId ||
                      snapshot.id != mutation.noteId ||
                      snapshot.share == null ||
                      (_expectedAccountUserId != null &&
                          snapshot.share!.recipientId !=
                              _expectedAccountUserId)))) {
            throw const SyncFailure(code: SyncErrorCode.forbidden);
          }
        }
        return result;
      }
      throw _decodeError(response);
    });
  }

  @override
  Future<SyncChangesPage> pull({String? cursor, int limit = 50}) {
    return _classify(() async {
      final version = _negotiatedVersion ?? await negotiateWireVersion();
      final http.Response response = await _send(
        method: 'GET',
        uri: _endpoint(
          version == 3
              ? 'sync/v3/changes'
              : labelsEnabled
              ? 'sync/v2/changes'
              : _changesPath,
          query: <String, String>{
            // The cursor is opaque: it is forwarded exactly as the caller
            // stored it, never parsed, rebuilt, or truncated here.
            'cursor': ?cursor,
            'limit': '$limit',
          },
        ),
      );
      if (!_isSuccess(response.statusCode)) {
        throw _decodeError(response);
      }
      // The page is returned untouched, so a final page keeps the server's
      // `nextCursor` together with `hasMore == false`.
      final page = decodeChangesPage(_readBody(response));
      if ((labelsEnabled || version == 3) && page.wireVersion != version) {
        throw const FormatException('Typed negotiation failed.');
      }
      return page;
    });
  }

  /// Releases the HTTP client, but only when this adapter created it.
  ///
  /// An injected client belongs to whoever injected it and stays open, so a
  /// caller that shares one client across adapters is not left with a closed
  /// connection pool.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
