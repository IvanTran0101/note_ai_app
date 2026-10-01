part of 'summary_http_gateway.dart';

/// Bounded response reading and safe transport error classification.
extension _SummaryResponse on SummaryHttpGateway {
  /// Reads the response body under [SummaryHttpGateway.maxResponseBytes], cancelling the stream as
  Future<Uint8List> _readBounded(
    SummaryHttpCall call,
    http.StreamedResponse response,
  ) async {
    final int? declared = response.contentLength;
    if (declared != null && declared > SummaryHttpGateway.maxResponseBytes) {
      // Release the advertised body without buffering any of it.
      call.abortForOversize();
      await _discard(response);
      throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidOutput);
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
        builder.add(chunk);
        if (builder.length > SummaryHttpGateway.maxResponseBytes) {
          call.abortForOversize();
          fail(
            const SummaryApiFailure(code: SummaryApiErrorCode.invalidOutput),
          );
        }
      },
      onError: fail,
      onDone: () {
        if (!done.isCompleted) {
          done.complete(builder.takeBytes());
        }
      },
      cancelOnError: true,
    );
    // The deadline must also stop a body read that the client cannot abort by
    // itself; the trigger completes without error by contract.
    unawaited(
      call.abortTrigger.then((void _) {
        if (call.cancelled) {
          fail(call.cancellationFailure());
        } else {
          fail(const SummaryApiFailure(code: SummaryApiErrorCode.timeout));
        }
      }),
    );
    try {
      return await done.future;
    } finally {
      await subscription.cancel();
    }
  }

  /// Releases a response this call will not read, without buffering it.
  Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen(null).cancel();
    } on Object {
      // Releasing a response that was already refused must not fail the refresh
      // path; the connection is dropped either way.
    }
  }

  Future<T> _classify<T>(
    SummaryHttpCall call,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on SummaryRunFailure {
      rethrow;
    } on SummaryApiFailure {
      rethrow;
    } on TimeoutException {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
    } on http.ClientException {
      if (call.cancelled) {
        throw call.cancellationFailure();
      }
      // `package:http` wraps socket-level failures in this type on IO platforms
      // and raises it directly on Web, and the abort trigger injects it as a
      // `RequestAbortedException`. The call's own state tells the two aborts
      // apart from a real transport failure.
      if (call.timedOut) {
        throw const SummaryApiFailure(code: SummaryApiErrorCode.timeout);
      }
      if (call.aborted) {
        throw const SummaryApiFailure(code: SummaryApiErrorCode.invalidOutput);
      }
      throw const SummaryApiFailure(
        code: SummaryApiErrorCode.networkUnavailable,
      );
    } catch (_) {
      throw const SummaryApiFailure(code: SummaryApiErrorCode.unexpected);
    }
  }
}
