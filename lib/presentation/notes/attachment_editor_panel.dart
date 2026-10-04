import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/attachments/attachment_application.dart';
import '../../application/attachments/attachment_input.dart';
import '../../application/attachments/local_attachment_draft.dart';
import '../../application/notes/note_access.dart';
import '../../application/notes/note_application.dart';
import 'notes_application_controller.dart';

/// Local Pending flow. Binary actions never replace the editor's text draft.
/// No cloud Ready claim is made until the verified backend is available.
final class AttachmentEditorPanel extends StatefulWidget {
  const AttachmentEditorPanel({
    super.key,
    required this.note,
    required this.controller,
    required this.security,
    required this.enabled,
  });
  final NoteDto note;
  final AttachmentNotesController controller;
  final SecuredNotesController? security;
  final bool enabled;
  @override
  State<AttachmentEditorPanel> createState() => _AttachmentEditorPanelState();
}

final class _AttachmentEditorPanelState extends State<AttachmentEditorPanel> {
  StreamSubscription<void>? _subscription;
  List<LocalAttachmentDraft> _pending = const [];
  Uint8List? _preview;
  LocalAttachmentDraft? _previewDraft;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  bool get _allowed =>
      widget.enabled &&
      widget.note.contentAvailable &&
      widget.security?.capabilitiesFor(widget.note).canManage == true;
  AttachmentApplicationService? get _service => widget.controller.attachments;

  @override
  void initState() {
    super.initState();
    _listen();
    unawaited(_reload());
  }

  void _clearPreview() {
    final bytes = _preview;
    if (bytes != null) {
      // Image.memory also owns a decoded global-cache entry. Evict it when
      // closing/locking, in addition to wiping our encoded plaintext buffer.
      unawaited(
        ResizeImage(MemoryImage(bytes), width: 1024, height: 1024).evict(),
      );
      bytes.fillRange(0, bytes.length, 0);
    }
    _preview = null;
    _previewDraft = null;
  }

  void _listen() {
    _subscription = widget.security?.securityChanges.listen((_) {
      _generation++;
      _clearPreview();
      if (!mounted) return;
      setState(() {
        _pending = const [];
        _error = null;
        _busy = false;
      });
      unawaited(_reload());
    });
  }

  @override
  void didUpdateWidget(covariant AttachmentEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.security != widget.security) {
      unawaited(_subscription?.cancel());
      _listen();
    }
    if (oldWidget.note != widget.note ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.controller != widget.controller) {
      _generation++;
      _clearPreview();
      _pending = const [];
      _busy = false;
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final generation = _generation;
    if (!_allowed) return;
    try {
      final pending =
          await _service?.pending(widget.note.id) ??
          const <LocalAttachmentDraft>[];
      if (mounted && generation == _generation && _allowed) {
        setState(() => _pending = pending);
      }
    } on Object {
      if (mounted && generation == _generation && _allowed) {
        setState(
          () => _error = 'Local attachments are unavailable. Unlock or retry.',
        );
      }
    }
  }

