import 'package:file_selector/file_selector.dart' as files;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import '../../application/attachments/attachment_input.dart';
import '../../application/attachments/attachment_policy.dart';
import 'attachment_picker_cleanup.dart';
import 'attachment_camera_video.dart';

/// Official plugin adapters; no storage permission, file path or plugin in Domain.
final class FlutterAttachmentPicker {
  FlutterAttachmentPicker({
    ImagePicker? imagePicker,
    Future<XFile> Function(XFile)? prepareCameraVideo,
  }) : _images = imagePicker ?? ImagePicker(),
       _prepareCameraVideo = prepareCameraVideo ?? prepareAttachmentCameraVideo;
  final ImagePicker _images;
  final Future<XFile> Function(XFile) _prepareCameraVideo;

  Future<List<AttachmentInput>> pick(AttachmentSource source) async {
    try {
      return await _select(source);
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      throw AttachmentSelectionFailure(
        code.contains('denied') || code.contains('permission')
            ? AttachmentSelectionFailureCode.denied
            : AttachmentSelectionFailureCode.unavailable,
      );
    } on UnsupportedError {
      throw const AttachmentSelectionFailure(
        AttachmentSelectionFailureCode.unavailable,
      );
    }
  }

  Future<List<AttachmentInput>> _select(AttachmentSource source) async {
    final List<XFile> selected;
    switch (source) {
      case AttachmentSource.files:
        selected = await files.openFiles(
          acceptedTypeGroups: [
            files.XTypeGroup(
              label: 'Note attachments',
              extensions: AttachmentPolicy.types.keys.toList(),
              mimeTypes: AttachmentPolicy.types.values
                  .map((type) => type.mime)
                  .toSet()
                  .toList(),
            ),
          ],
        );
      case AttachmentSource.gallery:
        selected = await _images.pickMultipleMedia(
          limit: AttachmentPolicy.maxFiles,
        );
      case AttachmentSource.cameraPhoto:
        final file = await _images.pickImage(
          source: ImageSource.camera,
          requestFullMetadata: false,
        );
        selected = file == null ? [] : [file];
      case AttachmentSource.cameraVideo:
        final file = await _images.pickVideo(source: ImageSource.camera);
        selected = file == null ? [] : await _prepareVideos([file]);
    }
    return _map(selected);
  }

  /// Android activity/process recreation: callers stage recovered files only
  /// after rechecking the active account and note authority.
  Future<List<AttachmentInput>> recoverCameraSelection() async {
    final recovered = await _images.retrieveLostData();
    if (recovered.exception != null) {
      throw StateError('Camera selection could not be recovered.');
    }
    final files = recovered.files ?? [];
    return _map(
      recovered.type == RetrieveType.video
          ? await _prepareVideos(files)
          : files,
    );
  }

  Future<List<XFile>> _prepareVideos(List<XFile> files) async {
    final prepared = <XFile>[];
    try {
      for (final file in files) {
        prepared.add(await _prepareCameraVideo(file));
      }
      return prepared;
    } on Object {
      for (final file in [...files, ...prepared]) {
        await releaseAttachmentSelection(file.path);
      }
      rethrow;
    }
  }

  Future<List<AttachmentInput>> _map(List<XFile> selected) async {
    try {
      return List.unmodifiable([
        for (final file in selected) await attachmentInputFromFile(file),
      ]);
    } on Object {
      for (final file in selected) {
        await releaseAttachmentSelection(file.path);
      }
      rethrow;
    }
  }
}

/// cross_file Web openRead() converts its entire requested Blob slice to an
/// ArrayBuffer. Bound the requested slice itself, before staging/validation.
Future<AttachmentInput> attachmentInputFromFile(XFile file) async {
  final length = await file.length();
  return AttachmentInput(
    fileName: file.name,
    mimeType:
        file.mimeType ??
        AttachmentPolicy.types[file.name.split('.').last.toLowerCase()]?.mime ??
        '',
    sizeBytes: length,
    release: () => releaseAttachmentSelection(file.path),
    openRead: ([start, end]) async* {
      var offset = start ?? 0;
      final stop = end ?? length;
      if (offset < 0 || stop < offset || stop > length) {
        throw RangeError('Invalid selected file range');
      }
      while (offset < stop) {
        final next = (offset + AttachmentPolicy.chunkBytes).clamp(0, stop);
        var received = 0;
        await for (final bytes in file.openRead(offset, next)) {
          try {
            received += bytes.length;
            if (received > next - offset ||
                bytes.length > AttachmentPolicy.chunkBytes) {
              throw const FormatException('Invalid selected file stream');
            }
            yield bytes;
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
        if (received != next - offset) {
          throw const FormatException('Selected file changed');
        }
        offset = next;
      }
    },
  );
}
