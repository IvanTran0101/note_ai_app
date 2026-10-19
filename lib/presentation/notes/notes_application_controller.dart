import '../../application/attachments/attachment_application.dart';
import '../../application/attachments/attachment_input.dart';
import '../../application/notes/note_application.dart';
import '../../application/notes/note_editor_snapshot.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import '../../application/note_intelligence/summary_consent_app_service.dart';
import '../../application/notes/note_access.dart';
import '../../application/notes/note_security_service.dart';
import '../../application/notes/note_sharing_app_service.dart';
import '../../domain/notes/note_document.dart';

abstract interface class DocumentNotesController {
  Future<NoteDto> saveDocumentSnapshot(
    NoteDto selected,
    String title,
    NoteDocument document,
  );
  Future<NoteDto> createDocumentNote({
    required String title,
    required NoteDocument document,
  });
}

extension DocumentNoteCopy on NotesApplicationController {
  Future<NoteDto> createSnapshotNote({
    required String title,
    required String content,
    NoteDocument? document,
  }) async {
    if (document == null) return createNote(title: title, content: content);
    final Object controller = this;
    if (controller is! DocumentNotesController ||
        content != document.plainText) {
      throw const NoteDocumentStorageUnavailable();
    }
    return controller.createDocumentNote(title: title, document: document);
  }
}

abstract interface class AttachmentNotesController {
  AttachmentApplicationService? get attachments;
  Future<List<AttachmentInput>> pickAttachments(AttachmentSource source);
}

abstract interface class SharingNotesController {
  Future<List<NoteDto>> listSharedNotes();
  NoteSharingAppService? get sharing;
}

abstract interface class SnapshotNotesController {
  Future<NoteDto> saveEditorSnapshot(
    NoteDto selected,
    String title,
    String content,
  );
}

/// Optional security seam preserves simple non-security controller consumers.
abstract interface class SecuredNotesController {
  NoteSecurityService? get noteSecurity;
  Stream<void> get securityChanges;
  int get accessGeneration;
  int get sessionGeneration;
  bool get securityServerAvailable;
  Future<NoteDto> readNote(String id);
  NoteAccessCapabilities capabilitiesFor(NoteDto note);
}

/// A narrow Presentation seam around the Note application use cases.
///
/// The concrete application service is the default production dependency.
/// This seam keeps widget tests independent from repositories, file storage,
/// and the local-LLM implementation.
abstract interface class NotesApplicationController {
  /// Optional session consent actions; unavailable for unwired/local test seams.
  SummaryConsentAppService? get summaryConsent;

  Future<List<NoteDto>> listNotes();

  Future<NoteDto> createNote({required String title, required String content});

  Future<NoteDto> renameNote({required String noteId, required String title});

  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  });

  Future<void> deleteNote(String noteId);

  /// Returns summary text instead of exposing the Domain [Summary] type to
  /// the widget.
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  });
}

/// Optional Module 02 operations used by the production editor and dashboard.
/// The older test seam remains usable without implementing the new flows.
abstract interface class NotesModule02Controller {
  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  });

  Future<NoteDto> setPinned({required String noteId, required bool pinned});

  Future<NoteLayoutPreference> getNoteLayout();

  Future<void> setNoteLayout(NoteLayoutPreference layout);
}

