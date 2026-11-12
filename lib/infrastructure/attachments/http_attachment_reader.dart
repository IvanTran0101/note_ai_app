import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../../application/attachments/attachment_binding.dart';
import '../../application/attachments/attachment_policy.dart';
import '../../application/notes/note_access.dart';
import '../../domain/notes/attachment.dart';
import '../../domain/notes/note_protection.dart';
import '../security/note_jwt_subject.dart';
import 'attachment_http_request.dart';
import '../sync/http_remote_note_data_source.dart';

/// Authenticated REST content route, never a public/presigned GET. Every
/// bounded Range request obtains a fresh JWT/grant and the backend must intersect
/// them with its current ACL, note manifest and object/protection/access epochs.
/// The caller supplies M05/M06's live guard; this adapter cannot grant access.
final class HttpAttachmentReader {
  HttpAttachmentReader({
    required this.baseUri,
    required this.tokenProvider,
    required this.grantHeader,
    required this.requireAccess,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.operation = NoteOperation.attachmentRead,
    bool allowLocalDev = false,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (!(baseUri.scheme == 'https' ||
            allowLocalDev &&
                baseUri.scheme == 'http' &&
                baseUri.host == '127.0.0.1' &&
                baseUri.port == 8796) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        timeout <= Duration.zero ||
        operation != NoteOperation.attachmentRead &&
            operation != NoteOperation.export) {
      throw ArgumentError(
        'An HTTPS attachment API and positive timeout are required.',
      );
    }
  }

  final Uri baseUri;
  final SyncAccessTokenProvider tokenProvider;
  // Reuse HttpNoteSecurityGateway.grantHeader with attachmentRead, not read.
  final String? Function(AttachmentBinding binding, NoteOperation operation)
  grantHeader;
  final void Function(AttachmentBinding binding, NoteOperation operation)
  requireAccess;
  final Duration timeout;
  final NoteOperation operation;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;
  final _reads = <String, Set<Completer<void>>>{};

  String _key(AttachmentBinding b, String id) =>
      jsonEncode([b.actorId, b.note.key, id]);

  void cancel(AttachmentBinding b, String id) {
    for (final read in _reads[_key(b, id)] ?? <Completer<void>>{}) {
      if (!read.isCompleted) read.complete();
    }
  }

  void _require(AttachmentBinding binding, Attachment attachment) {
    if (_closed) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    if (attachment.noteId != binding.note.noteId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    requireAccess(binding, NoteOperation.attachmentRead);
    if (operation == NoteOperation.export) {
      if (binding.actorId != binding.note.ownerId) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      requireAccess(binding, NoteOperation.export);
    }
  }

  Uri _endpoint(AttachmentBinding binding, Attachment attachment) {
    final prefix = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    return baseUri.replace(
      path:
          '${prefix}notes/${Uri.encodeComponent(binding.note.noteId)}'
          '/attachments/${Uri.encodeComponent(attachment.id)}/content',
      queryParameters: {
        'ownerId': binding.note.ownerId,
        'objectVersion': attachment.objectVersion,
        if (operation == NoteOperation.export) 'mode': 'export',
      },
    );
  }

  /// End is exclusive, matching the encrypted cache's local Range reader.
  /// Each yielded buffer belongs to the caller and should be erased on close.
  /// A full read also verifies SHA-256 before completion; a preview must wait
  /// for completion before displaying the collected bytes.
  Stream<Uint8List> read(
    AttachmentBinding binding,
    Attachment attachment, {
    int start = 0,
    int? end,
  }) async* {
    final stop = end ?? attachment.sizeBytes;
    if (start < 0 ||
        stop < start ||
        stop > attachment.sizeBytes ||
        attachment.sizeBytes > 50 * AttachmentPolicy.mib) {
      throw ArgumentError('Invalid attachment byte range.');
    }
    _require(binding, attachment);
    AttachmentPolicy.validate(
      fileName: attachment.fileName,
      mimeType: attachment.mimeType,
      sizeBytes: attachment.sizeBytes,
      existing: const [],
    );
    final digest = _DigestSink();
    final hasher = crypto.sha256.startChunkedConversion(digest);
    final key = _key(binding, attachment.id);
    final cancel = Completer<void>();
    (_reads[key] ??= {}).add(cancel);
    void guard() {
      _require(binding, attachment);
      if (cancel.isCompleted) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
      }
    }

    try {
      for (var offset = start; offset < stop;) {
        final next = (offset + AttachmentPolicy.chunkBytes < stop)
            ? offset + AttachmentPolicy.chunkBytes
            : stop;
        final bytes = await _range(
          binding,
          attachment,
          offset,
          next,
          guard,
          cancel.future,
        );
        try {
          guard();
          hasher.add(bytes);
          yield bytes;
        } catch (_) {
          bytes.fillRange(0, bytes.length, 0);
          rethrow;
        }
        offset = next;
      }
      guard();
      hasher.close();
      if (start == 0 &&
          stop == attachment.sizeBytes &&
          digest.value.toString() != attachment.sha256) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
      }
    } on NoteSecurityFailure {
      rethrow;
    } on TimeoutException {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.network);
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    } finally {
      _reads[key]?.remove(cancel);
      if (_reads[key]?.isEmpty ?? false) _reads.remove(key);
    }
  }

  Future<Uint8List> _range(
    AttachmentBinding binding,
    Attachment attachment,
    int start,
    int end,
    void Function() guard,
    Future<void> cancel,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      guard();
      final token = await tokenProvider(forceRefresh: attempt == 1)
          .timeout(timeout);
      guard();
      if (token == null || noteJwtSubject(token) != binding.actorId) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
      }
      final grant = grantHeader(binding, operation);
      if (binding.protection.enabled &&
          (grant == null || !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(grant))) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
      }
      final result = await attachmentHttpRequest<Uint8List?>(
        client: _client,
        method: 'GET',
        uri: _endpoint(binding, attachment),
        timeout: timeout,
        requireAccess: guard,
        cancel: cancel,
        discard: (bytes) => bytes?.fillRange(0, bytes.length, 0),
        configure: (request) => request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Range': 'bytes=$start-${end - 1}',
          'Accept': attachment.mimeType,
          'X-Note-Unlock-Grant': ?grant,
        }),
        consume: (response) async {
          if (response.statusCode == 401 && attempt == 0) {
            await response.stream.listen((_) {}).cancel();
            return null;
          }
          if (response.statusCode != 206 ||
              response.headers['content-range'] !=
                  'bytes $start-${end - 1}/${attachment.sizeBytes}' ||
              response.headers['content-type']?.split(';').first.trim() !=
                  attachment.mimeType ||
              response.contentLength != null &&
                  response.contentLength != end - start) {
            await response.stream.listen((_) {}).cancel();
            throw NoteSecurityFailure(
              response.statusCode == 401 || response.statusCode == 403
                  ? NoteSecurityFailureCode.denied
                  : NoteSecurityFailureCode.unavailable,
            );
          }
          final bytes = Uint8List(end - start);
          var written = 0;
          try {
            await for (final chunk in response.stream.timeout(timeout)) {
              guard();
              if (written + chunk.length > bytes.length) {
                throw const NoteSecurityFailure(
                  NoteSecurityFailureCode.unavailable,
                );
              }
              bytes.setRange(written, written + chunk.length, chunk);
              written += chunk.length;
            }
            guard();
            if (written != bytes.length) {
              throw const NoteSecurityFailure(
                NoteSecurityFailureCode.unavailable,
              );
            }
            return bytes;
          } on Object {
            bytes.fillRange(0, bytes.length, 0);
            rethrow;
          }
        },
      );
      if (result != null) return result;
    }
    throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
  }

  void close() {
    _closed = true;
    for (final reads in _reads.values) {
      for (final read in reads) {
        if (!read.isCompleted) read.complete();
      }
    }
    if (_ownsClient) _client.close();
  }
}

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}
