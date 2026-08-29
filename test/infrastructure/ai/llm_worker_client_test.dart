// Worker protocol / lifecycle tests for LocalLlmWorkerClientImpl.
//
// A fake isolate entry speaks the same serializable map protocol as the real
// worker (`_llmWorkerIsolateEntry`) without touching local_llm_bridge, so no
// GGUF model is needed. `dart:io` sleep mimics the real worker's synchronous
// native generation: it blocks the isolate event loop, so a `chat` followed
// by `shutdown` is handled in order exactly like a native generate call.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/infrastructure/ai/llm_worker_client_io.dart';
import 'package:note_ai_app/infrastructure/ai/llm_worker_contract.dart';

void _fakeWorkerEntry(Map<String, Object?> args) {
  final SendPort mainPort = args['mainPort']! as SendPort;
  final ReceivePort receivePort = ReceivePort();
  mainPort.send(<String, Object?>{
    'type': 'workerReady',
    'port': receivePort.sendPort,
  });

  if (args['failStartup'] == true) {
    mainPort.send(<String, Object?>{
      'type': 'startupError',
      'message': args['startupMessage'] ?? 'fake startup failure',
    });
    return;
  }
  if (args['exitDuringStartup'] == true) {
    // Closing the only ReceivePort terminates the isolate, so the client's
    // onExit notification fires before 'started' is sent.
    receivePort.close();
    return;
  }
  mainPort.send(<String, Object?>{'type': 'started'});

  receivePort.listen((Object? message) {
    final Map<String, Object?> request = message! as Map<String, Object?>;
    switch (request['type']) {
      case 'chat':
        final int requestId = request['requestId']! as int;
        final String userPrompt = request['userPrompt']! as String;
        if (userPrompt == 'die') {
          Isolate.exit(); // Simulate unexpected worker death mid-request.
        }
        if (userPrompt == 'slow') {
          sleep(const Duration(milliseconds: 150));
        }
        if (userPrompt == 'error') {
          mainPort.send(<String, Object?>{
            'type': 'error',
            'requestId': requestId,
            'message': 'native boom',
          });
          return;
        }
        mainPort.send(<String, Object?>{
          'type': 'result',
          'requestId': requestId,
          'text': 'fake summary of $userPrompt',
        });
      case 'shutdown':
        mainPort.send(<String, Object?>{'type': 'stopped'});
        Isolate.exit();
      default:
        break;
    }
  });
}

Future<LocalLlmWorkerClientImpl> _startClient([
  Map<String, Object?> args = const <String, Object?>{},
]) {
  return LocalLlmWorkerClientImpl.startWithEntry(_fakeWorkerEntry, args);
}

void main() {
  group('LocalLlmWorkerClientImpl protocol', () {
    test('round-trips a chat request and response', () async {
      final LocalLlmWorkerClientImpl client = await _startClient();
      addTearDown(client.dispose);

      final String text = await client.generateChat(
        systemPrompt: 'sys',
        userPrompt: 'hello',
      );

      expect(text, 'fake summary of hello');
    });

    test('routes concurrent requests by request ID', () async {
      final LocalLlmWorkerClientImpl client = await _startClient();
      addTearDown(client.dispose);

      final Future<String> a = client.generateChat(
        systemPrompt: 's',
        userPrompt: 'A',
      );
      final Future<String> b = client.generateChat(
        systemPrompt: 's',
        userPrompt: 'B',
      );

      expect(await a, 'fake summary of A');
      expect(await b, 'fake summary of B');
    });

    test('surfaces native errors as LlmWorkerException', () async {
      final LocalLlmWorkerClientImpl client = await _startClient();
      addTearDown(client.dispose);

      await expectLater(
        client.generateChat(systemPrompt: 's', userPrompt: 'error'),
        throwsA(
          isA<LlmWorkerException>().having(
            (LlmWorkerException error) => error.message,
            'message',
            contains('native boom'),
          ),
        ),
      );
    });
  });

  group('LocalLlmWorkerClientImpl lifecycle', () {
    test('startup failure surfaces from start', () async {
      await expectLater(
        _startClient(<String, Object?>{
          'failStartup': true,
          'startupMessage': 'boom',
        }),
        throwsA(
          isA<LlmWorkerException>().having(
            (LlmWorkerException error) => error.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    test('worker exiting during startup fails start', () async {
      await expectLater(
        _startClient(<String, Object?>{'exitDuringStartup': true}),
        throwsA(
          isA<LlmWorkerException>().having(
            (LlmWorkerException error) => error.message,
            'message',
            contains('startup'),
          ),
        ),
      );
    });

    test('worker death fails every pending future', () async {
      final LocalLlmWorkerClientImpl client = await _startClient();
      addTearDown(client.dispose);

      final Future<String> first = client.generateChat(
        systemPrompt: 's',
        userPrompt: 'die',
      );
      final Future<String> second = client.generateChat(
        systemPrompt: 's',
        userPrompt: 'die',
      );

      await expectLater(
        first,
        throwsA(
          isA<LlmWorkerException>().having(
            (LlmWorkerException error) => error.message,
            'message',
            contains('exited'),
          ),
        ),
      );
      await expectLater(second, throwsA(isA<LlmWorkerException>()));
    });

    test('ordered shutdown waits for the in-flight request', () async {
      final LocalLlmWorkerClientImpl client = await _startClient();
      final List<String> events = <String>[];

      final Future<void> chatDone = client
          .generateChat(systemPrompt: 's', userPrompt: 'slow')
          .then((String text) {
            events.add('chat:$text');
          });
      final Future<void> disposeDone = client.dispose().then((_) {
        events.add('disposed');
      });

      await Future.wait<void>(<Future<void>>[chatDone, disposeDone]);

      expect(events, <String>['chat:fake summary of slow', 'disposed']);
    });

    test('fails fast after disposal', () async {
      final LocalLlmWorkerClientImpl client = await _startClient();
      await client.dispose();

      expect(
        () => client.generateChat(systemPrompt: 's', userPrompt: 'x'),
        throwsStateError,
      );
      // dispose is idempotent.
      await client.dispose();
    });

    test(
      'concurrent disposal shares shutdown and rejects new requests',
      () async {
        final LocalLlmWorkerClientImpl client = await _startClient();

        final Future<void> first = client.dispose();
        final Future<void> second = client.dispose();

        expect(identical(first, second), isTrue);
        expect(
          () => client.generateChat(systemPrompt: 's', userPrompt: 'x'),
          throwsStateError,
        );
        await first;
      },
    );
  });
}
