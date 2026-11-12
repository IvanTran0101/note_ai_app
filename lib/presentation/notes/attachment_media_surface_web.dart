import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../application/attachments/attachment_media.dart';

/// Rendering only. The Application-owned handle supplies a transient local host.
final class AttachmentMediaSurface extends StatefulWidget {
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
  State<AttachmentMediaSurface> createState() => _AttachmentMediaSurfaceState();
}

final class _AttachmentMediaSurfaceState extends State<AttachmentMediaSurface> {
  web.HTMLIFrameElement? _frame;
  String _theme = 'light';
  late final JSFunction _loaded = ((web.Event _) => _applyTheme()).toJS;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light';
    _applyTheme();
  }

  void _applyTheme() {
    if (!mounted) return;
    // The existing viewer is same-origin. This changes only its public CSS
    // palette; capability, sandbox and attachment access stay with their owners.
    _frame?.contentDocument?.documentElement?.setAttribute(
      'data-theme',
      _theme,
    );
  }

  @override
  void dispose() {
    _frame?.removeEventListener('load', _loaded);
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      _frame?.removeEventListener('load', _loaded);
      _frame = frame;
      frame.addEventListener('load', _loaded);
      frame.src = widget.handle.uri!.toString();
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
