import 'dart:async';

import 'package:http/http.dart' as http;

/// Cancel actual HTTP work on timeout or access loss, including while awaiting
/// response headers. A Future.timeout alone leaves the underlying fetch running.
Future<T> attachmentHttpRequest<T>({
  required http.Client client,
  required String method,
  required Uri uri,
  required void Function() requireAccess,
  required Future<T> Function(http.StreamedResponse) consume,
  required void Function(http.Request) configure,
  Duration timeout = const Duration(seconds: 30),
  Future<void>? cancel,
  void Function(T result)? discard,
}) async {
  final abort = Completer<void>();
  Object? failure;
  void stop(Object reason) {
    failure ??= reason;
    if (!abort.isCompleted) abort.complete();
  }

  final watch = Timer.periodic(const Duration(milliseconds: 100), (_) {
    try {
      requireAccess();
    } on Object catch (e) {
      stop(e);
    }
  });
  final deadline = Timer(
    timeout,
    () => stop(TimeoutException('Attachment request timed out.')),
  );
  if (cancel != null) {
    unawaited(
      cancel.then(
        (_) => stop(StateError('Attachment transfer was cancelled.')),
      ),
    );
  }
  var acquired = false;
  late T result;
  try {
    requireAccess();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..maxRedirects = 0;
    configure(request);
    final response = await client.send(request).timeout(timeout);
    result = await consume(response).timeout(timeout);
    acquired = true;
    requireAccess();
    if (failure != null) throw failure!;
    return result;
  } on Object {
    if (acquired) discard?.call(result);
    if (failure != null) throw failure!;
    rethrow;
  } finally {
    watch.cancel();
    deadline.cancel();
    if (!abort.isCompleted) abort.complete();
  }
}
