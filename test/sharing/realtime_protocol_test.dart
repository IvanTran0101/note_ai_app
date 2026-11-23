import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/account_realtime_service.dart';
import 'package:note_ai_app/application/sync/revision_source.dart';
import 'package:note_ai_app/infrastructure/sync/appsync_revision_codec.dart';
import 'package:note_ai_app/infrastructure/sync/appsync_revision_source.dart';
import 'package:note_ai_app/infrastructure/sync/realtime_socket.dart';

final _now = DateTime.utc(2030);
String token({String actor = 'actor', int seconds = 3600, String use = 'id'}) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'token_use': use, 'exp': _now.add(Duration(seconds: seconds)).millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.signature';
Future<void> tick([int milliseconds = 20]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));
Map<String, Object?> signal([String id = 'event']) => {
  'version': 1,
  'eventId': id,
  'ownerId': 'owner',
  'noteId': 'same',
  'invalidate': true,
  'revision': 4,
};

final class SocketFixture implements RealtimeSocket {
  final input = StreamController<Object?>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  bool closed = false;
  Completer<void>? pendingReady;
  @override
  Future<void> get ready => pendingReady?.future ?? Future.value();
  @override
  Stream<Object?> get messages => input.stream;
  @override
  void send(String frame) =>
      sent.add(jsonDecode(frame) as Map<String, dynamic>);
  void receive(Map<String, Object?> frame) => input.add(jsonEncode(frame));
  void acknowledge({int timeout = 300000}) {
    receive({'type': 'connection_ack', 'connectionTimeoutMs': timeout});
    receive({'type': 'subscribe_success', 'id': sent.last['id']});
  }

  void event(Object value, {String? id}) => receive({
    'type': 'data',
    'id': id ?? sent.last['id'],
    'event': [jsonEncode(value)],
  });
  @override
  Future<void> close() async {
    closed = true;
  }
}

final class ProtocolFixture {
  ProtocolFixture({
    RealtimeTokenProvider? provider,
    Duration? timeout,
    SocketFixture Function()? make,
  }) {
    source = AppSyncRevisionSource(
      httpEndpoint: Uri.parse('https://events.test/event'),
      socketEndpoint: Uri.parse('wss://events.test/event/realtime'),
      actorId: 'actor',
      tokenProvider:
          provider ??
          ({required forceRefresh}) async {
            refreshes.add(forceRefresh);
            return token();
          },
      clock: () => _now,
      retryBase: const Duration(milliseconds: 20),
      handshakeTimeout: timeout ?? const Duration(seconds: 10),
      jitter: () => 0.5,
      socketFactory: (uri, protocols) {
        connections.add(protocols);
        final socket = make?.call() ?? SocketFixture();
        sockets.add(socket);
        return socket;
      },
    );
  }
  final sockets = <SocketFixture>[];
  final connections = <List<String>>[];
  final refreshes = <bool>[];
  late final AppSyncRevisionSource source;
}

final class NoticeFixture implements IRevisionSource {
  final events = StreamController<RevisionNotice>.broadcast(sync: true);
  bool started = false;
  bool disposed = false;
  int reconnects = 0;
  @override
  Stream<RevisionNotice> get notices => events.stream;
  @override
  void start() {
    started = true;
  }

