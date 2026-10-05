import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_media.dart';
import 'package:note_ai_app/application/attachments/attachment_policy.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_media_bridge_io.dart';

void main() {
  test('Native media Range is bounded, checks each request, and dies on close', () async {
    final bytes = Uint8List.fromList(
      List.generate(AttachmentPolicy.chunkBytes + 9, (i) => i % 256),
    );
    var allowed = true;
    final sizes = <int>[];
    final issued = <List<int>>[];
    final handle = await createAttachmentMediaBridge().open(
      AttachmentMediaRequest(
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
        sizeBytes: bytes.length,
        authorize: () async {
          if (!allowed) throw StateError('Locked');
        },
        read: (start, end) async* {
          sizes.add(end - start);
          final chunk = bytes.sublist(start, end);
          issued.add(chunk);
          yield chunk;
        },
      ),
    );
    final client = HttpClient();
    try {
      final request = await client.getUrl(handle.uri!);
      request.headers.set('range', 'bytes=3-18');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(
        response.headers.value('content-range'),
        'bytes 3-18/${bytes.length}',
      );
      expect(await response.expand((x) => x).toList(), bytes.sublist(3, 19));
      final entire = await (await client.getUrl(handle.uri!)).close();
      expect(await entire.expand((x) => x).toList(), bytes);
      expect(sizes.every((s) => s <= AttachmentPolicy.chunkBytes), true);
      expect(issued.every((b) => b.every((v) => v == 0)), true);
      allowed = false;
      // Revocation may reset the local connection; either failure has no bytes.
      await (() async {
        final denied = await (await client.getUrl(handle.uri!)).close();
        expect(denied.statusCode, 403);
        expect(await denied.toList(), isEmpty);
      })();
      await handle.close();
      await expectLater(
        client.getUrl(handle.uri!).then((r) => r.close()),
        throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
      );
    } finally {
      client.close(force: true);
      await handle.close();
    }
  });
}
