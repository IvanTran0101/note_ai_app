import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/infrastructure/attachments/flutter_attachment_picker.dart';

final class _Camera extends Fake implements ImagePicker {
  _Camera(this.file, {this.type = RetrieveType.video});
  final XFile? file;
  final RetrieveType type;
  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => file;
  @override
  Future<List<XFile>> pickMultipleMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async => file == null ? [] : [file!];
  @override
  Future<LostDataResponse> retrieveLostData() async =>
      LostDataResponse(type: type, files: file == null ? [] : [file!]);
}

final class _VideoFile extends Fake implements XFile {
  _VideoFile(this.name, this.bytes);
  @override
  final String name;
  final List<int> bytes;
  @override
  String get path => name;
  @override
  String get mimeType => 'video/mp4';
  @override
  Future<int> length() async => bytes.length;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List.fromList(bytes.sublist(start ?? 0, end ?? bytes.length));
  }
}

XFile _file(String name, List<int> bytes) => _VideoFile(name, bytes);

void main() {
  test(
    'camera video prepares bytes before normal bounded input mapping',
    () async {
      final original = _file('camera.mp4', [1, 2]),
          converted = _file('aac.mp4', [3, 4, 5]);
      var calls = 0;
      final picker = FlutterAttachmentPicker(
        imagePicker: _Camera(original),
        prepareCameraVideo: (file) async {
          expect(file, same(original));
          calls++;
          return converted;
        },
      );
      final inputs = await picker.pick(AttachmentSource.cameraVideo);
      expect(calls, 1);
      expect(inputs.single.fileName, 'aac.mp4');
      expect(inputs.single.sizeBytes, 3);
      expect(await inputs.single.openRead().expand((bytes) => bytes).toList(), [
        3,
        4,
        5,
      ]);
    },
  );

  test(
    'camera cancellation does not prepare or create an attachment',
    () async {
      final picker = FlutterAttachmentPicker(
        imagePicker: _Camera(null),
        prepareCameraVideo: (_) async => throw StateError('Should not prepare'),
      );
      expect(await picker.pick(AttachmentSource.cameraVideo), isEmpty);
    },
  );

  test(
    'camera preparation unavailable keeps actionable picker failure',
    () async {
      final picker = FlutterAttachmentPicker(
        imagePicker: _Camera(_file('camera.mp4', [1])),
        prepareCameraVideo: (_) async =>
            throw PlatformException(code: 'CAMERA_VIDEO_UNAVAILABLE'),
      );
      await expectLater(
        picker.pick(AttachmentSource.cameraVideo),
        throwsA(
          isA<AttachmentSelectionFailure>().having(
            (e) => e.code,
            'code',
            AttachmentSelectionFailureCode.unavailable,
          ),
        ),
      );
    },
  );

  test('Gallery original does not pass through camera conversion', () async {
    final picker = FlutterAttachmentPicker(
      imagePicker: _Camera(_file('gallery.mp4', [1])),
      prepareCameraVideo: (_) async => throw StateError('Should not prepare'),
    );
    expect(
      (await picker.pick(AttachmentSource.gallery)).single.fileName,
      'gallery.mp4',
    );
  });

  test(
    'lost camera video prepares before input recovery; image does not',
    () async {
      final original = _file('camera.mp4', [1]),
          converted = _file('aac.mp4', [2, 3]);
      var calls = 0;
      Future<XFile> prepare(XFile _) async {
        calls++;
        return converted;
      }

      final video = FlutterAttachmentPicker(
        imagePicker: _Camera(original),
        prepareCameraVideo: prepare,
      );
      expect((await video.recoverCameraSelection()).single.sizeBytes, 2);
      final image = FlutterAttachmentPicker(
        imagePicker: _Camera(original, type: RetrieveType.image),
        prepareCameraVideo: prepare,
      );
      expect((await image.recoverCameraSelection()).single.sizeBytes, 1);
      expect(calls, 1);
    },
  );
}
