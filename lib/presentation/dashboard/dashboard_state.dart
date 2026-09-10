import '../../application/dashboard/dashboard_overview.dart';

/// Lifecycle states exposed by the Dashboard Presentation seam.
enum DashboardLoadStatus { idle, loading, ready, empty, failure }

/// Immutable state consumed by a future DashboardPage.
final class DashboardState {
  const DashboardState._({required this.status, this.overview, this.error});

  /// Initial state before the first load starts.
  const DashboardState.idle() : this._(status: DashboardLoadStatus.idle);

  /// State while the application query is running.
  const DashboardState.loading() : this._(status: DashboardLoadStatus.loading);

  /// State containing at least one note.
  const DashboardState.ready(DashboardOverview overview)
    : this._(status: DashboardLoadStatus.ready, overview: overview);

  /// State containing a valid but empty overview.
  const DashboardState.empty(DashboardOverview overview)
    : this._(status: DashboardLoadStatus.empty, overview: overview);

  /// State containing the original query error for Presentation mapping.
  const DashboardState.failure(Object error)
    : this._(status: DashboardLoadStatus.failure, error: error);

  /// Current lifecycle status.
  final DashboardLoadStatus status;

  /// Latest successful projection, when one exists.
  final DashboardOverview? overview;

  /// Query failure, only populated for [DashboardLoadStatus.failure].
  final Object? error;

  bool get isLoading => status == DashboardLoadStatus.loading;

  bool get hasError => status == DashboardLoadStatus.failure;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DashboardState &&
            other.status == status &&
            other.overview == overview &&
            identical(other.error, error);
  }

  @override
  int get hashCode => Object.hash(status, overview, error);

  @override
  String toString() {
    return 'DashboardState(status: $status, overview: $overview, '
        'error: $error)';
  }
}
