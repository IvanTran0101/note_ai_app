/// Opaque remote change-feed cursor.
library;

/// An opaque position in the remote note change feed.
///
/// The value is stored and sent back exactly as received. It is never parsed,
/// split, decoded, compared numerically, trimmed, or rebuilt from its parts:
/// only the server that issued it can interpret it. A null [value] means no
/// cursor has been recorded.
final class SyncCursor {
  /// Wraps an already opaque cursor value.
  const SyncCursor(this.value);

  /// The server-issued value, kept byte-for-byte as received.
  final String? value;

  /// True when a value was recorded. The value itself is never interpreted.
  bool get hasValue => value != null;

  @override
  bool operator ==(Object other) {
    return other is SyncCursor && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  /// Never renders [value]: the cursor stays opaque in logs and diagnostics.
  @override
  String toString() => hasValue ? 'SyncCursor(opaque)' : 'SyncCursor(none)';
}
