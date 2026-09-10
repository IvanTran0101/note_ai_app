import '../notes/note_application.dart';

/// Immutable application read model for the Dashboard overview.
///
/// This is a projection for a screen, not a Domain aggregate. It contains
/// only facts currently available from the primitive-first Note model.
final class DashboardOverview {
  /// Creates a validated, copy-safe dashboard projection.
  factory DashboardOverview({
    required int totalNotes,
    required List<NoteDto> recentNotes,
    required DateTime? lastUpdatedAt,
  }) {
    if (totalNotes < 0) {
      throw ArgumentError.value(
        totalNotes,
        'totalNotes',
        'must not be negative',
      );
    }
    if (recentNotes.length > totalNotes) {
      throw ArgumentError.value(
        recentNotes.length,
        'recentNotes',
        'cannot contain more items than totalNotes',
      );
    }
    if (totalNotes == 0 && lastUpdatedAt != null) {
      throw ArgumentError.value(
        lastUpdatedAt,
        'lastUpdatedAt',
        'must be null when totalNotes is zero',
      );
    }
    if (totalNotes > 0 && lastUpdatedAt == null) {
      throw ArgumentError.value(
        lastUpdatedAt,
        'lastUpdatedAt',
        'must be provided when totalNotes is positive',
      );
    }
    return DashboardOverview._(
      totalNotes: totalNotes,
      recentNotes: List<NoteDto>.unmodifiable(recentNotes),
      lastUpdatedAt: lastUpdatedAt,
    );
  }

  const DashboardOverview._({
    required this.totalNotes,
    required this.recentNotes,
    required this.lastUpdatedAt,
  });

  /// Number of notes owned by the current application user.
  final int totalNotes;

  /// Most recently updated note projections, already ordered by the query.
  final List<NoteDto> recentNotes;

  /// Timestamp of the most recently updated note, or null when empty.
  final DateTime? lastUpdatedAt;

  /// Whether the current owner has no notes.
  bool get isEmpty => totalNotes == 0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DashboardOverview &&
            other.totalNotes == totalNotes &&
            _sameNotes(other.recentNotes, recentNotes) &&
            other.lastUpdatedAt == lastUpdatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(totalNotes, Object.hashAll(recentNotes), lastUpdatedAt);

  @override
  String toString() {
    return 'DashboardOverview(totalNotes: $totalNotes, '
        'recentNotes: $recentNotes, lastUpdatedAt: $lastUpdatedAt)';
  }

  static bool _sameNotes(List<NoteDto> a, List<NoteDto> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}
