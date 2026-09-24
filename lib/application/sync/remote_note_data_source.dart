/// Application port for the remote note sync adapter.
library;

import 'sync_mutation.dart';
import 'sync_result.dart';
import 'sync_snapshot.dart';

abstract interface class IRemoteNoteDataSource {
  Future<SyncMutationResult> push(SyncMutation mutation);

  Future<SyncChangesPage> pull({String? cursor, int limit = 50});
}
