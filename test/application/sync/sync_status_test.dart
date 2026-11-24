import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_status.dart';

void main() {
  test('freezes the four sync statuses', () {
    expect(SyncStatus.values, <SyncStatus>[
      SyncStatus.idle,
      SyncStatus.offline,
      SyncStatus.syncing,
      SyncStatus.failed,
    ]);
  });

  test('offers const snapshots for the failure-free statuses', () {
    expect(const SyncStatusSnapshot.idle().status, SyncStatus.idle);
    expect(const SyncStatusSnapshot.offline().status, SyncStatus.offline);
    expect(const SyncStatusSnapshot.syncing().status, SyncStatus.syncing);
    expect(const SyncStatusSnapshot.syncing().isSyncing, isTrue);
    expect(const SyncStatusSnapshot.idle().isSyncing, isFalse);
    expect(const SyncStatusSnapshot.idle().failure, isNull);
    expect(
      const SyncStatusSnapshot.idle(),
      SyncStatusSnapshot(status: SyncStatus.idle),
    );
  });

  test('pairs a failure with the failed status only', () {
    const SyncFailure failure = SyncFailure(code: SyncErrorCode.timeout);
    final SyncStatusSnapshot failed = SyncStatusSnapshot.failed(failure);

    expect(failed.status, SyncStatus.failed);
    expect(failed.failure, same(failure));
    expect(failed.isFailed, isTrue);
    expect(
      failed,
      SyncStatusSnapshot(status: SyncStatus.failed, failure: failure),
    );

    expect(
      () => SyncStatusSnapshot(status: SyncStatus.offline, failure: failure),
      throwsArgumentError,
    );
    expect(
      () => SyncStatusSnapshot(status: SyncStatus.failed),
      throwsArgumentError,
    );
  });

  test('compares by status and failure', () {
    const SyncFailure failure = SyncFailure(code: SyncErrorCode.timeout);

    expect(
      SyncStatusSnapshot.failed(failure),
      SyncStatusSnapshot.failed(failure),
    );
    expect(
      SyncStatusSnapshot.failed(failure).hashCode,
      SyncStatusSnapshot.failed(failure).hashCode,
    );
    expect(
      const SyncStatusSnapshot.idle(),
      isNot(const SyncStatusSnapshot.syncing()),
    );
    expect(
      SyncStatusSnapshot.failed(failure),
      isNot(
        SyncStatusSnapshot.failed(
          const SyncFailure(code: SyncErrorCode.unauthorized),
        ),
      ),
    );
  });
}
