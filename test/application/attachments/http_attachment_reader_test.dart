import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_policy.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/attachments/http_attachment_reader.dart';

String jwt(String actor) =>
    'header.${base64UrlEncode(utf8.encode(jsonEncode({'sub': actor})))}.signature';
Attachment file(List<int> data, {String? checksum}) => Attachment(
  id: 'file',
  noteId: 'note',
  fileName: 'file.txt',
  mimeType: 'text/plain',
  sizeBytes: data.length,
  storageObjectId: 'object',
  objectVersion: 'v1',
  sha256: checksum ?? sha256.convert(data).toString(),
  addedAt: DateTime.utc(2026, 10, 4),
);
AttachmentBinding binding({bool protected = false}) => AttachmentBinding(
  actorId: 'actor',
  note: NoteIdentity('owner', 'note'),
  protection: protected
      ? NoteProtection(enabled: true, revision: 1)
      : const NoteProtection.unprotected(),
  accessRevision: 1,
  sessionGeneration: 1,
  contentRevision: 2,
);

http.Response range(
  http.Request request,
  List<int> data, {
  bool wrongRange = false,
}) {
  final match = RegExp(r'^bytes=(\d+)-(\d+)$')
      .firstMatch(request.headers['Range']!)!;
  final start = int.parse(match[1]!), end = int.parse(match[2]!);
  return http.Response.bytes(
    data.sublist(start, end + 1),
    206,
    headers: {
      'content-type': 'text/plain',
      'content-range': wrongRange
          ? 'bytes 0-0/1'
          : 'bytes $start-$end/${data.length}',
    },
  );
}

Future<List<int>> collect(Stream<Uint8List> stream) async {
  final result = <int>[];
  await for (final chunk in stream) {
    result.addAll(chunk);
    chunk.fillRange(0, chunk.length, 0);
  }
  return result;
}

