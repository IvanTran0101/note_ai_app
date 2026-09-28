/// Provider-neutral failures for one remote sync call.
library;

enum SyncErrorCode {
  networkUnavailable,
  timeout,
  serverUnavailable,
  throttled,
  unauthorized,
  forbidden,
  invalidMutation,
  unexpected,
}

final class SyncFailure implements Exception {
  const SyncFailure({required this.code, this.detail});

  final SyncErrorCode code;
  final String? detail;

  bool get retryable {
    return switch (code) {
      SyncErrorCode.networkUnavailable ||
      SyncErrorCode.timeout ||
      SyncErrorCode.serverUnavailable ||
      SyncErrorCode.throttled => true,
      _ => false,
    };
  }

  @override
  String toString() => 'SyncFailure(${code.name})';
}
