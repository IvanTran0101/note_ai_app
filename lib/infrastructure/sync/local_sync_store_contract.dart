/// Platform-neutral vocabulary for the M2.1 local sync store adapters.
///
/// Native JSON, Web IndexedDB, and the unsupported-platform stub share these
/// types, so every adapter reports the same failure vocabulary and every
/// factory accepts the same native test seam. Nothing here imports `dart:io`,
/// `package:path_provider`, or a browser binding, so the library compiles and
/// the Web implementation can reuse it.
library;

/// Resolves the application-private support directory as an absolute path
/// string.
///
/// A plain function so the native adapter stays injectable in unit tests
/// without a `path_provider` plugin channel. The Web and stub factories accept
/// the same parameter and ignore it, because only the native adapter stores
/// state in a file.
typedef LocalSyncApplicationSupportPathResolver = Future<String> Function();

/// Why a local sync store operation failed, without naming any stored value.
enum LocalSyncStoreFailure {
  /// The backing store cannot be reached at all: the support directory cannot
  /// be resolved, or the IndexedDB database cannot be opened.
  unavailable,

  /// Stored state exists but could not be read from the backing store.
  unreadable,

  /// Stored state does not match the frozen schemaVersion 2 envelope, so it
  /// cannot be decoded without losing local note state.
  malformed,

  /// The state belongs to another account than the one this store is bound to,
  /// either as the replacement argument or as the stored document.
  foreignAccount,

  /// The state could not be written to the backing store. A failed replacement
  /// leaves any previously stored state in place.
  unwritable,
}

/// The one failure the local sync stores raise.
///
/// A message names the operation and the rule that failed, never a stored
/// value: note titles, note content, mutation ids, cursor values, account ids,
/// IndexedDB database names, and filesystem paths must not reach a log, a
/// crash report, or a user-visible message through a store failure.
///
/// The exception deliberately has no `cause`, because a wrapped filesystem,
/// browser, or codec exception can carry any of those values.
final class LocalSyncStoreException implements Exception {
  /// Creates a failure with a value-free [message] and its [failure] kind.
  const LocalSyncStoreException(this.failure, this.message);

  /// Why the operation failed, for a caller that must react differently to a
  /// corrupt document and to an unreachable backing store.
  final LocalSyncStoreFailure failure;

  /// What failed, phrased without any persisted value.
  final String message;

  @override
  String toString() => 'LocalSyncStoreException(${failure.name}): $message';
}
