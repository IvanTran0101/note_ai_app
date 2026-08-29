/// Isolate-backed [LlmWorkerClient] implementation (native platforms only).
///
/// A single long-lived worker isolate owns the [LocalLlmBridgeRuntime]. The
/// native handle is created, used, and closed exclusively inside the worker;
/// it never crosses the isolate boundary. Requests and responses travel as
/// plain serializable maps (`type`, `requestId`, ...).
///
/// The client guarantees: startup failure is surfaced from
/// [startLlmWorkerClient]; every pending future fails when the worker exits
/// unexpectedly; [dispose] shuts the worker down in order (after in-flight
/// requests); and calls after [dispose] fail fast.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:local_llm_bridge/local_llm_bridge.dart';

import 'llm_worker_contract.dart';

/// Starts a long-lived worker isolate, loads [modelPath] inside it, and
/// returns a client bound to that isolate.
///
/// Throws [LlmWorkerException] when the isolate cannot be spawned or the
/// model fails to load inside the isolate (startup failure).
Future<LlmWorkerClient> startLlmWorkerClient({
  required String modelPath,
  int contextSize = 2048,
  int threads = 0,
}) async {
  return LocalLlmWorkerClientImpl._start(
    _llmWorkerIsolateEntry,
    <String, Object?>{
      'modelPath': modelPath,
      'contextSize': contextSize,
      'threads': threads,
    },
  );
}

/// Worker-isolate entry point (top-level so [Isolate.spawn] can reference it).
///
/// Runs inside the spawned isolate: creates the worker's own [ReceivePort],
/// loads the [LocalLlmBridgeRuntime] (reporting failure via `startupError`),
/// then serves `chat`/`shutdown` messages. The runtime is owned by this
/// isolate alone.
void _llmWorkerIsolateEntry(Map<String, Object?> args) {
  final SendPort mainPort = args['mainPort']! as SendPort;
  final ReceivePort receivePort = ReceivePort();
  mainPort.send(<String, Object?>{
    'type': 'workerReady',
    'port': receivePort.sendPort,
  });

  final LocalLlmBridgeRuntime runtime;
  try {
    runtime = LocalLlmBridgeRuntime.load(
      args['modelPath']! as String,
      contextSize: (args['contextSize'] as int?) ?? 2048,
      threads: (args['threads'] as int?) ?? 0,
    );
  } on Object catch (error) {
    mainPort.send(<String, Object?>{
      'type': 'startupError',
      'message': error.toString(),
    });
    receivePort.close();
    return;
  }
  mainPort.send(<String, Object?>{'type': 'started'});

  receivePort.listen((Object? message) {
    final Map<String, Object?> request = message! as Map<String, Object?>;
    switch (request['type']) {
      case 'chat':
        final int requestId = request['requestId']! as int;
        try {
          final String text = runtime.generateChat(
            request['systemPrompt']! as String,
            request['userPrompt']! as String,
            maxTokens: (request['maxTokens'] as int?) ?? 128,
          );
          mainPort.send(<String, Object?>{
            'type': 'result',
            'requestId': requestId,
            'text': text,
          });
        } on Object catch (error) {
          mainPort.send(<String, Object?>{
            'type': 'error',
            'requestId': requestId,
            'message': error.toString(),
          });
        }
      case 'shutdown':
        runtime.close();
        mainPort.send(<String, Object?>{'type': 'stopped'});
        receivePort.close();
        Isolate.exit();
      default:
        break; // Unknown message types are ignored defensively.
    }
  });
}

/// Isolate-backed [LlmWorkerClient].
final class LocalLlmWorkerClientImpl implements LlmWorkerClient {
  LocalLlmWorkerClientImpl._({
    required this._worker,
    required this._workerPort,
    required this._mainPort,
    required this._mainSub,
    required this._exitPort,
    required this._errorPort,
    required this._exitSub,
    required this._errorSub,
  });

