import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../application/attachments/attachment_media.dart';

/// Rendering only. The Application-owned handle supplies a transient local host.
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
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      frame.src = handle.uri!.toString();
      frame.title = 'Attachment preview';
      frame.style.width = '100%';
      frame.style.height = '100%';
      frame.style.border = '0';
      frame.setAttribute(
        'sandbox',
        'allow-scripts allow-same-origin allow-downloads',
      );
      frame.setAttribute('referrerpolicy', 'no-referrer');
    },
  );
}
