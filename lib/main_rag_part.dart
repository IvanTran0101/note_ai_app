// Root composition and source navigation for the Phase 5 ask-my-notes slice.
//
// This part owns the shared RAG gateway/service lifetime, the account/session
// lifecycle bindings, the single RAG route, and the raw-source callback. It is
// additive to the existing composition root: it never reads storage directly
// (only the existing account store through the service), never performs a
// network call of its own, and never fabricates authority the application
// service did not return.
part of 'main.dart';

/// Root owner of the shared RAG (ask-my-notes) gateway/service and the
/// raw-source navigation contract.
///
/// Feature availability is honest: the ask-notes surfaces exist only when a
/// gateway is injected or a validated HTTPS `custom.ragApiEndpoint` is present
/// in the generated Amplify outputs. An absent endpoint hides the feature
/// instead of pretending a live one.
final class _RagRoot {
  _RagRoot(this._host) {
    _securitySubscription = _host._noteSecurityRuntime.changes.listen(
      (_) => onLocalStateChanged(),
    );
  }

  final _NoteFlowAppState _host;

  IRagGateway? _gateway;
  RagAppService? _service;
  StreamSubscription<void>? _securitySubscription;
  ChangeNotifier? _syncController;
  bool _disposed = false;

  _RagRoute? _currentRoute;
  int _routeToken = 0;
  String? _consentActor;
  int? _consentGeneration;

  /// Whether an ask-notes surface can be offered at all.
  bool get available =>
      _host.widget.ragGateway != null || _ragBaseUri() != null;

  /// The lazy shared service, or null when the feature is unavailable.
  RagAppService? ensureService() {
    if (_disposed) return null;
    if (!available) return null;
    try {
      return _service ??= _createService();
    } on Object {
      return null;
    }
  }

  /// The shared service for Settings, when one exists or can be created.
  RagAppService? get settingsService => ensureService();

  Uri? _ragBaseUri() {
    final Uri? explicit = _host.widget.ragApiBaseUri;
    if (explicit != null) return _validHttps(explicit);
    // The legacy Sync connection is never an endpoint for ask-notes: only an
    // explicit RAG URI or the generated `custom.ragApiEndpoint` may enable the
    // feature. Inferring the RAG base from the Sync base would silently offer
    // RAG when none is configured and contradict honest availability.
    try {
      final Object? decoded = jsonDecode(amplifyConfig);
      if (decoded is Map) {
        final Object? custom = decoded['custom'];
        if (custom is Map) {
          final Object? endpoint = custom['ragApiEndpoint'];
          if (endpoint is String) return _validHttps(Uri.tryParse(endpoint));
        }
      }
    } on Object {
      // An unreadable generated config means the feature stays hidden.
    }
    return null;
  }

  Uri? _validHttps(Uri? uri) =>
      uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? uri : null;

  RagAppService _createService() {
    return RagAppService(
      gateway: _ensureGateway(),
      currentUser: _host._currentUserSession,
      session: _host._currentUserSession,
      readLocalState: (String actorId) =>
          _host._localSyncStoreForAccount(accountUserId: actorId).read(),
    );
  }

  IRagGateway _ensureGateway() {
    final IRagGateway? existing = _gateway;
    if (existing != null) return existing;
    final IRagGateway? injected = _host.widget.ragGateway;
    if (injected != null) return _gateway = injected;
    final Uri? baseUri = _ragBaseUri();
    if (baseUri == null) {
      throw StateError('The RAG endpoint is not configured.');
    }
    final NoteConnection? connection = _host.widget.connection;
    // A borrowed HTTP client and token provider stay owned by the composition
    // root; the gateway only closes a client it created itself.
    return _gateway = RagHttpGateway(
      baseUri: baseUri,
      tokenProvider: connection?.tokenProvider ?? _profileAccessToken,
      client: connection?.client,
    );
  }

  /// Handles a session/login/logout transition for the shared service.
  void onAuthenticationChanged({required bool sessionChanged}) {
    if (_disposed) return;
    if (sessionChanged) {
      // Logout and account switch clear the local run/answer; nothing is
      // revoked on the server (only an explicit user revoke writes).
      _service?.invalidateSession();
      _closeCurrentRoute();
      attachSyncController(null);
    }
    final String? actor = _host._currentUserSession.userId;
    if (actor == null) {
      _consentActor = null;
      _consentGeneration = null;
      return;
    }
    // Login/resume re-reads the canonical grant; an absent or unknown grant
    // never authorizes a question. Exactly one read per (account, generation).
    final RagAppService? service = ensureService();
    if (service == null) return;
    final int generation = _host._currentUserSession.sessionGeneration;
    if (_consentActor == actor && _consentGeneration == generation) return;
    _consentActor = actor;
    _consentGeneration = generation;
    unawaited(service.refreshConsent());
  }

