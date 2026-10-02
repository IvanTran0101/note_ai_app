import 'dart:async';
import 'dart:collection';

import 'revision_source.dart';

/// Session lifetime and serialized catch-up orchestration live in Application.
final class AccountRealtimeService {
  AccountRealtimeService({
    required this.source,
    required this.isCurrentSession,
    required this.synchronize,
    this.retryDelay = const Duration(seconds: 5),
  });
  final IRevisionSource source;
  final bool Function() isCurrentSession;
  final Future<void> Function() synchronize;
  final Duration retryDelay;
  Timer? _retry;
  int _failures = 0;
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  StreamSubscription<RevisionNotice>? _subscription;
  bool _disposed = false;
  bool _running = false;
  bool _pending = false;

  void start() {
    if (_disposed || _subscription != null || !isCurrentSession()) return;
    _subscription = source.notices.listen(_notice, onError: (Object _) {});
    source.start();
  }

  void _notice(RevisionNotice notice) {
    if (_disposed || !isCurrentSession()) return;
    final signal = notice.signal;
    if (signal != null) {
      if (!_seen.add(signal.eventId)) return;
      if (_seen.length > 512) _seen.remove(_seen.first);
    }
    _pending = true;
    _retry?.cancel();
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending && !_disposed && isCurrentSession()) {
        _pending = false;
        try {
          await synchronize();
          _failures = 0;
        } on Object {
          // Retry the existing coordinator when HTTP is down but WS stays alive.
          // Metadata IDs remain deduped; reconnect still performs full catch-up.
          final scale = 1 << (_failures++).clamp(0, 4);
          _retry = Timer(retryDelay * scale, () {
            if (_disposed || !isCurrentSession()) return;
            _pending = true;
            if (!_running) unawaited(_drain());
          });
          break;
        }
      }
    } finally {
      _running = false;
    }
  }

  void reconnect() {
    if (!_disposed && isCurrentSession()) source.reconnect();
  }

  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    _pending = false;
    _seen.clear();
    await _subscription?.cancel();
    await source.dispose();
  }
}
