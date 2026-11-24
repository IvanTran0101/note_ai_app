// Source navigation and the bounded citation-open attempt for the ask-my-notes
// slice.
//
// This part is the natural boundary for "turn one validated citation into one
// synchronous editor reveal": it owns route liveness/close, the single
// 26-second navigation deadline, and the per-attempt rechecks. It keeps the
// shared RAG gateway/service lifetime and the session bindings in [_RagRoot]
// (main_rag_part.dart); no state is duplicated here.
part of 'main.dart';

/// Route liveness and close helpers for the single RAG route.
extension _RagRouteNavigation on _RagRoot {
  bool _routeIsLive(_RagRoute route) =>
      !_disposed &&
      route.token == _routeToken &&
      identical(_currentRoute, route);

  void _closeCurrentRoute() {
    final _RagRoute? route = _currentRoute;
    if (route != null) _closeRoute(route);
  }

  void _closeRoute(_RagRoute route) {
    if (!identical(_currentRoute, route)) return;
    _routeToken++; // Invalidate any in-flight citation attempt.
    _currentRoute = null;
    final MaterialPageRoute<void> page = route.pageRoute;
    if (page.isActive) {
      route.navigator.removeRoute(page);
    }
  }
}

/// Validates and commits one citation open.
///
/// The actor, session, service, displayed result, and source are captured
/// before the first await and rechecked after every await. Navigation happens
/// only after a bounded fresh sync, a bounded local reload, and exactly one
/// `validateSource`; nothing here reads or writes the repository itself.
extension _RagSourceNavigation on _RagRoot {
  Future<bool> _openSource(_RagRoute route, RagSource source) async {
    if (!_routeIsLive(route)) return false;
    final RagAppService service = route.service;
    final RagResult? displayed = service.state.result;
    if (displayed == null || !displayed.isAnswered) return false;
    if (!_isDisplayedSource(displayed, source)) return false;

    final _RagSourceAttempt attempt = _RagSourceAttempt(
      route: route,
      source: source,
      displayed: displayed,
      deadline: DateTime.now().add(const Duration(seconds: 26)),
    );
    if (!_attemptLive(attempt)) return false;
    try {
      final AccountSyncRuntime? runtime = _host._accountSyncRuntime();
      if (runtime == null) return false;
      await attempt.guard(runtime.syncNow(route.actorId));
      if (!_attemptLive(attempt)) return false;

      final NotesWorkspacePageState? notesPage =
          _host._notesPageKey.currentState;
      if (notesPage == null) return false;
      await attempt.guard(notesPage.reload());
      if (!_attemptLive(attempt)) return false;

      final NoteDto note = await attempt.guard(service.validateSource(source));
      if (!_attemptLive(attempt)) return false;
      if (!_eligibleSourceNote(route, source, note)) return false;
      if (!source.matchesContent(note.content)) return false;

      final TextSelection selection = TextSelection(
        baseOffset: source.startOffset,
        extentOffset: source.endOffset,
      );
      // Synchronous commit: reveal the target destination, then open/highlight.
      _host._workspaceShellKey.currentState?.showDestination(
        WorkspaceDestination.notes,
      );
      final NotesWorkspacePageState? page = _host._notesPageKey.currentState;
      if (page == null) return false;
      final bool opened = page.openSource(note, selection);
      if (!opened) return false;
      _closeRoute(route);
      return true;
    } on RagFailure {
      attempt.expired = true;
      return false;
    } on Object {
      attempt.expired = true;
      return false;
    }
  }

  bool _isDisplayedSource(RagResult displayed, RagSource source) {
    for (final RagSource candidate in displayed.sources) {
      if (candidate == source) return true;
    }
    return false;
  }

  bool _attemptLive(_RagSourceAttempt attempt) {
    if (_disposed || attempt.expired || !attempt.hasBudget) return false;
    if (!_routeIsLive(attempt.route)) return false;
    if (!attempt.route.service.state.active) return false;
    if (!identical(attempt.route.service.state.result, attempt.displayed)) {
      return false;
    }
    if (_host._currentUserSession.userId != attempt.route.actorId) return false;
    if (_host._currentUserSession.sessionGeneration !=
        attempt.route.sessionGeneration) {
      return false;
    }
    final NotesWorkspacePageState? notesPage =
        _host._notesPageKey.currentState;
    if (notesPage != null && notesPage.hasUnsavedChanges) return false;
    return true;
  }

  bool _eligibleSourceNote(_RagRoute route, RagSource source, NoteDto note) {
    final String? actor = _host._currentUserSession.userId;
    if (actor == null || actor != route.actorId) return false;
    if (note.ownerId != actor) return false;
    if (note.id != source.noteId) return false;
    if (note.isProtected || !note.contentAvailable) return false;
    if (note.share != null) return false;
    if (note.contentRevision != source.revision) return false;
    if (note.contentRevision < 1) return false;
    if (note.content.length < source.endOffset) return false;
    return true;
  }
}

/// One open RAG route, with the bindings an in-flight citation must match.
final class _RagRoute {
  _RagRoute({
    required this.token,
    required this.actorId,
    required this.sessionGeneration,
    required this.service,
    required this.navigator,
    required this.pageRoute,
  });

  final int token;
  final String actorId;
  final int sessionGeneration;
  final RagAppService service;
  final NavigatorState navigator;
  final MaterialPageRoute<void> pageRoute;
}

/// One citation open with a single local 26-second navigation deadline.
///
/// The deadline bounds every awaited step (fresh sync, local reload, validate);
/// a timeout marks the attempt expired so a late completion can never commit.
final class _RagSourceAttempt {
  _RagSourceAttempt({
    required this.route,
    required this.source,
    required this.displayed,
    required this.deadline,
  });

  final _RagRoute route;
  final RagSource source;
  final RagResult displayed;
  final DateTime deadline;

  /// Set once a step timed out or was refused; an expired attempt never commits.
  bool expired = false;

  bool get hasBudget => DateTime.now().isBefore(deadline);

  /// Awaits [future] within the remaining navigation budget.
  Future<T> guard<T>(Future<T> future) {
    final Duration remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      expired = true;
      return Future<T>.error(TimeoutException('rag-navigation'));
    }
    return future.timeout(
      remaining,
      onTimeout: () {
        expired = true;
        throw TimeoutException('rag-navigation');
      },
    );
  }
}