  /// Mirrors app lifecycle changes onto the service.
  void onLifecycle(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Any background/inactive moment invalidates the local consent view and
        // cancels the run, without writing a revoke.
        _service?.onInactive();
      case AppLifecycleState.resumed:
        final RagAppService? service = _service;
        if (service != null) unawaited(service.onResume());
    }
  }

  /// Revalidates the displayed answer after local sync/security changes.
  void onLocalStateChanged() {
    if (_disposed) return;
    final RagAppService? service = _service;
    if (service == null) return;
    unawaited(service.onLocalStateChanged());
  }

  /// Binds (or unbinds) the sync presentation controller's notifications.
  void attachSyncController(ChangeNotifier? next) {
    if (identical(_syncController, next)) return;
    _syncController?.removeListener(onLocalStateChanged);
    _syncController = next;
    next?.addListener(onLocalStateChanged);
  }

  /// Reports one real edit of a saved note before its autosave runs.
  ///
  /// Only an owned, synced, unprotected, unshared note can affect account
  /// evidence. A new draft, a local-only note, an incoming share, or a
  /// protected note never blanket-denies an account question.
  void onNoteEdited(NoteDto note) {
    if (_disposed) return;
    final RagAppService? service = _service;
    if (service == null) return;
    final String? actor = _host._currentUserSession.userId;
    if (actor == null || note.ownerId != actor) return;
    if (note.share != null || note.isProtected || !note.contentAvailable) return;
    if (note.contentRevision < 1) return;
    // Clears a displayed pair that cites this note, synchronously. An active
    // account query is cancelled conservatively: its evidence changed and its
    // future authorization is unknown.
    service.invalidateNote(note.id);
    final RagState state = service.state;
    if (state.queryRunning && (state.scope?.isAccount ?? false)) {
      service.cancel();
    }
  }

  /// Opens the account-scope ask-notes screen for the current account.
  void openAccountScope(BuildContext context) {
    if (_disposed || !available) return;
    final RagAppService? service = ensureService();
    if (service == null) return;
    final String? actor = _host._currentUserSession.userId;
    if (actor == null) return;
    _pushRagRoute(
      context: context,
      service: service,
      initialScope: const RagScope.account(),
      actorId: actor,
    );
  }

  /// Opens the current note's ask-notes screen when the note is eligible.
  void openNoteScope(BuildContext context, NoteDto note) {
    if (_disposed || !available) return;
    final RagAppService? service = ensureService();
    if (service == null) return;
    final String? actor = _host._currentUserSession.userId;
    if (actor == null || note.ownerId != actor) return;
    if (note.share != null ||
        note.isProtected ||
        !note.contentAvailable ||
        note.contentRevision < 1) {
      return;
    }
    _pushRagRoute(
      context: context,
      service: service,
      initialScope: RagScope.note(note.id),
      actorId: actor,
    );
  }

  void _pushRagRoute({
    required BuildContext context,
    required RagAppService service,
    required RagScope initialScope,
    required String actorId,
  }) {
    if (_currentRoute != null) return; // One RAG route at a time.
    final NavigatorState navigator = Navigator.of(context);
    late final _RagRoute route;
    final MaterialPageRoute<void> pageRoute = MaterialPageRoute<void>(
      builder: (_) => RagPage(
        service: service,
        initialScope: initialScope,
        onOpenSource: (RagSource source) => _openSource(route, source),
      ),
    );
    route = _RagRoute(
      token: ++_routeToken,
      actorId: actorId,
      sessionGeneration: _host._currentUserSession.sessionGeneration,
      service: service,
      navigator: navigator,
      pageRoute: pageRoute,
    );
    _currentRoute = route;
    unawaited(
      navigator.push<void>(pageRoute).whenComplete(() {
        if (identical(_currentRoute, route)) _currentRoute = null;
      }),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_securitySubscription?.cancel());
    _securitySubscription = null;
    _syncController?.removeListener(onLocalStateChanged);
    _syncController = null;
    _currentRoute = null;
    final RagAppService? service = _service;
    _service = null;
    service?.dispose();
    final IRagGateway? gateway = _gateway;
    _gateway = null;
    if (gateway != null) unawaited(gateway.close());
  }
}
