/// Opaque cursor mapping for the M2 local sync schema.
library;

import '../../application/sync/sync_cursor.dart';
import 'local_sync_codec_exception.dart';

/// Maps [SyncCursor] to and from its stored form.
///
/// The stored form is the raw string, or null when no cursor is recorded. The
/// value is opaque: it is written and read back byte-for-byte, without trimming,
/// decoding, parsing, length checking, or normalization. Nothing here renders it
/// in a failure, so a cursor value cannot leak through a decode error.
abstract final class SyncCursorCodec {
  /// Returns the stored form of [cursor]: its raw value, or null for none.
  static String? encode(SyncCursor? cursor) => cursor?.value;

  /// Wraps the stored value, rejecting anything that is neither null nor text.
  ///
  /// An empty string is preserved as a recorded value rather than folded into
  /// null: only this codec's caller may decide what an empty cursor means.
  static SyncCursor? decode(Object? data, {String path = 'cursor'}) {
    if (data == null) {
      return null;
    }
    if (data is! String) {
      throw LocalSyncCodecException('must be a string or null.', path: path);
    }
    return SyncCursor(data);
  }
}
