import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../application/sync/revision_source.dart';
import 'appsync_revision_codec.dart';
import 'realtime_socket.dart';

typedef RealtimeTokenProvider = Future<String?> Function({
  required bool forceRefresh,
});

enum _Phase { disconnected, acknowledging, subscribing, active }

/// AppSync Events protocol only. Never writes content, grants or cursor state.
final class AppSyncRevisionSource implements IRevisionSource {
  AppSyncRevisionSource({
    required this.httpEndpoint,
    required this.socketEndpoint,
    required this.actorId,
    required this.tokenProvider,
    RealtimeSocketFactory? socketFactory,
    DateTime Function()? clock,
    double Function()? jitter,
    this.retryBase = const Duration(seconds: 1),
    this.handshakeTimeout = const Duration(seconds: 15),
  }) : _socketFactory = socketFactory ?? ChannelRealtimeSocket.new,
       _clock = clock ?? DateTime.now,
       _jitter = jitter ?? Random().nextDouble {
    if (httpEndpoint.scheme != 'https' ||
        httpEndpoint.path != '/event' ||
        socketEndpoint.scheme != 'wss' ||
        socketEndpoint.path != '/event/realtime' ||
        httpEndpoint.userInfo.isNotEmpty ||
        socketEndpoint.userInfo.isNotEmpty ||
        httpEndpoint.hasQuery ||
        socketEndpoint.hasQuery ||
        !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?$')
            .hasMatch(actorId)) {
      throw ArgumentError('Invalid realtime configuration');
    }
  }
  final Uri httpEndpoint;
  final Uri socketEndpoint;
  final String actorId;
  final RealtimeTokenProvider tokenProvider;
  final RealtimeSocketFactory _socketFactory;
  final DateTime Function() _clock;
  final double Function() _jitter;
  final Duration retryBase;
  final Duration handshakeTimeout;
  final StreamController<RevisionNotice> _notices =
      StreamController.broadcast();
  RealtimeSocket? _socket;
  StreamSubscription<Object?>? _messages;
  Timer? _retry;
  Timer? _watchdog;
  Timer? _refresh;
  _Phase _phase = _Phase.disconnected;
  bool _disposed = false;
  bool _started = false;
  int _generation = 0;
  int _attempts = 0;
  String? _subscriptionId;
  Map<String, String>? _authorization;
  Duration _keepalive = const Duration(minutes: 5);

  @override
  Stream<RevisionNotice> get notices => _notices.stream;
  @override
  void start() {
    if (_disposed || _started) return;
    _started = true;
    unawaited(_connect(false));
  }

  @override
  void reconnect() {
    if (!_disposed && _started) _retryConnection(immediate: true);
  }

  bool _live(int generation) => !_disposed && generation == _generation;

  Future<void> _connect(bool refresh) async {
    final generation = ++_generation;
    _arm(handshakeTimeout, generation);
    try {
      final token = await tokenProvider(forceRefresh: refresh);
      if (!_live(generation)) return;
      final expires = token == null ? null : tokenExpiry(token, actorId);
      if (expires == null ||
          expires.difference(_clock()) <= const Duration(seconds: 45)) {
        _retryConnection();
        return;
      }
      _authorization = {'host': httpEndpoint.host, 'Authorization': token!};
      final header = base64Url
          .encode(utf8.encode(jsonEncode(_authorization)))
          .replaceAll('=', '');
      final socket = _socketFactory(socketEndpoint, [
        'aws-appsync-event-ws',
        'header-$header',
      ]);
      _socket = socket;
      _messages = socket.messages.listen(
        (frame) => _frame(frame, generation),
        onDone: () {
          if (_live(generation)) _retryConnection();
        },
        onError: (Object _) {
          if (_live(generation)) _retryConnection();
        },
      );
      await socket.ready;
      if (!_live(generation)) {
        unawaited(_closeSocket(socket));
        return;
      }
      _phase = _Phase.acknowledging;
      _send({'type': 'connection_init'});
      _refresh = Timer(
        expires.difference(_clock()) - const Duration(seconds: 60),
        () {
          if (_live(generation)) _retryConnection(immediate: true);
        },
      );
    } on Object {
      if (_live(generation)) _retryConnection();
    }
  }

  void _frame(Object? frame, int generation) {
    if (!_live(generation)) return;
    final row = decodeEventFrame(frame);
    if (row == null) return;
    switch (row['type']) {
      case 'connection_ack':
        if (_phase != _Phase.acknowledging) return;
        final timeout = row['connectionTimeoutMs'];
        if (timeout is! int || timeout < 1000 || timeout > 300000) {
          _retryConnection();
          return;
        }
        _keepalive = Duration(milliseconds: timeout);
        _subscriptionId = 'session-$generation';
        _phase = _Phase.subscribing;
        _send({
          'type': 'subscribe',
          'id': _subscriptionId,
          'channel': '/notes/$actorId',
          'authorization': _authorization,
        });
        _arm(handshakeTimeout, generation);
      case 'subscribe_success':
        if (row['id'] != _subscriptionId || _phase != _Phase.subscribing) {
          return;
        }
        _phase = _Phase.active;
        _attempts = 0;
        _arm(_keepalive, generation);
        _notices.add(const RevisionNotice.connected());
      case 'ka':
        if (_phase == _Phase.active) _arm(_keepalive, generation);
      case 'data':
        if (_phase != _Phase.active || row['id'] != _subscriptionId) return;
        final events = row['event'];
        if (events is! List || events.length > 5) return;
        for (final event in events) {
          final signal = decodeRevisionSignal(event);
          if (signal != null) _notices.add(RevisionNotice.changed(signal));
        }
      case 'connection_error':
      case 'subscribe_error':
      case 'broadcast_error':
        _retryConnection();
    }
  }

  void _send(Map<String, Object?> message) {
    try {
      _socket?.send(jsonEncode(message));
    } on Object {
      _retryConnection();
    }
  }

  void _arm(Duration timeout, int generation) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, () {
      if (_live(generation)) _retryConnection();
    });
  }

  void _retryConnection({bool immediate = false}) {
    if (_disposed) return;
    ++_generation; // Invalidates token/ready/message callbacks before closing.
    _phase = _Phase.disconnected;
    _authorization = null;
    _subscriptionId = null;
    _watchdog?.cancel();
    _refresh?.cancel();
    _retry?.cancel();
    unawaited(_messages?.cancel());
    _messages = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(_closeSocket(socket));
    final millis = min(
      60000,
      retryBase.inMilliseconds * pow(2, min(_attempts++, 6)),
    );
    _retry = Timer(
      immediate
          ? Duration.zero
          : Duration(milliseconds: (millis * (0.75 + _jitter() * 0.5)).round()),
      () {
        if (!_disposed) unawaited(_connect(true));
      },
    );
  }

  Future<void> _closeSocket(RealtimeSocket socket) async {
    try {
      await socket.close();
    } on Object {
      /* Raw provider data stays here. */
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _watchdog?.cancel();
    _refresh?.cancel();
    _retry?.cancel();
    if (_phase == _Phase.active && _subscriptionId != null) {
      try {
        _socket?.send(
          jsonEncode({'type': 'unsubscribe', 'id': _subscriptionId}),
        );
      } on Object {
        /* Socket may already be closed. */
      }
    }
    await _messages?.cancel();
    final socket = _socket;
    _socket = null;
    _authorization = null;
    if (socket != null) await _closeSocket(socket);
    await _notices.close();
  }
}