  @override
  void reconnect() {
    reconnects++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test(
    'HTTP failure retries cursor catch-up while socket stays connected',
    () async {
      final source = NoticeFixture();
      var runs = 0;
      final service = AccountRealtimeService(
        source: source,
        isCurrentSession: () => true,
        retryDelay: const Duration(milliseconds: 20),
        synchronize: () async {
          if (++runs == 1) throw StateError('network');
        },
      );
      service.start();
      addTearDown(service.dispose);
      source.events.add(const RevisionNotice.connected());
      await tick(60);
      expect(runs, 2);
      expect(source.reconnects, 0);
    },
  );
  test(
    'AppSync ID-token header and own-sub subscribe follow ack lifecycle',
    () async {
      final f = ProtocolFixture();
      final notices = <RevisionNotice>[];
      final sub = f.source.notices.listen(notices.add);
      addTearDown(() async {
        await f.source.dispose();
        await sub.cancel();
      });
      f.source.start();
      await tick();
      final protocols = f.connections.single;
      expect(protocols.first, 'aws-appsync-event-ws');
      expect(protocols.last.contains('='), false);
      final header = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(protocols.last.substring(7))),
        ),
      );
      expect(header['host'], 'events.test');
      expect(header['Authorization'], token());
      final s = f.sockets.single;
      expect(s.sent.single['type'], 'connection_init');
      expect(notices, isEmpty);
      s.acknowledge();
      await tick();
      expect(s.sent.last['channel'], '/notes/actor');
      expect(notices.length, 1);
      await f.source.dispose();
      expect(s.sent.last['type'], 'unsubscribe');
    },
  );
  test(
    'metadata decoder rejects unknown/private fields and malformed revisions',
    () {
      expect(decodeRevisionSignal(jsonEncode(signal())), isNotNull);
      for (final row in [
        {...signal(), 'content': 'PRIVATE'},
        {...signal(), 'email': 'PRIVATE'},
        {...signal(), 'grant': 'PRIVATE'},
        {...signal(), 'revision': -1},
        {...signal(), 'version': 2},
      ]) {
        expect(decodeRevisionSignal(jsonEncode(row)), isNull);
      }
      expect(decodeRevisionSignal('invalid'), isNull);
      expect(tokenExpiry(token(actor: 'foreign'), 'actor'), isNull);
      expect(tokenExpiry(token(use: 'access'), 'actor'), isNull);
    },
  );
  test(
    'data only after matching subscription, no GraphQL/content forwarding',
    () async {
      final f = ProtocolFixture();
      final notices = <RevisionNotice>[];
      f.source.notices.listen(notices.add);
      addTearDown(f.source.dispose);
      f.source.start();
      await tick();
      final s = f.sockets.single;
      s.event(signal(), id: 'wrong');
      s.acknowledge();
      await tick();
      s.event(signal(), id: 'wrong');
      s.event({...signal(), 'content': 'SECRET'});
      s.receive({'type': 'data', 'id': s.sent.last['id'], 'payload': signal()});
      s.event(signal());
      await tick();
      expect(notices.where((n) => n.signal != null).single.signal!.revision, 4);
    },
  );
  test(
    'connection error refreshes JWT and reconnect catches up without reload',
    () async {
      final f = ProtocolFixture();
      var connected = 0;
      f.source.notices.listen((n) {
        if (n.signal == null) connected++;
      });
      addTearDown(f.source.dispose);
      f.source.start();
      await tick();
      f.sockets.single.acknowledge();
      await tick();
      f.sockets.single.receive({
        'type': 'connection_error',
        'message': 'provider secret',
      });
      await tick(50);
      expect(f.sockets.first.closed, true);
      expect(f.refreshes, [false, true]);
      f.sockets.last.acknowledge();
      await tick();
      expect(connected, 2);
    },
  );
  test('keepalive timeout reconnects, fresh ka resets watchdog', () async {
    final f = ProtocolFixture();
    addTearDown(f.source.dispose);
    f.source.start();
    await tick();
    f.sockets.single.acknowledge(timeout: 1000);
    await tick(600);
    f.sockets.single.receive({'type': 'ka'});
    await tick(600);
    expect(f.sockets.length, 1);
    await tick(500);
    expect(f.sockets.length, 2);
  });
  test(
    'handshake deadline invalidates pending ready and raw socket error',
    () async {
      final pending = Completer<void>();
      final f = ProtocolFixture(
        timeout: const Duration(milliseconds: 30),
        make: () => SocketFixture()..pendingReady = pending,
      );
      addTearDown(f.source.dispose);
      f.source.start();
      await tick(80);
      expect(f.sockets.length, greaterThan(1));
      pending.complete();
      await tick();
      expect(f.sockets.first.sent, isEmpty);
      expect(f.sockets.first.closed, true);
    },
  );
  test(
    'dispose fences delayed token and same-account former-session callback',
    () async {
      final pending = Completer<String?>();
      final f = ProtocolFixture(
        provider: ({required forceRefresh}) => pending.future,
      );
      f.source.start();
      await tick();
      await f.source.dispose();
      pending.complete(token());
      await tick();
      expect(f.sockets, isEmpty);
      f.source.start();
      f.source.reconnect();
      await tick();
      expect(f.sockets, isEmpty);
    },
  );
  test('token expiry refresh precedes ID-token expiration', () async {
    var count = 0;
    final f = ProtocolFixture(
      provider: ({required forceRefresh}) async {
        count++;
        return token(seconds: count == 1 ? 61 : 3600);
      },
    );
    addTearDown(f.source.dispose);
    f.source.start();
    await tick();
    f.sockets.first.acknowledge();
    await tick(1100);
    expect(f.sockets.length, 2);
    expect(count, 2);
  });
  test(
    'foreign token never opens a socket; forced refresh can recover',
    () async {
      var calls = 0;
      final f = ProtocolFixture(
        provider: ({required forceRefresh}) async {
          calls++;
          return token(actor: calls == 1 ? 'foreign' : 'actor');
        },
      );
      addTearDown(f.source.dispose);
      f.source.start();
      await tick(50);
      expect(calls, 2);
      expect(f.sockets.length, 1);
    },
  );
  test(
    'Application dedupes and serializes another catch-up during active sync',
    () async {
      final source = NoticeFixture();
      final pending = Completer<void>();
      var runs = 0;
      final service = AccountRealtimeService(
        source: source,
        isCurrentSession: () => true,
        synchronize: () async {
          runs++;
          if (runs == 1) await pending.future;
        },
      );
      service.start();
      addTearDown(service.dispose);
      source.events.add(const RevisionNotice.connected());
      const changed = RevisionNotice.changed(
        RevisionSignal(eventId: 'a', ownerId: 'o', noteId: 'n'),
      );
      source.events.add(changed);
      source.events.add(changed);
      expect(runs, 1);
      pending.complete();
      await tick();
      expect(runs, 2);
      source.events.add(changed);
      await tick();
      expect(runs, 2);
      source.events.add(const RevisionNotice.connected());
      await tick();
      expect(runs, 3);
    },
  );
  test(
    'Application fences account/session switch and disposes subscription',
    () async {
      final source = NoticeFixture();
      var live = true;
      var runs = 0;
      final service = AccountRealtimeService(
        source: source,
        isCurrentSession: () => live,
        synchronize: () async {
          runs++;
        },
      );
      service.start();
      source.events.add(const RevisionNotice.connected());
      await tick();
      live = false;
      source.events.add(const RevisionNotice.connected());
      service.reconnect();
      await service.dispose();
      source.events.add(const RevisionNotice.connected());
      await tick();
      expect(runs, 1);
      expect(source.reconnects, 0);
      expect(source.disposed, true);
    },
  );
}
