part of 'attachment_application.dart';

extension _AttachmentApplicationMedia on AttachmentApplicationService {
  Future<AttachmentMediaHandle> _openMedia(
    String reference, {
    Attachment? attachment,
    LocalAttachmentDraft? draft,
    bool exportFile = false,
  }) async {
    final bridge = mediaBridge;
    if (bridge == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    final b = attachment == null
        ? await _capture(reference)
        : await _readBinding(reference, attachment);
    if (exportFile && b.actorId != b.note.ownerId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
    }
    final id = attachment?.id ?? draft!.cacheId;
    final key = jsonEncode([reference, id]);
    _mediaLeases[key]?.cancel();
    final lease = _AttachmentMediaLease(() => cancelRemoteRead?.call(b, id));
    _mediaLeases[key] = lease;
    void guard() {
      if (lease.cancelled) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
      }
      requireAccess(b, NoteOperation.attachmentRead);
      if (exportFile) requireAccess(b, NoteOperation.export);
    }

    Future<void> authorize() async {
      guard();
      if (attachment != null) {
        final current = await _readBinding(reference, attachment);
        _requireSameReader(b, current);
      } else {
        await _fresh(b);
      }
      guard();
    }

    Stream<List<int>> read(int start, int end) async* {
      await authorize();
      final source = attachment == null
          ? readLocal(reference, draft!.cacheId, start: start, end: end)
          : readAssociated(
              reference,
              attachment,
              start: start,
              end: end,
              exportFile: exportFile,
            );
      await for (final bytes in source) {
        try {
          guard();
        } on Object {
          bytes.fillRange(0, bytes.length, 0);
          rethrow;
        }
        yield bytes;
        guard();
      }
    }

    try {
      await authorize();
      final handle = await bridge.open(
        AttachmentMediaRequest(
          fileName: attachment?.fileName ?? draft!.fileName,
          mimeType: attachment?.mimeType ?? draft!.mimeType,
          sizeBytes: attachment?.sizeBytes ?? draft!.sizeBytes,
          read: read,
          authorize: authorize,
          exportFile: exportFile,
        ),
      );
      lease.handle = handle;
      if (handle.exported) {
        if (identical(_mediaLeases[key], lease)) _mediaLeases.remove(key);
        return handle;
      }
      guard();
      return _ScopedAttachmentMediaHandle(handle, () async {
        lease.cancel();
        if (identical(_mediaLeases[key], lease)) _mediaLeases.remove(key);
        await lease.closing;
      });
    } on Object {
      lease.cancel();
      if (identical(_mediaLeases[key], lease)) _mediaLeases.remove(key);
      rethrow;
    }
  }
}

final class _AttachmentMediaLease {
  _AttachmentMediaLease(this.abort);
  final void Function() abort;
  AttachmentMediaHandle? handle;
  Future<void>? closing;
  bool cancelled = false;
  void cancel() {
    if (!cancelled) {
      cancelled = true;
      abort();
    }
    // Bridge handles are idempotent. Closing the worker/server stops queued reads.
    final current = handle;
    if (current != null && closing == null) {
      closing = current.close();
      unawaited(closing!.catchError((Object _) {}));
    }
  }
}

final class _ScopedAttachmentMediaHandle implements AttachmentMediaHandle {
  _ScopedAttachmentMediaHandle(this.inner, this._close);
  final AttachmentMediaHandle inner;
  final Future<void> Function() _close;
  bool _closed = false;
  @override
  Uri? get uri => inner.uri;
  @override
  bool get exported => inner.exported;
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _close();
  }
}