/// Presentation adapter for the Application service.
///
/// It intentionally contains no Infrastructure knowledge. The root can pass
/// [NoteApplicationService] directly to [NotesPage], while tests can inject a
/// [NotesApplicationController] fake.
final class NoteApplicationServiceController
    implements
        NotesApplicationController,
        DocumentNotesController,
        NotesModule02Controller,
        SecuredNotesController,
        SharingNotesController,
        SnapshotNotesController,
        AttachmentNotesController {
  const NoteApplicationServiceController(
    this._service, {
    this.summaryConsent,
    this.securityForCurrentAccount,
    this.securityEvents = const Stream<void>.empty(),
    this.readAccessGeneration,
    this.readSessionGeneration,
    this.serverAvailable = false,
    this.sharingForCurrentAccount,
    this.attachmentsForCurrentAccount,
    this.attachmentPicker,
  });

  final AttachmentApplicationService? Function()? attachmentsForCurrentAccount;
  final Future<List<AttachmentInput>> Function(AttachmentSource)?
  attachmentPicker;
  @override
  AttachmentApplicationService? get attachments =>
      attachmentsForCurrentAccount?.call();
  @override
  Future<List<AttachmentInput>> pickAttachments(AttachmentSource source) async {
    final pick = attachmentPicker;
    if (pick == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
    }
    return pick(source);
  }

  final NoteSecurityService Function()? securityForCurrentAccount;
  final Stream<void> securityEvents;
  final int Function()? readAccessGeneration;
  final int Function()? readSessionGeneration;
  final bool serverAvailable;
  final NoteSharingAppService? Function()? sharingForCurrentAccount;
  @override
  NoteSharingAppService? get sharing => sharingForCurrentAccount?.call();
  @override
  Future<List<NoteDto>> listSharedNotes() => _service.listSharedNotes();
  @override
  Future<NoteDto> saveEditorSnapshot(
    NoteDto selected,
    String title,
    String content,
  ) => _service.saveEditorSnapshot(selected, title, content);
  @override
  Stream<void> get securityChanges => securityEvents;
  @override
  int get accessGeneration => readAccessGeneration?.call() ?? 0;
  @override
  int get sessionGeneration => readSessionGeneration?.call() ?? 0;
  @override
  bool get securityServerAvailable => serverAvailable;
  @override
  NoteSecurityService? get noteSecurity {
    try {
      return securityForCurrentAccount?.call();
    } on NoteSecurityFailure {
      return null;
    }
  }

  @override
  Future<NoteDto> readNote(String id) => _service.readNote(id);
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      _service.capabilitiesFor(note);

  final NoteApplicationService _service;

  @override
  final SummaryConsentAppService? summaryConsent;

  @override
  Future<List<NoteDto>> listNotes() => _service.listNotes();

  @override
  Future<NoteDto> createNote({required String title, required String content}) {
    return _service.createNote(title: title, content: content);
  }

  @override
  Future<NoteDto> createDocumentNote({
    required String title,
    required NoteDocument document,
  }) => _service.createNote(
    title: title,
    content: document.plainText,
    document: document,
  );

  @override
  Future<NoteDto> saveDocumentSnapshot(
    NoteDto selected,
    String title,
    NoteDocument document,
  ) => _service.saveDocumentSnapshot(selected, title, document);

  @override
  Future<NoteDto> renameNote({required String noteId, required String title}) {
    return _service.renameNote(noteId: noteId, title: title);
  }

  @override
  Future<NoteDto> replaceContent({
    required String noteId,
    required String content,
  }) {
    return _service.replaceContent(noteId: noteId, content: content);
  }

  @override
  Future<NoteDto> updateNote({
    required String noteId,
    required String title,
    required String content,
  }) => _service.updateNote(noteId: noteId, title: title, content: content);

  @override
  Future<NoteDto> setPinned({required String noteId, required bool pinned}) =>
      _service.setPinned(noteId: noteId, pinned: pinned);

  @override
  Future<NoteLayoutPreference> getNoteLayout() => _service.getNoteLayout();

  @override
  Future<void> setNoteLayout(NoteLayoutPreference layout) =>
      _service.setNoteLayout(layout);

  @override
  Future<void> deleteNote(String noteId) => _service.deleteNote(noteId);

  @override
  Future<String> summarizeNote(
    String noteId, {
    NoteDto? selectedSnapshot,
    SummaryRunScope? scope,
  }) async {
    try {
      final summary = await _service.summarizeNote(
        noteId,
        selectedSnapshot: selectedSnapshot,
        scope: scope,
      );
      return summary.text;
    } on SummaryRunFailure {
      rethrow;
    } on NoteSecurityFailure {
      throw const SummaryRunFailure(SummaryRunFailureCode.noteLocked);
    } on Object {
      throw const SummaryRunFailure(SummaryRunFailureCode.unexpected);
    }
  }
}
