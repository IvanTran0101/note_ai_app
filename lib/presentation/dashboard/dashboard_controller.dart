import 'dart:async';

import '../../application/dashboard/dashboard_overview.dart';
import '../../application/dashboard/get_dashboard_overview.dart';
import 'dashboard_state.dart';

/// Listener used by a Dashboard widget without adding a state-management
/// dependency to the project.
typedef DashboardStateListener = void Function(DashboardState state);

/// Coordinates Dashboard loading and exposes an immutable Presentation state.
///
/// The controller is deliberately framework-light: it has no repository,
/// JSON, Flutter widget, or Infrastructure knowledge. Concurrent loads share
/// one future, and query errors become [DashboardState.failure] so a widget can
/// render and retry them without an uncaught asynchronous exception.
final class DashboardController {
  /// Creates a controller using [query] and a positive recent-note limit.
  DashboardController({required this._query, int recentLimit = 5})
    : _recentLimit = _validateRecentLimit(recentLimit);

  final IDashboardOverviewQuery _query;
  final int _recentLimit;
  final List<DashboardStateListener> _listeners = <DashboardStateListener>[];

  DashboardState _state = const DashboardState.idle();
  Future<DashboardState>? _inFlight;
  bool _disposed = false;

  /// Current immutable state.
  DashboardState get state => _state;

  /// Configured number of recent notes requested by [load].
  int get recentLimit => _recentLimit;

  /// Whether this controller has been disposed.
  bool get isDisposed => _disposed;

  /// Registers a listener. Duplicate registrations are ignored.
  void addListener(DashboardStateListener listener) {
    _ensureActive();
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// Removes a previously registered listener.
  void removeListener(DashboardStateListener listener) {
    _listeners.remove(listener);
  }

  /// Loads the overview, sharing an already-running request when present.
  Future<DashboardState> load() {
    _ensureActive();
    final Future<DashboardState>? current = _inFlight;
    if (current != null) {
      return current;
    }

    final Future<DashboardState> started = _load();
    _inFlight = started;
    unawaited(
      started.then<void>(
        (_) => _clearInFlight(started),
        onError: (Object error, StackTrace stackTrace) {
          _clearInFlight(started);
        },
      ),
    );
    return started;
  }

  /// Retries the same query with the configured recent-note limit.
  Future<DashboardState> retry() => load();

  /// Stops notifications and releases listener references.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _listeners.clear();
  }

  Future<DashboardState> _load() async {
    _emit(const DashboardState.loading());
    try {
      final DashboardOverview overview = await _query.execute(
        recentLimit: _recentLimit,
      );
      if (_disposed) {
        return _state;
      }
      final DashboardState next = overview.isEmpty
          ? DashboardState.empty(overview)
          : DashboardState.ready(overview);
      _emit(next);
      return next;
    } on Object catch (error) {
      if (_disposed) {
        return _state;
      }
      final DashboardState next = DashboardState.failure(error);
      _emit(next);
      return next;
    }
  }

  void _emit(DashboardState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    final List<DashboardStateListener> listeners =
        List<DashboardStateListener>.of(_listeners);
    for (final DashboardStateListener listener in listeners) {
      listener(next);
    }
  }

  void _clearInFlight(Future<DashboardState> operation) {
    if (identical(_inFlight, operation)) {
      _inFlight = null;
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('DashboardController is disposed');
    }
  }

  static int _validateRecentLimit(int value) {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'recentLimit',
        'must be greater than zero',
      );
    }
    return value;
  }
}
