/// Typed failure raised by the M2 local sync state codec.
library;

/// The one failure the local sync codecs raise for malformed input.
///
/// A message names the field and the rule that failed, never the stored value:
/// a note title, note content, mutation id, or cursor value must not reach a
/// log, a crash report, or a user-visible message through a decode failure.
/// The exception deliberately has no `cause`, because a wrapped model or
/// provider exception could carry either.
final class LocalSyncCodecException implements Exception {
  /// Creates a failure with a value-free [message] and optional [path].
  const LocalSyncCodecException(this.message, {this.path});

  /// What is wrong, phrased without any persisted value.
  final String message;

  /// Where it is wrong, for example `notes[2].title`.
  ///
  /// The path is structural: indexes and schema field names only.
  final String? path;

  @override
  String toString() {
    final String? location = path;
    if (location == null || location.isEmpty) {
      return 'LocalSyncCodecException: $message';
    }
    return 'LocalSyncCodecException: $message (at $location)';
  }
}