  Future<void> _run(
    Future<void> Function(AttachmentApplicationService) action,
  ) async {
    if (_busy || !_allowed) return;
    final service = _service;
    if (service == null) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
      _clearPreview();
    });
    try {
      await action(service);
    } on NoteSecurityFailure catch (failure) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = failure.code == NoteSecurityFailureCode.unavailable
              ? 'Cloud attachments are unavailable. This file remains Pending on this device.'
              : 'Attachment access changed. Unlock and retry.',
        );
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'Attachment operation failed. Check file type, size and note quota, then retry. Completed local drafts are retained.',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        await _reload();
      }
    }
  }

  Future<void> _pick(AttachmentSource source) async {
    final identity = widget.note.identity;
    await _run(
      (service) => service.pickAndStage(
        widget.note.id,
        () => widget.controller.pickAttachments(source),
      ),
    );
    // A native picker can cause a lifecycle lock/rebuild while it is open.
    if (mounted && _allowed && widget.note.identity == identity) {
      await _reload();
    }
  }

  Future<void> _cancel(LocalAttachmentDraft draft) async {
    final generation = _generation;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove local attachment?'),
        content: const Text(
          'The pending encrypted copy on this device will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || generation != _generation) return;
    await _run((service) => service.cancel(widget.note.id, draft.cacheId));
  }

  Future<void> _open(LocalAttachmentDraft draft) => _run((service) async {
    final generation = _generation;
    final image = draft.mimeType.startsWith('image/');
    final text = draft.mimeType == 'text/plain' || draft.mimeType == 'text/csv';
    if (!image && !text) {
      setState(
        () => _error = 'Video and PDF preview are not available yet. The encrypted file is retained.',
      );
      return;
    }
    final limit = image ? 10 * 1024 * 1024 : 64 * 1024;
    final end = draft.sizeBytes < limit ? draft.sizeBytes : limit;
    final bytes = Uint8List(end);
    var offset = 0;
    try {
      await for (final chunk in service.readLocal(
        widget.note.id,
        draft.cacheId,
        end: end,
      )) {
        try {
          if (!mounted || generation != _generation || !_allowed) return;
          if (offset + chunk.length > end) {
            throw StateError('Preview exceeds its bound.');
          }
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        } finally {
          chunk.fillRange(0, chunk.length, 0);
        }
      }
      if (offset != end) throw StateError('Incomplete preview.');
      if (mounted && generation == _generation && _allowed) {
        setState(() {
          _preview = Uint8List.fromList(bytes);
          _previewDraft = draft;
        });
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  @override
  void dispose() {
    _generation++;
    _clearPreview();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed || _service == null) return const SizedBox.shrink();
    final preview = _preview, previewDraft = _previewDraft;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Attachments')),
                PopupMenuButton<AttachmentSource>(
                  enabled: !_busy,
                  tooltip: 'Add attachment',
                  icon: const Icon(Icons.attach_file),
                  onSelected: (source) => unawaited(_pick(source)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: AttachmentSource.files,
                      child: Text('Choose files'),
                    ),
                    PopupMenuItem(
                      value: AttachmentSource.gallery,
                      child: Text('Gallery'),
                    ),
                    PopupMenuItem(
                      value: AttachmentSource.cameraPhoto,
                      child: Text('Take photo'),
                    ),
                    PopupMenuItem(
                      value: AttachmentSource.cameraVideo,
                      child: Text('Record video'),
                    ),
                  ],
                ),
              ],
            ),
            const Text(
              'Images 10 MiB · MP4 50 MiB · PDF/TXT/CSV 20 MiB. Up to 10 files / 100 MiB per note.',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            for (final draft in _pending)
              ListTile(
                title: Text(draft.fileName),
                subtitle: Text(
                  'Pending on this device · ${draft.sizeBytes} bytes',
                ),
                onTap: _busy ? null : () => unawaited(_open(draft)),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Retry upload',
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _run((service) async {
                                await service.retry(
                                  widget.note.id,
                                  draft.cacheId,
                                );
                              }),
                            ),
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      tooltip: 'Remove local attachment',
                      onPressed: _busy ? null : () => unawaited(_cancel(draft)),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            for (final attachment in widget.note.attachments)
              ListTile(
                title: Text(attachment.fileName),
                subtitle: const Text(
                  'Linked metadata · remote preview unavailable',
                ),
              ),
            if (preview != null && previewDraft != null) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(_clearPreview),
                  child: const Text('Close preview'),
                ),
              ),
              if (previewDraft.mimeType.startsWith('image/'))
                Image.memory(
                  preview,
                  height: 220,
                  cacheWidth: 1024,
                  cacheHeight: 1024,
                  errorBuilder: (_, _, _) =>
                      const Text('Image preview unavailable.'),
                )
              else
                SelectableText(utf8.decode(preview, allowMalformed: true)),
              if (preview.length < previewDraft.sizeBytes)
                const Text('Showing the first 64 KiB.'),
            ],
          ],
        ),
      ),
    );
  }
}
