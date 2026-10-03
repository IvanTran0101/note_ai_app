part of 'main.dart';

/// Root wiring only. Application owns lifetime; adapter owns provider protocol.
extension _RealtimeComposition on _NoteFlowAppState {
  void _stopRealtime() {
    final service = _realtimeService;
    _realtimeService = null;
    if (service != null) unawaited(service.dispose());
  }

  String _eventEndpoint(String name, String configured) {
    if (configured.trim().isNotEmpty) return configured.trim();
    try {
      final decoded = jsonDecode(amplifyConfig);
      final custom = decoded is Map ? decoded['custom'] : null;
      final value = custom is Map ? custom[name] : null;
      return value is String ? value : '';
    } on Object {
      return '';
    }
  }

  void _startRealtime(String actor) {
    if (_disposed || _realtimeService != null) return;
    final runtime = _accountSyncRuntime();
    if (runtime == null) return;
    final generation = _currentUserSession.sessionGeneration;
    bool live() =>
        !_disposed &&
        _currentUserSession.userId == actor &&
        _currentUserSession.sessionGeneration == generation;
    final connection = widget.connection;
    if (connection != null) {
      _realtimeService = AccountRealtimeService(
        source: connection.revisionSourceFor(actor),
        isCurrentSession: live,
        synchronize: () async {
          if (live()) await runtime.syncNow(actor);
        },
      )..start();
      return;
    }
    final http = Uri.tryParse(
      _eventEndpoint(
        'eventHttpEndpoint',
        const String.fromEnvironment('NOTEFLOW_EVENT_HTTP'),
      ),
    );
    final socket = Uri.tryParse(
      _eventEndpoint(
        'eventSocketEndpoint',
        const String.fromEnvironment('NOTEFLOW_EVENT_SOCKET'),
      ),
    );
    if (http == null ||
        socket == null ||
        http.host.isEmpty ||
        socket.host.isEmpty) {
      return;
    }
    try {
      _realtimeService = AccountRealtimeService(
        source: AppSyncRevisionSource(
          httpEndpoint: http,
          socketEndpoint: socket,
          actorId: actor,
          tokenProvider: const CognitoIdTokenProvider().call,
        ),
        isCurrentSession: live,
        synchronize: () async {
          if (live()) await runtime.syncNow(actor);
        },
      )..start();
    } on ArgumentError {
      // Missing/invalid deployment configuration leaves durable HTTP sync active.
    }
  }
}
