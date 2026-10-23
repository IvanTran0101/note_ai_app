import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../application/attachments/attachment_application.dart';
import '../../application/attachments/attachment_input.dart';
import '../../application/attachments/attachment_media.dart';
import '../../application/attachments/attachment_transfer.dart';
import '../../application/attachments/local_attachment_draft.dart';
import '../../application/notes/note_access.dart';
import '../../application/notes/note_application.dart';
import '../../domain/notes/attachment.dart';
import 'attachment_file_row.dart';
import 'attachment_editor_controller.dart';
import 'attachment_media_surface.dart';
import 'notes_application_controller.dart';
part 'attachment_inline.dart';
part 'attachment_inline_picker.dart';
part 'attachment_inline_transfer.dart';
part 'attachment_editor_actions.dart';
part 'attachment_editor_rows.dart';
part 'attachment_editor_preview.dart';

/// Binary actions use Application and the canonical writer. An ordinary text
/// ACK does not cancel a transfer or replace the editor's unsaved text.
final class AttachmentEditorPanel extends StatefulWidget {
  const AttachmentEditorPanel({
    super.key,
    required this.note,
    required this.controller,
    required this.security,
    required this.enabled,
    this.onChanged,
    this.onResumeProtected,
    this.onBeforePick,
    this.inlineController,
    this.inlineLayout = false,
    this.hiddenOwner = false,
    this.onFilesPicked,
  });
  final NoteDto note;
  final AttachmentNotesController controller;
  final SecuredNotesController? security;
  final bool enabled;
  final ValueChanged<NoteDto>? onChanged;
  final Future<void> Function()? onResumeProtected;
  final Future<bool> Function()? onBeforePick;
  final AttachmentEditorController? inlineController;
  final bool inlineLayout;
  final bool hiddenOwner;
  final Future<bool> Function(String blockId, List<String> attachmentIds)?
  onFilesPicked;
  @override
  State<AttachmentEditorPanel> createState() => _AttachmentEditorPanelState();
}

final class _AttachmentEditorPanelState extends State<AttachmentEditorPanel> {
  StreamSubscription<void>? _securityEvents;
  StreamSubscription<AttachmentProgress>? _progressEvents;
  Timer? _refresh;
  List<LocalAttachmentDraft> _pending = const [];
  final _progress = <String, AttachmentProgress>{};
  final _ready = <String>{}, _working = <String>{};
  final _retryAfter = <String, DateTime>{};
  bool _loading = false;
  String? _error;
  String? _inlineErrorBlock;
  int _generation = 0;
  _AttachmentItem? _previewItem;
  Uint8List? _preview;
  AttachmentMediaHandle? _media;
  AttachmentApplicationService? _previewService;
  String? _previewReference;
  bool _exporting = false;
  NoteAccessCapabilities get _capabilities =>
      widget.security?.capabilitiesFor(widget.note) ??
      const NoteAccessCapabilities();
  bool get _allowed =>
      widget.enabled && widget.note.contentAvailable && _capabilities.canRead;
  bool get _canWrite => _allowed && _capabilities.canManage;
  bool get _busy => _working.isNotEmpty;
  String get _reference => widget.note.reference;
  AttachmentApplicationService? get _service => widget.controller.attachments;
  // Picker Activity transitions can replace a lease while keeping the resource
  // authority. Error feedback may resume only for that identical live scope.
  ({
    int? session,
    String note,
    bool protected,
    int protectionRevision,
    int? accessRevision,
    int contentRevision,
  })
  get _pickerAuthority => (
    session: widget.security?.sessionGeneration,
    note: widget.note.reference,
    protected: widget.note.isProtected,
    protectionRevision: widget.note.protectionRevision,
    accessRevision: widget.note.share?.accessRevision,
    contentRevision: widget.note.contentRevision,
  );
  bool _current(int generation) =>
      mounted && _allowed && generation == _generation;
  void _update(VoidCallback change) {
    if (!mounted) return;
    setState(change);
    widget.inlineController?.refresh();
  }

