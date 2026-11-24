import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/attachment_policy.dart';
import 'package:note_ai_app/infrastructure/attachments/flutter_attachment_picker.dart';

final class _SelectedFile extends Fake implements XFile {
  final ranges = <List<int>>[], buffers = <Uint8List>[];
  @override
  String get name => 'bounded.txt';
  @override
  String get path => 'temporary-provider-selection';
  @override
  String? get mimeType => 'text/plain';
  @override
  Future<int> length() async => AttachmentPolicy.chunkBytes * 3 + 7;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    expect(start, isNotNull);
    expect(end, isNotNull);
    ranges.add([start!, end!]);
    final bytes = Uint8List(end - start)..fillRange(0, end - start, 97);
    buffers.add(bytes);
    yield bytes;
  }
}

final class _SelectionImages extends Fake implements ImagePicker {
  _SelectionImages(this.failure);
  final String? failure;
  @override
  dynamic noSuchMethod(Invocation _) => failure == null
      ? Future<List<XFile>>.value([])
      : Future<List<XFile>>.error(PlatformException(code: failure!));
}

void main() {
  test('picker bounds the actual Blob/file read request and wipes transient buffers', () async {
    final file = _SelectedFile(),
        input = await attachmentInputFromFile(_SelectedFile());
    // Separate requested ranges from descriptor creation to prove both APIs.
    expect(input.sizeBytes, AttachmentPolicy.chunkBytes * 3 + 7);
    final source = await attachmentInputFromFile(file);
    var total = 0;
    await for (final bytes in source.openRead()) {
      expect(bytes.length, lessThanOrEqualTo(AttachmentPolicy.chunkBytes));
      expect(bytes.first, 97);
      total += bytes.length;
    }
    expect(total, source.sizeBytes);
    expect(file.ranges, hasLength(4));
    expect(file.ranges.last, [
      AttachmentPolicy.chunkBytes * 3,
      source.sizeBytes,
    ]);
    expect(file.buffers.every((b) => b.every((v) => v == 0)), true);
  });
  test(
    'permission denial is mapped to safe actionable selection failure',
    () async {
      final picker = FlutterAttachmentPicker(
        imagePicker: _SelectionImages('photo_access_denied'),
      );
      await expectLater(
        picker.pick(AttachmentSource.gallery),
        throwsA(
          isA<AttachmentSelectionFailure>().having(
            (e) => e.code,
            'code',
            AttachmentSelectionFailureCode.denied,
          ),
        ),
      );
    },
  );
  test('unavailable picker and cancellation remain distinct', () async {
    final picker = FlutterAttachmentPicker(
      imagePicker: _SelectionImages('unsupported'),
    );
    await expectLater(
      picker.pick(AttachmentSource.gallery),
      throwsA(
        isA<AttachmentSelectionFailure>().having(
          (e) => e.code,
          'code',
          AttachmentSelectionFailureCode.unavailable,
        ),
      ),
    );
    expect(
      await FlutterAttachmentPicker(imagePicker: _SelectionImages(null))
          .pick(AttachmentSource.gallery),
      isEmpty,
    );
  });
}
