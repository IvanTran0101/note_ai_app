import '../auth/current_user.dart';
import '../../domain/notes/note_repository.dart';
import '../notes/note_application.dart';
import 'dashboard_overview.dart';

/// Application query contract consumed by the Presentation Dashboard state.
abstract interface class IDashboardOverviewQuery {
  /// Loads an overview for the authenticated user and recent-note limit.
  Future<DashboardOverview> execute({required int recentLimit});
}

/// Builds a Dashboard projection from the existing Note repository contract.
///
/// The query owns projection concerns such as ordering and limiting. It does
/// not introduce a Dashboard Domain concept or change note persistence.
final class GetDashboardOverview implements IDashboardOverviewQuery {
  /// Creates a query for notes owned by the current user.
  const GetDashboardOverview({
    required this.noteRepository,
    required this.currentUser,
  });

  /// Existing Domain repository contract used as the source of truth.
  final INoteRepository noteRepository;

  /// Current identity used to scope the projection.
  final ICurrentUser currentUser;

  @override
  Future<DashboardOverview> execute({required int recentLimit}) async {
    if (recentLimit <= 0) {
      throw ArgumentError.value(
        recentLimit,
        'recentLimit',
        'must be greater than zero',
      );
    }

    final String userId = currentUser.requiredUserId;
    final List<NoteDto> notes = (await noteRepository.findByOwnerId(userId))
        .map(NoteDto.fromDomain)
        .toList();
    notes.sort(_compareByUpdatedAtDescending);

    final int recentCount = notes.length < recentLimit
        ? notes.length
        : recentLimit;
    return DashboardOverview(
      totalNotes: notes.length,
      recentNotes: notes.take(recentCount).toList(growable: false),
      lastUpdatedAt: notes.isEmpty ? null : notes.first.updatedAt,
    );
  }

  static int _compareByUpdatedAtDescending(NoteDto a, NoteDto b) {
    final int byUpdatedAt = b.updatedAt.compareTo(a.updatedAt);
    if (byUpdatedAt != 0) {
      return byUpdatedAt;
    }
    // A stable tie-break keeps the projection deterministic when timestamps
    // have the same precision or were restored from equal persisted values.
    return a.id.compareTo(b.id);
  }
}
