import '../../application/note_intelligence/summary_consent_app_service.dart';
import '../../application/note_intelligence/summary_run_context.dart';
import '../../application/notes/note_application.dart';

/// Whether the Summary action for the open note can start, and if not, why.
///
/// The reasons are presentation-level: they describe what the user can do about
/// the state (save, resolve, sign in, allow cloud summaries) instead of leaking
/// a transport or provider condition. [canStart] is true for exactly the states
/// where a user action may dispatch a run.
enum NoteSummaryAvailability {
  /// A run may start now: consent is granted, or the composition needs none.
  ready,

  /// A run may start, but the user must allow cloud summaries first. It stays
  /// actionable so the primary button can open the disclosure dialog.
  consentRequired,

  /// There is no saved note yet, so there is no revision to summarize.
  draft,

  /// The editor holds unsaved edits.
  dirty,

  /// A sync conflict must be resolved before the note can be summarized.
  conflict,

  /// The runtime cannot summarize in this composition (local Web, missing or
  /// incompatible remote configuration).
  unavailable,

  /// The account must authenticate again before a run can start.
  signInRequired;

  /// Whether the primary, retry, and regenerate actions may dispatch a run.
  bool get canStart => this == ready || this == consentRequired;
}

/// Editor facts a Summary run must revalidate before it grants or dispatches.
final class NoteSummaryEditorFacts {
  const NoteSummaryEditorFacts({
    required this.note,
    required this.isDirty,
    required this.hasConflict,
  });

  /// The exact saved revision the editor currently shows, or null for a draft.
  final NoteDto? note;

  /// Whether the editor holds edits that are not persisted yet.
  final bool isDirty;

  /// Whether a sync conflict currently blocks the note.
  final bool hasConflict;
}

/// Availability for one editor revision and one live consent service.
///
/// The editor facts win over the runtime: an unsaved or conflicted revision is
/// reported as such even when consent would also be required, because saving or
/// resolving is the action the user can take immediately. A null [consent]
/// service is the legacy/local seam: it never opens a dialog, but a local
/// runtime that is unavailable on this build is still reported as such.
NoteSummaryAvailability noteSummaryAvailability({
  required SummaryConsentAppService? consent,
  required bool hasSavedNote,
  required bool isDirty,
  required bool hasConflict,
}) {
  if (!hasSavedNote) {
    return NoteSummaryAvailability.draft;
  }
  if (isDirty) {
    return NoteSummaryAvailability.dirty;
  }
  if (hasConflict) {
    return NoteSummaryAvailability.conflict;
  }
  if (consent == null) {
    return NoteSummaryAvailability.ready;
  }
  final SummaryRunFailureCode? reason = consent.unavailableReason;
  if (reason == SummaryRunFailureCode.unauthorized) {
    return NoteSummaryAvailability.signInRequired;
  }
  if (!consent.requiresCloudConsent) {
    return reason == null
        ? NoteSummaryAvailability.ready
        : NoteSummaryAvailability.unavailable;
  }
  if (reason != null) {
    return NoteSummaryAvailability.unavailable;
  }
  return consent.state == SummaryConsentStatus.granted
      ? NoteSummaryAvailability.ready
      : NoteSummaryAvailability.consentRequired;
}
