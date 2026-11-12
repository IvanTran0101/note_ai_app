import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_policy.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_blob_store.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_chunk_cipher.dart';
import 'package:note_ai_app/infrastructure/attachments/encrypted_attachment_cache.dart';
import 'package:note_ai_app/infrastructure/attachments/http_attachment_upload.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_codec.dart';
import 'package:note_ai_app/infrastructure/security/note_crypto.dart';

final class MemoryBlobs implements AttachmentBlobStore {
  Map<String, Object?> index = {};
  final packets = <String, Map<String, Object?>>{};
  @override
  Future<Map<String, Object?>> readIndex() async => Map.of(index);
  @override
  Future<Map<String, Object?>> updateIndex(
    Map<String, Object?> Function(Map<String, Object?>) change,
  ) async => index = change(Map.of(index));
  @override
  Future<Map<String, Object?>?> readChunk(String key) async => packets[key];
  @override
  Future<void> writeChunk(String key, Map<String, Object?> packet) async {
    packets[key] = Map.of(packet);
  }

  @override
  Future<void> removeChunk(String key) async {
    packets.remove(key);
  }
}

final id = 'a' * 64;
AttachmentBinding binding({String actor = 'owner', int access = 0}) =>
    AttachmentBinding(
      actorId: actor,
      note: NoteIdentity('owner', 'note'),
      protection: const NoteProtection.unprotected(),
      accessRevision: access,
      sessionGeneration: 1,
      contentRevision: 1,
    );
Attachment file(List<int> bytes) => Attachment(
  id: id,
  noteId: 'note',
  fileName: 'file.txt',
  mimeType: 'text/plain',
  sizeBytes: bytes.length,
  storageObjectId: 'final/object',
  objectVersion: 'v1',
  sha256: sha256.convert(bytes).toString(),
  addedAt: DateTime.utc(2026, 10, 5),
);
Future<List<int>> collect(Stream<List<int>> source) async {
  final out = <int>[];
  await for (final b in source) {
    out.addAll(b);
    b.fillRange(0, b.length, 0);
  }
  return out;
}

