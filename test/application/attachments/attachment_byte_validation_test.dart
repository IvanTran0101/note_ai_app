import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_byte_validation.dart';

List<int> uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
List<int> box(String type, List<int> body) => [
  ...uint32(body.length + 8),
  ...ascii.encode(type),
  ...body,
];
List<int> track(String kind, String codec) {
  final config = kind == 'vide'
      ? box('avcC', [1, 66, 0, 30, 255, 225, 0, 1, 103, 1, 0, 1, 104])
      : box('esds', [
          0,
          0,
          0,
          0,
          3,
          22,
          0,
          1,
          0,
          4,
          17,
          64,
          ...List.filled(12, 0),
          5,
          2,
          18,
          16,
        ]);
  return box(
    'trak',
    box('mdia', [
      ...box('hdlr', [...List.filled(8, 0), ...ascii.encode(kind)]),
      ...box(
        'minf',
        box(
          'stbl',
          box('stsd', [
            ...List.filled(4, 0),
            ...uint32(1),
            ...box(codec, [
              ...List.filled(kind == 'vide' ? 78 : 28, 0),
              ...config,
            ]),
          ]),
        ),
      ),
    ]),
  );
}

List<int> mp4({String video = 'avc1', String audio = 'mp4a'}) => [
  ...box('ftyp', [...ascii.encode('isom'), ...List.filled(4, 0)]),
  ...box('moov', [...track('vide', video), ...track('soun', audio)]),
];
AttachmentInput source(List<int> bytes, String mime) => AttachmentInput(
  fileName: 'sample',
  mimeType: mime,
  sizeBytes: bytes.length,
  openRead: ([start, end]) =>
      Stream.value(bytes.sublist(start ?? 0, end ?? bytes.length)),
);
void main() {
  test('magic must match the claimed media type', () async {
    await AttachmentByteValidation.validate(
      source([137, 80, 78, 71, 13, 10, 26, 10], 'image/png'),
    );
    await expectLater(
      AttachmentByteValidation.validate(
        source(utf8.encode('not a picture'), 'image/png'),
      ),
      throwsFormatException,
    );
    await expectLater(
      AttachmentByteValidation.validate(source([255, 216, 255], 'image/png')),
      throwsFormatException,
    );
  });
  test(
    'text must be complete UTF8 without NUL; split UTF8 sequences are accepted',
    () async {
      final bytes = utf8.encode('Unicode Tiếng Việt');
      await AttachmentByteValidation.validate(source(bytes, 'text/csv'));
      await expectLater(
        AttachmentByteValidation.validate(source([0xc3, 0x28], 'text/plain')),
        throwsFormatException,
      );
      await expectLater(
        AttachmentByteValidation.validate(source([65, 0, 66], 'text/plain')),
        throwsFormatException,
      );
      final split = AttachmentInput(
        fileName: 'text.txt',
        mimeType: 'text/plain',
        sizeBytes: bytes.length,
        openRead: ([start, end]) => Stream.fromIterable(
          bytes.sublist(start ?? 0, end ?? bytes.length).map((b) => [b]),
        ),
      );
      await AttachmentByteValidation.validate(split);
    },
  );
  test('MP4 requires H264/AAC sample descriptions; HEVC and other audio are rejected', () async {
    await AttachmentByteValidation.validate(source(mp4(), 'video/mp4'));
    await expectLater(
      AttachmentByteValidation.validate(
        source(mp4(video: 'hvc1'), 'video/mp4'),
      ),
      throwsFormatException,
    );
    await expectLater(
      AttachmentByteValidation.validate(
        source(mp4(audio: 'Opus'), 'video/mp4'),
      ),
      throwsFormatException,
    );
    await expectLater(
      AttachmentByteValidation.validate(
        source([0, 0, 0, 100, 102, 116, 121, 112], 'video/mp4'),
      ),
      throwsFormatException,
    );
  });
  test(
    'short or overshooting range streams cannot validate a media structure',
    () async {
      final input = AttachmentInput(
        fileName: 'fake.png',
        mimeType: 'image/png',
        sizeBytes: 32,
        openRead: ([start, end]) =>
            Stream.value([137, 80, 78, 71, 13, 10, 26, 10]),
      );
      await expectLater(
        AttachmentByteValidation.validate(input),
        throwsFormatException,
      );
    },
  );
}