  void _bindInlineController() {
    widget.inlineController?.bind(
      owner: this,
      buildBlock: _buildInlineBlock,
      buildLegacy: _buildPanel,
      openPicker: _showInlinePicker,
      readAttachmentIds: () => {
        ...widget.note.attachments.map((item) => item.id),
        ..._pending.map((item) => item.cacheId),
      }.toList(growable: false),
    );
  }

  @override
  void initState() {
    super.initState();
    _bindInlineController();
    _listen();
    unawaited(_reload());
    _refresh = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_reload()),
    );
  }

  void _listen() {
    _securityEvents = widget.security?.securityChanges.listen((_) {
      _invalidate();
      unawaited(_reload());
    });
    _progressEvents = _service?.progress.listen((event) {
      if (!_allowed || !mounted) return;
      if (_pending.any((p) => p.cacheId == event.id) ||
          widget.note.attachments.any((p) => p.id == event.id)) {
        _update(() => _progress[event.id] = event);
      }
    });
  }

  void _invalidate() {
    _generation++;
    _clearPreview();
    _update(() {
      _pending = const [];
      _ready.clear();
      _progress.clear();
      _working.clear();
      _error = null;
      _inlineErrorBlock = null;
    });
  }

  @override
  void didUpdateWidget(covariant AttachmentEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inlineController != widget.inlineController) {
      oldWidget.inlineController?.unbind(this);
      _bindInlineController();
    }
    final authorityChanged =
        oldWidget.security != widget.security ||
        oldWidget.controller != widget.controller;
    if (authorityChanged) {
      unawaited(_securityEvents?.cancel());
      unawaited(_progressEvents?.cancel());
      _listen();
    }
    if (authorityChanged ||
        oldWidget.note.identity != widget.note.identity ||
        oldWidget.note.protectionRevision != widget.note.protectionRevision ||
        oldWidget.note.isProtected != widget.note.isProtected ||
        oldWidget.note.share != widget.note.share ||
        !_allowed) {
      _invalidate();
    } else if (_previewItem?.attachment case final Attachment attachment) {
      if (!widget.note.attachments.contains(attachment)) _clearPreview();
    }
    unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!_allowed || _loading) return;
    _loading = true;
    final generation = _generation;
    try {
      final service = _service;
      if (service == null) return;
      final pending = _canWrite
          ? await service.pending(_reference)
          : const <LocalAttachmentDraft>[];
      final ready = <String>{};
      for (final attachment in widget.note.attachments) {
        if (!_current(generation)) return;
        if (await service.ready(_reference, attachment)) {
          ready.add(attachment.id);
        }
      }
      if (!_current(generation)) return;
      _update(() {
        _pending = pending;
        _ready
          ..clear()
          ..addAll(ready);
      });
      if (_canWrite && !_busy) {
        for (final draft in pending) {
          if (!_current(generation) || !_canWrite) break;
          if (_shouldRetryDraft(draft) &&
              !(_retryAfter[draft.cacheId]?.isAfter(DateTime.now()) ?? false)) {
            await _retry(draft.cacheId, background: true);
          }
        }
      }
    } on Object {
      // A background refresh never erases ciphertext or an explicit Retry error.
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.inlineController?.unbind(this);
    _refresh?.cancel();
    _clearPreview();
    unawaited(_securityEvents?.cancel());
    unawaited(_progressEvents?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      !_allowed || _service == null || widget.hiddenOwner
      ? const SizedBox.shrink()
      : _buildPanel(context);
}

final class _AttachmentItem {
  _AttachmentItem.local(this.draft) : attachment = null;
  _AttachmentItem.associated(this.attachment) : draft = null;
  final LocalAttachmentDraft? draft;
  final Attachment? attachment;
  String get id => attachment?.id ?? draft!.cacheId;
  String get name => attachment?.fileName ?? draft!.fileName;
  String get mime => attachment?.mimeType ?? draft!.mimeType;
  int get size => attachment?.sizeBytes ?? draft!.sizeBytes;
}