  /// Spawns [entry] with [args] and waits for the worker handshake.
  ///
  /// [entry] must speak the map protocol of [_llmWorkerIsolateEntry]. Tests
  /// inject a fake entry so the protocol and lifecycle can be exercised
  /// without a GGUF model.
  static Future<LocalLlmWorkerClientImpl> startWithEntry(
    void Function(Map<String, Object?>) entry,
    Map<String, Object?> args,
  ) {
    return _start(entry, args);
  }

  static Future<LocalLlmWorkerClientImpl> _start(
    void Function(Map<String, Object?>) entry,
    Map<String, Object?> args,
  ) async {
    final ReceivePort mainPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();

    final Completer<SendPort> workerReady = Completer<SendPort>();
    final Completer<void> started = Completer<void>();
    // Both handshake futures may be completed with an error when startup
    // fails; attach swallow listeners so whichever one is not awaited still
    // has a listener (awaiting later still surfaces the error).
    workerReady.future.ignore();
    started.future.ignore();
    LocalLlmWorkerClientImpl? impl;
    bool handshakeDone = false;

    void failStartup(Object error) {
      if (!workerReady.isCompleted) {
        workerReady.completeError(error);
      }
      if (!started.isCompleted) {
        started.completeError(error);
      }
    }

    // A ReceivePort is single-subscription: one listener handles the startup
    // handshake and, once `handshakeDone`, dispatches steady-state messages.
    final StreamSubscription<Object?> mainSub = mainPort.listen((
      Object? message,
    ) {
      if (!handshakeDone) {
        final Map<String, Object?> map = message! as Map<String, Object?>;
        switch (map['type']) {
          case 'workerReady':
            if (!workerReady.isCompleted) {
              workerReady.complete(map['port']! as SendPort);
            }
          case 'started':
            if (!started.isCompleted) {
              started.complete();
            }
          case 'startupError':
            failStartup(LlmWorkerException(map['message']! as String));
          default:
            break;
        }
        return;
      }
      impl?._handleWorkerMessage(message);
    });

    final StreamSubscription<Object?> exitSub = exitPort.listen((Object? _) {
      if (!started.isCompleted) {
        failStartup(
          const LlmWorkerException('worker isolate exited during startup'),
        );
        return;
      }
      impl?._onWorkerGone('worker isolate exited unexpectedly');
    });

    final StreamSubscription<Object?> errorSub = errorPort.listen((
      Object? raw,
    ) {
      final String detail = raw is List && raw.isNotEmpty
          ? raw.first.toString()
          : raw.toString();
      if (!started.isCompleted) {
        failStartup(
          LlmWorkerException('worker isolate failed during startup: $detail'),
        );
        return;
      }
      impl?._onWorkerGone('worker isolate failed: $detail');
    });

    final Isolate worker;
    try {
      worker = await Isolate.spawn<Map<String, Object?>>(
        entry,
        <String, Object?>{...args, 'mainPort': mainPort.sendPort},
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
      );
    } on Object catch (error) {
      await mainSub.cancel();
      await exitSub.cancel();
      await errorSub.cancel();
      mainPort.close();
      exitPort.close();
      errorPort.close();
      throw LlmWorkerException('failed to spawn worker isolate: $error');
    }

    final SendPort workerPort;
    try {
      workerPort = await workerReady.future;
      await started.future;
    } on Object catch (error) {
      await mainSub.cancel();
      await exitSub.cancel();
      await errorSub.cancel();
      mainPort.close();
      exitPort.close();
      errorPort.close();
      worker.kill(priority: Isolate.immediate);
      if (error is LlmWorkerException) {
        rethrow;
      }
      throw LlmWorkerException('worker isolate startup failed: $error');
    }

    handshakeDone = true;

    final LocalLlmWorkerClientImpl client = LocalLlmWorkerClientImpl._(
      worker: worker,
      workerPort: workerPort,
      mainPort: mainPort,
      mainSub: mainSub,
      exitPort: exitPort,
      errorPort: errorPort,
      exitSub: exitSub,
      errorSub: errorSub,
    );
    impl = client;
    return client;
  }