void main() {
  test('upload uses <=256KiB anonymous PUT chunks, per-call JWT/scope, progress, verify and stable ID', () async {
    final data = Uint8List.fromList(
      utf8.encode('x' * (AttachmentPolicy.chunkBytes + 9)),
    );
    final descriptor = file(data), phases = <String>[];
    var puts = 0, acks = 0;
    final uploader = HttpAttachmentUpload(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async =>
          'header.${base64UrlEncode(utf8.encode('{"sub":"owner"}'))}.signature',
      grantHeader: (_, op) {
        expect(op, NoteOperation.attachmentWrite);
        return null;
      },
      requireAccess: (_, op) => expect(op, NoteOperation.attachmentWrite),
      onProgress: (p) => phases.add(p.phase),
      client: MockClient((request) async {
        if (request.method == 'PUT') {
          puts++;
          expect(
            request.bodyBytes.length,
            lessThanOrEqualTo(AttachmentPolicy.chunkBytes),
          );
          expect(request.headers.containsKey('authorization'), false);
          expect(request.headers.containsKey('x-note-unlock-grant'), false);
          return http.Response('', 200);
        }
        expect(request.url.path, contains('/attachments/$id/'));
        expect(request.followRedirects, false);
        final action = request.url.pathSegments.last;
        if (action == 'chunk-url') {
          return http.Response(
            jsonEncode({
              'url': 'https://fixture.s3.ap-southeast-1.amazonaws.com/staging/chunk?signature=synthetic',
              'headers': {'content-type': 'application/octet-stream'},
            }),
            200,
          );
        }
        if (action == 'chunk-ack') acks++;
        return http.Response(
          jsonEncode(
            action == 'verify'
                ? {
                    'phase': 'verified',
                    'attachment': AttachmentCodec.encode(descriptor),
                  }
                : {'phase': 'uploading', 'completedChunks': 0, 'chunkCount': 2},
          ),
          200,
        );
      }),
    );
    final draft = LocalAttachmentDraft(
      cacheId: id,
      fileName: descriptor.fileName,
      mimeType: descriptor.mimeType,
      sizeBytes: data.length,
      sha256: descriptor.sha256,
      chunkCount: 2,
    );
    final result = await uploader.upload(binding(), draft, () async* {
      yield Uint8List.fromList(data.sublist(0, AttachmentPolicy.chunkBytes));
      yield Uint8List.fromList(data.sublist(AttachmentPolicy.chunkBytes));
    });
    expect(result, descriptor);
    expect(puts, 2);
    expect(acks, 2);
    expect(phases.last, 'Awaiting note sync');
  });
  test('lost verify ACK reconciles descriptor before reading/reuploading local bytes', () async {
    final d = file(utf8.encode('retained'));
    final uploader = HttpAttachmentUpload(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async =>
          'h.${base64UrlEncode(utf8.encode('{"sub":"owner"}'))}.s',
      grantHeader: (_, _) => null,
      requireAccess: (_, _) {},
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'phase': 'verified',
            'attachment': AttachmentCodec.encode(d),
          }),
          200,
        ),
      ),
    );
    expect(
      await uploader.upload(
        binding(),
        LocalAttachmentDraft(
          cacheId: id,
          fileName: d.fileName,
          mimeType: d.mimeType,
          sizeBytes: d.sizeBytes,
          sha256: d.sha256,
          chunkCount: 1,
        ),
        () => throw StateError('Must not reupload'),
      ),
      d,
    );
  });
  test('sparse encrypted recipient cache reads ranges offline, reopens and never needs attachmentWrite', () async {
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    final blobs = MemoryBlobs(), bytes = utf8.encode('PRIVATE' * 50000);
    final d = file(bytes);
    var reads = 0;
    final cipher = AttachmentChunkCipher(
      requireAccess: (_, op) => expect(op, NoteOperation.attachmentRead),
      resolveKey: (_) async => key,
    );
    EncryptedAttachmentCache cache() => EncryptedAttachmentCache(
      actorId: 'recipient',
      store: blobs,
      cipher: cipher,
      generateId: () => 'unused',
    );
    Stream<List<int>> remote(
      AttachmentBinding _,
      Attachment _, {
      int start = 0,
      int? end,
    }) async* {
      reads++;
      yield Uint8List.fromList(bytes.sublist(start, end));
    }

    final b = binding(actor: 'recipient', access: 1);
    expect(
      await collect(cache().readAssociated(b, d, remote, start: 5, end: 17)),
      bytes.sublist(5, 17),
    );
    expect(reads, 1);
    Stream<List<int>> offline(
      AttachmentBinding _,
      Attachment _, {
      int start = 0,
      int? end,
    }) async* {
      throw StateError('Offline');
    }

    expect(
      await collect(cache().readAssociated(b, d, offline, start: 8, end: 23)),
      bytes.sublist(8, 23),
    );
    expect(jsonEncode(blobs.packets), isNot(contains('PRIVATE')));
    expect(jsonEncode(blobs.index), isNot(contains('file.txt')));
    await expectLater(
      collect(
        cache().readAssociated(
          binding(actor: 'recipient', access: 2),
          d,
          offline,
          end: 10,
        ),
      ),
      throwsStateError,
    );
  });
  test('in-flight revoke rejects cache/network bytes and does not persist unreadable chunks', () async {
    final key = await NoteCrypto().newKey();
    addTearDown(key.destroy);
    var live = true;
    final blobs = MemoryBlobs(), bytes = utf8.encode('private');
    final d = file(bytes);
    final cache = EncryptedAttachmentCache(
      actorId: 'recipient',
      store: blobs,
      cipher: AttachmentChunkCipher(
        requireAccess: (_, _) {
          if (!live) throw StateError('revoked');
        },
        resolveKey: (_) async => key,
      ),
      generateId: () => 'unused',
    );
    Stream<List<int>> remote(
      AttachmentBinding _,
      Attachment _, {
      int start = 0,
      int? end,
    }) async* {
      live = false;
      yield Uint8List.fromList(bytes);
    }

    await expectLater(
      collect(
        cache.readAssociated(binding(actor: 'recipient', access: 1), d, remote),
      ),
      throwsStateError,
    );
    expect(blobs.packets, isEmpty);
  });
}
