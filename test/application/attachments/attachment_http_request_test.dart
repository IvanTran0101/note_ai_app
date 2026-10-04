import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_http_request.dart';

final class WaitingClient extends http.BaseClient {
  final started = Completer<void>();
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request, isA<http.AbortableRequest>());
    if (!started.isCompleted) started.complete();
    await (request as http.AbortableRequest).abortTrigger;
    aborted = true;
    throw http.RequestAbortedException(request.url);
  }
}

Future<int> read(
  WaitingClient client, {
  Future<void>? cancel,
  Duration timeout = const Duration(seconds: 2),
  void Function()? guard,
}) => attachmentHttpRequest(
  client: client,
  method: 'GET',
  uri: Uri.parse('https://api.example.test/file'),
  requireAccess: guard ?? () {},
  configure: (_) {},
  consume: (_) async => throw StateError('Should abort before response'),
  timeout: timeout,
  cancel: cancel,
);

void main() {
  test('explicit cancellation aborts pending actual request', () async {
    final client = WaitingClient(), cancel = Completer<void>();
    final result = read(client, cancel: cancel.future);
    final assertion = expectLater(result, throwsStateError);
    await client.started.future;
    cancel.complete();
    await assertion;
    expect(client.aborted, true);
  });
  test('timeout aborts pending actual request', () async {
    final client = WaitingClient();
    await expectLater(
      read(client, timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.aborted, true);
  });
  test('access loss aborts while response headers are pending', () async {
    final client = WaitingClient();
    var allowed = true;
    final assertion = expectLater(
      read(
        client,
        guard: () {
          if (!allowed) throw StateError('locked');
        },
      ),
      throwsStateError,
    );
    await client.started.future;
    allowed = false;
    await assertion;
    expect(client.aborted, true);
  });
  test(
    'returned buffer is erased if authority changes after consumption',
    () async {
      var allowed = true;
      final bytes = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        attachmentHttpRequest<Uint8List>(
          client: MockClient((_) async => http.Response('', 200)),
          method: 'GET',
          uri: Uri.parse('https://api.example.test/file'),
          requireAccess: () {
            if (!allowed) throw StateError('locked');
          },
          configure: (_) {},
          consume: (_) async {
            allowed = false;
            return bytes;
          },
          discard: (b) => b.fillRange(0, b.length, 0),
        ),
        throwsStateError,
      );
      expect(bytes, [0, 0, 0]);
    },
  );
}
