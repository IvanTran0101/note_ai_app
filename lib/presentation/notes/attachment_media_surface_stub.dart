import 'package:flutter/widgets.dart';

import '../../application/attachments/attachment_media.dart';

final class AttachmentMediaSurface extends StatelessWidget {
  const AttachmentMediaSurface({
    super.key,
    required this.handle,
    required this.mime,
    required this.size,
    required this.read,
  });
  final AttachmentMediaHandle handle;
  final String mime;
  final int size;
  final Stream<List<int>> Function(int, int) read;
  @override
  Widget build(BuildContext context) =>
      const Text('Media preview is unavailable on this platform.');
}