  final Isolate _worker;
  final SendPort _workerPort;
  final ReceivePort _mainPort;
  final StreamSubscription<Object?> _mainSub;
  final ReceivePort _exitPort;
  final ReceivePort _errorPort;
  final StreamSubscription<Object?> _exitSub;
  final StreamSubscription<Object?> _errorSub;

  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  int _nextRequestId = 0;
  bool _disposed = false;
  bool _stopped = false;
  String? _failure;
  Completer<void>? _shutdownCompleter;
  Future<void>? _disposeFuture;

  @override
  Future<String> generateChat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 128,
  }) {
    _ensureUsable();
    final int requestId = _nextRequestId++;
    final Completer<String> completer = Completer<String>();
    _pending[requestId] = completer;
    _workerPort.send(<String, Object?>{
      'type': 'chat',
      'requestId': requestId,
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
      'maxTokens': maxTokens,
    });
    return completer.future;
  }

  @override
  Future<void> dispose() {
    final Future<void>? existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }

    // Reject new requests before putting shutdown behind already queued work.
    _disposed = true;
    final Future<void> disposal = _disposeInternal();
    _disposeFuture = disposal;
    return disposal;
  }

  Future<void> _disposeInternal() async {
    if (_stopped) {
      await _close();
      return;
    }

    final Completer<void> shutdown = Completer<void>();
    _shutdownCompleter = shutdown;
    try {
      _workerPort.send(<String, Object?>{'type': 'shutdown'});
    } on Object catch (error) {
      _onWorkerGone('failed to send worker shutdown: $error');
    }
    await shutdown.future;
    await _close();
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError(
        'LocalLlmWorkerClientImpl is disposed; create a new client',
      );
    }
    if (_stopped) {
      throw StateError(
        'LocalLlmWorkerClientImpl worker is not running: $_failure',
      );
    }
  }

  void _handleWorkerMessage(Object? message) {
    final Map<String, Object?> map = message! as Map<String, Object?>;
    switch (map['type']) {
      case 'result':
        _complete(
          map['requestId']! as int,
          (Completer<String> completer) =>
              completer.complete(map['text']! as String),
        );
      case 'error':
        final String message = map['message']! as String;
        _complete(
          map['requestId']! as int,
          (Completer<String> completer) =>
              completer.completeError(LlmWorkerException(message)),
        );
      case 'stopped':
        _markStopped();
      default:
        break; // Unknown message types are ignored defensively.
    }
  }

  void _complete(
    int requestId,
    void Function(Completer<String> completer) action,
  ) {
    final Completer<String>? completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return; // Unknown or stale request ID — ignore defensively.
    }
    action(completer);
  }

  void _markStopped() {
    _stopped = true;
    _failure ??= 'worker stopped';
    final Completer<void>? shutdown = _shutdownCompleter;
    if (shutdown != null && !shutdown.isCompleted) {
      shutdown.complete();
    }
  }

  void _onWorkerGone(String reason) {
    _stopped = true;
    _failure = reason;
    final Map<int, Completer<String>> pending =
        Map<int, Completer<String>>.from(_pending);
    _pending.clear();
    for (final Completer<String> completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(LlmWorkerException(reason));
      }
    }
    final Completer<void>? shutdown = _shutdownCompleter;
    if (shutdown != null && !shutdown.isCompleted) {
      shutdown.complete();
    }
  }

  Future<void> _close() async {
    await _mainSub.cancel();
    await _exitSub.cancel();
    await _errorSub.cancel();
    _mainPort.close();
    _exitPort.close();
    _errorPort.close();
    // The worker exits on its own after a clean shutdown; this kill is only a
    // safeguard for the unexpected-exit paths.
    _worker.kill(priority: Isolate.immediate);
  }
}
