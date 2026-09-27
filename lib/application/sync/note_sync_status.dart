/// Local sync standing of one stored note.
library;

/// Where one locally stored note stands relative to the remote change feed.
///
/// The status describes local bookkeeping only: it says whether the note has a
/// queued mutation, whether the last push failed, and whether the server
/// rejected a mutation. It never describes remote-only state.
enum NoteSyncStatus {
  /// There is no queued mutation for this note and the last push applied.
  synced,

  /// A local change is queued and has not been acknowledged by the server yet.
  pending,

  /// The last push attempt failed and the note needs attention or a retry.
  failed,

  /// The server rejected a queued mutation with a revision conflict.
  conflict,
}
