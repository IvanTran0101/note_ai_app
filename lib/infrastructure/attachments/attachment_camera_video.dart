import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'attachment_picker_cleanup.dart';

/// Android camera profiles may return AMR audio inside MP4. Normalize only its
/// owned scratch selection, then let the normal byte/policy checks and encrypted
/// local staging run. Web and other platforms keep their original selection.
Future<XFile> prepareAttachmentCameraVideo(XFile file) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return file;
  String? preparedPath;
  try {
    final path = await const MethodChannel('noteflow/attachment_camera_video')
        .invokeMethod<String>('prepare', {'path': file.path});
    if (path == null || path.isEmpty) {
      throw PlatformException(code: 'CAMERA_VIDEO_UNAVAILABLE');
    }
    if (path == file.path) return file;
    preparedPath = path;
    await releaseAttachmentSelection(file.path);
    return XFile(path, mimeType: 'video/mp4');
  } on Object {
    if (preparedPath != null) await releaseAttachmentSelection(preparedPath);
    await releaseAttachmentSelection(file.path);
    rethrow;
  }
}
