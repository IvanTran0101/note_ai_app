import 'package:file_selector/file_selector.dart' as files;
import 'package:image_picker/image_picker.dart';

import '../../application/attachments/attachment_input.dart';
import '../../application/attachments/attachment_policy.dart';

/// Official plugin adapters; no storage permission, file path or plugin in Domain.
final class FlutterAttachmentPicker {
  FlutterAttachmentPicker({ImagePicker? imagePicker})
    : _images = imagePicker ?? ImagePicker();
  final ImagePicker _images;

  Future<List<AttachmentInput>> pick(AttachmentSource source) async {
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
        selected = file == null ? [] : [file];
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
    return _map(recovered.files ?? []);
  }

  Future<List<AttachmentInput>> _map(List<XFile> selected) async =>
      List.unmodifiable([
        for (final file in selected)
          AttachmentInput(
            fileName: file.name,
            mimeType:
                file.mimeType ??
                AttachmentPolicy
                    .types[file.name.split('.').last.toLowerCase()]
                    ?.mime ??
                '',
            sizeBytes: await file.length(),
            openRead: file.openRead,
          ),
      ]);
}
