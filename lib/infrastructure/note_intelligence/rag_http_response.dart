part of 'rag_http_gateway.dart';

/// Bounded response reading for the RAG gateway.
///
/// The 64 KiB transport cap, the stream subscription that must be cancelled on
/// overflow, cancellation, deadline and close, and the abort trigger that ends a
/// body read the client cannot abort by itself are one responsibility, so they
/// live together here.
extension _RagResponse on RagHttpGateway {
  /// Reads a response body under [RagHttpGateway.maxResponseBytes].
  ///
  /// Returns null when the body broke the cap: the request is aborted and the
  /// connection released without buffering any further chunk, and the caller
  /// classifies the exchange from its status alone. Throws the call's failure
  /// when the call was cancelled, closed, or timed out, and lets a real
  /// transport error through for the caller to classify.
  Future<Uint8List?> _readBody(
    RagHttpCall call,
    http.StreamedResponse response,
  ) async {
    final int? declared = response.contentLength;
    if (declared != null && declared > RagHttpGateway.maxResponseBytes) {
      // Release the advertised body without buffering any of it.
      call.abortForOversize();
      await _discard(response);
      return null;
    }

    final BytesBuilder builder = BytesBuilder(copy: false);
    final Completer<Uint8List> done = Completer<Uint8List>();
    void fail(Object error, [StackTrace? stackTrace]) {
      if (!done.isCompleted) {
        done.completeError(error, stackTrace);
      }
    }

    final StreamSubscription<List<int>> subscription = response.stream.listen(
      (List<int> chunk) {
        // Once refused, or once the read settled, no later event may retain a
        // single byte: a synchronous burst must not grow past the cap even
        // before the cancel lands.
        if (done.isCompleted || call.isOversize) {
          return;
        }
        final int remaining = RagHttpGateway.maxResponseBytes - builder.length;
        if (chunk.length > remaining) {
          // Refuse before appending, so neither one giant chunk nor a burst can
          // ever be buffered beyond `maxResponseBytes`.
          call.abortForOversize();
          fail(call.failure);
          return;
        }
        builder.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) => fail(error, stackTrace),
      onDone: () {
        if (!done.isCompleted) {
          done.complete(builder.takeBytes());
        }
      },
      cancelOnError: true,
    );
    // The deadline and cancellation must also stop a body read that the client
    // cannot abort by itself; the trigger completes without error by contract.
    unawaited(call.abortTrigger.then((void _) => fail(call.failure)));
    try {
      return await done.future;
    } on RagFailure {
      // Oversize is a refusal the mapper decides; a stop is rechecked by the
      // caller, which has the call's failure.
      return null;
    } on http.ClientException {
      // Releasing an oversize body aborts its request, and `package:http` then
      // injects a `RequestAbortedException` into the stream. That abort is the
      // gateway's own release, so after a refusal the known HTTP status still
      // classifies the exchange; it must never be remapped to a network error.
      if (call.isOversize) {
        return null;
      }
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }

  /// Releases a response this call will not read, without buffering it.
  Future<void> _discard(http.StreamedResponse response) async {
    try {
      // An aborted response may push its `RequestAbortedException` after the
      // cancel is requested; swallowing it keeps releasing side-effect free.
      await response.stream.listen(null, onError: (Object _) {}).cancel();
    } on Object {
      // Releasing a refused response must not fail the call; the connection is
      // dropped either way.
    }
  }
}