void main() {
  test(
    'large read uses bounded authenticated Ranges and the attachment scope',
    () async {
      final bytes = List<int>.generate(
        AttachmentPolicy.chunkBytes + 7,
        (i) => i % 256,
      );
      var requests = 0, tokens = 0, grants = 0;
      final reader = HttpAttachmentReader(
        baseUri: Uri.parse('https://api.example.test/prod'),
        tokenProvider: ({required forceRefresh}) async {
          tokens++;
          return jwt('actor');
        },
        grantHeader: (captured, operation) {
          expect(operation, NoteOperation.attachmentRead);
          grants++;
          return 'g' * 43;
        },
        requireAccess: (captured, operation) =>
            expect(operation, NoteOperation.attachmentRead),
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, '/prod/notes/note/attachments/file/content');
          expect(request.url.queryParameters, {
            'ownerId': 'owner',
            'objectVersion': 'v1',
          });
          expect(request.headers['Authorization'], 'Bearer ${jwt('actor')}');
          expect(request.headers['X-Note-Unlock-Grant'], 'g' * 43);
          expect(request.followRedirects, false);
          return range(request, bytes);
        }),
      );
      expect(
        await collect(reader.read(binding(protected: true), file(bytes))),
        bytes,
      );
      expect([requests, tokens, grants], [2, 2, 2]);
    },
  );

  test('seek is end-exclusive and never requests unrelated bytes', () async {
    final bytes = utf8.encode('abcdef');
    final reader = HttpAttachmentReader(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => jwt('actor'),
      grantHeader: (_, operation) => null,
      requireAccess: (_, operation) {},
      client: MockClient((request) async {
        expect(request.headers['Range'], 'bytes=2-4');
        return range(request, bytes);
      }),
    );
    expect(
      await collect(reader.read(binding(), file(bytes), start: 2, end: 5)),
      utf8.encode('cde'),
    );
  });

  test(
    '401 refreshes once and obtains the grant again for the retry',
    () async {
      final bytes = utf8.encode('abc');
      final refreshes = <bool>[];
      var requests = 0, grants = 0;
      final reader = HttpAttachmentReader(
        baseUri: Uri.parse('https://api.example.test'),
        tokenProvider: ({required forceRefresh}) async {
          refreshes.add(forceRefresh);
          return jwt('actor');
        },
        grantHeader: (_, operation) {
          grants++;
          return null;
        },
        requireAccess: (_, operation) {},
        client: MockClient(
          (request) async => ++requests == 1
              ? http.Response('private provider text', 401)
              : range(request, bytes),
        ),
      );
      expect(await collect(reader.read(binding(), file(bytes))), bytes);
      expect(refreshes, [false, true]);
      expect(grants, 2);
    },
  );

  test(
    'wrong-account token and missing binary grant never send a request',
    () async {
      for (final wrongActor in [true, false]) {
        var sent = false;
        final reader = HttpAttachmentReader(
          baseUri: Uri.parse('https://api.example.test'),
          tokenProvider: ({required forceRefresh}) async =>
              jwt(wrongActor ? 'other' : 'actor'),
          grantHeader: (_, operation) => null,
          requireAccess: (_, operation) {},
          client: MockClient((request) async {
            sent = true;
            return http.Response('', 200);
          }),
        );
        await expectLater(
          collect(reader.read(binding(protected: true), file([1]))),
          throwsA(isA<NoteSecurityFailure>()),
        );
        expect(sent, false);
      }
    },
  );

  test('lock after token acquisition fences the same actor session', () async {
    var locked = false, sent = false;
    final reader = HttpAttachmentReader(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async {
        locked = true;
        return jwt('actor');
      },
      grantHeader: (_, operation) => null,
      requireAccess: (_, operation) {
        if (locked) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
        }
      },
      client: MockClient((request) async {
        sent = true;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      collect(reader.read(binding(), file([1]))),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect(sent, false);
  });

  test(
    'incorrect Content-Range is refused without yielding any bytes',
    () async {
      final data = [1, 2, 3];
      final reader = HttpAttachmentReader(
        baseUri: Uri.parse('https://api.example.test'),
        tokenProvider: ({required forceRefresh}) async => jwt('actor'),
        grantHeader: (_, operation) => null,
        requireAccess: (_, operation) {},
        client: MockClient(
          (request) async => range(request, data, wrongRange: true),
        ),
      );
      var yielded = false;
      await expectLater(
        reader.read(binding(), file(data)).map((bytes) {
          yielded = true;
          return bytes;
        }).drain<void>(),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(yielded, false);
    },
  );

  test('a complete read must match the server-verified checksum', () async {
    final data = [1, 2, 3];
    final reader = HttpAttachmentReader(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => jwt('actor'),
      grantHeader: (_, operation) => null,
      requireAccess: (_, operation) {},
      client: MockClient((request) async => range(request, data)),
    );
    await expectLater(
      collect(reader.read(binding(), file(data, checksum: 'a' * 64))),
      throwsA(
        isA<NoteSecurityFailure>().having(
          (e) => e.code,
          'code',
          NoteSecurityFailureCode.storage,
        ),
      ),
    );
  });

  test('expired/revoked authority blocks subsequent Ranges', () async {
    final bytes = List<int>.filled(AttachmentPolicy.chunkBytes + 1, 1);
    var expired = false, requests = 0;
    final reader = HttpAttachmentReader(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => jwt('actor'),
      grantHeader: (_, operation) => null,
      requireAccess: (_, operation) {
        if (expired) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.expired);
        }
      },
      client: MockClient((request) async {
        requests++;
        return range(request, bytes);
      }),
    );
    final work = () async {
      await for (final bytes in reader.read(binding(), file(bytes))) {
        bytes.fillRange(0, bytes.length, 0);
        expired = true;
      }
    }();
    await expectLater(work, throwsA(isA<NoteSecurityFailure>()));
    expect(requests, 1);
  });

  test(
    'redirects, short bodies and ignored Range responses are never accepted',
    () async {
      for (final status in [200, 302, 206]) {
        final reader = HttpAttachmentReader(
          baseUri: Uri.parse('https://api.example.test'),
          tokenProvider: ({required forceRefresh}) async => jwt('actor'),
          grantHeader: (_, operation) => null,
          requireAccess: (_, operation) {},
          client: MockClient(
            (request) async => http.Response.bytes(
              [1],
              status,
              headers: {
                'content-type': 'text/plain',
                'content-range': 'bytes 0-2/3',
                'location': 'https://evil.test',
              },
            ),
          ),
        );
        await expectLater(
          collect(reader.read(binding(), file([1, 2, 3]))),
          throwsA(isA<NoteSecurityFailure>()),
        );
      }
    },
  );
}
