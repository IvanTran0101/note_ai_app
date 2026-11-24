import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/sync/sync_coordinator.dart';
import 'package:note_ai_app/application/sync/sync_failure.dart';
import 'package:note_ai_app/application/sync/sync_report.dart';
import 'package:note_ai_app/application/sync/sync_status.dart';

/// Minimal coordinator used only to pin the port's shape.
///
/// M2.0 ships no production coordinator, so the contract is exercised through
/// this fake: status is readable synchronously, changes stream to listeners,
/// and one run returns a report.
final class _FakeSyncCoordinator implements ISyncCoordinator {
  _FakeSyncCoordinator({this.failure, SyncReport? report})
    : report = report ?? SyncReport(applied: 2, pulled: 1);

  final SyncFailure? failure;
  final SyncReport report;
  final StreamController<SyncStatusSnapshot> _changesController =
      StreamController<SyncStatusSnapshot>.broadcast();
  SyncStatusSnapshot _status = const SyncStatusSnapshot.idle();

  @override
  SyncStatusSnapshot get status => _status;

  @override
  Stream<SyncStatusSnapshot> get statusChanges => _changesController.stream;

  @override
  Future<SyncReport> syncNow() async {
    final SyncFailure? endingFailure = failure;
    _publish(const SyncStatusSnapshot.syncing());
    if (endingFailure != null) {
      _publish(SyncStatusSnapshot.failed(endingFailure));
      throw endingFailure;
    }
    _publish(const SyncStatusSnapshot.idle());
    return report;
  }

  void _publish(SyncStatusSnapshot snapshot) {
    _status = snapshot;
    _changesController.add(snapshot);
  }

  Future<void> dispose() => _changesController.close();
}

void main() {
  test('exposes status synchronously and streams transitions', () async {
    final _FakeSyncCoordinator coordinator = _FakeSyncCoordinator();
    addTearDown(coordinator.dispose);
    final List<SyncStatusSnapshot> observed = <SyncStatusSnapshot>[];
    final StreamSubscription<SyncStatusSnapshot> subscription = coordinator
        .statusChanges
        .listen(observed.add);

    expect(coordinator.status, const SyncStatusSnapshot.idle());
    final SyncReport report = await coordinator.syncNow();
    await pumpEventQueue();
    await subscription.cancel();

    expect(report.applied, 2);
    expect(report.pulled, 1);
    expect(report.conflicts, 0);
    expect(
      observed.map((SyncStatusSnapshot snapshot) => snapshot.status),
      <SyncStatus>[SyncStatus.syncing, SyncStatus.idle],
    );
    expect(coordinator.status.isSyncing, isFalse);
  });

  test('publishes an ending failure and reports it to the caller', () async {
    const SyncFailure failure = SyncFailure(code: SyncErrorCode.throttled);
    final _FakeSyncCoordinator coordinator = _FakeSyncCoordinator(
      failure: failure,
    );
    addTearDown(coordinator.dispose);
    final List<SyncStatusSnapshot> observed = <SyncStatusSnapshot>[];
    final StreamSubscription<SyncStatusSnapshot> subscription = coordinator
        .statusChanges
        .listen(observed.add);

    await expectLater(coordinator.syncNow(), throwsA(same(failure)));
    await pumpEventQueue();
    await subscription.cancel();

    expect(coordinator.status.isFailed, isTrue);
    expect(coordinator.status.failure, same(failure));
    expect(observed.last.status, SyncStatus.failed);
    expect(observed.first.status, SyncStatus.syncing);
  });

  test('the port is implementable without any provider type', () {
    expect(_FakeSyncCoordinator(), isA<ISyncCoordinator>());
  });
}
