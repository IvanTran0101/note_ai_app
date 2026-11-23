/// Application port for the remote note sync adapter.
library;

import 'sync_mutation.dart';
import 'sync_result.dart';
import 'sync_snapshot.dart';

abstract interface class IRemoteNoteDataSource {
  Future<SyncMutationResult> push(SyncMutation mutation);

  Future<SyncChangesPage> pull({String? cursor, int limit = 50});
}

/// Negotiate before choosing a pull cursor, so old cached notes are backfilled.
/// The probe never owns or advances the account cursor.
abstract interface class ISyncWireNegotiation {
  Future<int> negotiateWireVersion();
}
