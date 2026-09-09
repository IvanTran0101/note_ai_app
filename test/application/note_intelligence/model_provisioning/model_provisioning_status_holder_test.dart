import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';

final DateTime _updatedAt = DateTime.utc(2026, 9, 9, 12, 0, 0);

ModelProvisioningState _phase(ModelProvisioningPhase phase) {
  return ModelProvisioningState(phase: phase, updatedAt: _updatedAt);
}

void main() {
  group('ModelProvisioningStatusHolder', () {
    test('starts idle in UTC before the first publish', () {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);

      final IModelProvisioningReader reader = holder;

      expect(reader.current.phase, ModelProvisioningPhase.idle);
      expect(reader.current.modelId, isNull);
      expect(reader.current.failure, isNull);
      expect(reader.current.updatedAt.isUtc, isTrue);
    });

    test('accepts an explicit initial snapshot', () {
      final ModelProvisioningState initial = _phase(
        ModelProvisioningPhase.artifactReady,
      );
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder(initial: initial);
      addTearDown(holder.close);

      expect(holder.current, initial);
      expect(identical(holder.current, initial), isTrue);
    });

    test('publish updates current and broadcasts the same instance', () async {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);
      final IModelProvisioningReader reader = holder;
      final IModelProvisioningReporter reporter = holder;

      final ModelProvisioningState detecting = ModelProvisioningState(
        phase: ModelProvisioningPhase.detectingDevice,
        updatedAt: _updatedAt,
      );
      final ModelProvisioningState ready = _phase(ModelProvisioningPhase.ready);

      final List<ModelProvisioningState> received = <ModelProvisioningState>[];
      final StreamSubscription<ModelProvisioningState> subscription = reader
          .watch()
          .listen(received.add);
      addTearDown(subscription.cancel);

      reporter.publish(detecting);
      reporter.publish(ready);
      await pumpEventQueue();

      expect(received, <ModelProvisioningState>[detecting, ready]);
      expect(identical(received[0], detecting), isTrue);
      expect(identical(received[1], ready), isTrue);
      expect(identical(holder.current, ready), isTrue);
    });

    test('watch never replays history to late subscribers', () async {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);
      final IModelProvisioningReader reader = holder;
      final IModelProvisioningReporter reporter = holder;

      final ModelProvisioningState downloading = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        downloadedBytes: 512,
        totalBytes: 1024,
        updatedAt: _updatedAt,
      );
      reporter.publish(downloading);

      final List<ModelProvisioningState> received = <ModelProvisioningState>[];
      final StreamSubscription<ModelProvisioningState> subscription = reader
          .watch()
          .listen(received.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(received, isEmpty, reason: 'history is not replayed');
      expect(holder.current, downloading);

      final ModelProvisioningState failed = ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        failure: const ModelProvisioningFailure(
          code: ModelProvisioningFailureCode.unexpected,
        ),
        updatedAt: _updatedAt,
      );
      reporter.publish(failed);
      await pumpEventQueue();

      expect(received, <ModelProvisioningState>[failed]);
      expect(holder.current, failed);
    });

    test('delivers every snapshot to multiple concurrent readers', () async {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);
      final IModelProvisioningReader reader = holder;
      final IModelProvisioningReporter reporter = holder;

      final List<ModelProvisioningState> first = <ModelProvisioningState>[];
      final List<ModelProvisioningState> second = <ModelProvisioningState>[];
      final StreamSubscription<ModelProvisioningState> firstSubscription =
          reader.watch().listen(first.add);
      final StreamSubscription<ModelProvisioningState> secondSubscription =
          reader.watch().listen(second.add);
      addTearDown(firstSubscription.cancel);
      addTearDown(secondSubscription.cancel);

      final ModelProvisioningState verifying = _phase(
        ModelProvisioningPhase.verifying,
      );
      reporter.publish(verifying);
      await pumpEventQueue();

      expect(first, <ModelProvisioningState>[verifying]);
      expect(second, <ModelProvisioningState>[verifying]);
    });

    test('publishes the caller snapshot unchanged without mutation', () {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);
      final IModelProvisioningReporter reporter = holder;

      final ModelProvisioningState state = ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        downloadedBytes: 1,
        totalBytes: 2,
        updatedAt: _updatedAt,
      );
      reporter.publish(state);

      expect(identical(holder.current, state), isTrue);
      expect(holder.current.phase, ModelProvisioningPhase.downloading);
      expect(holder.current.downloadedBytes, 1);
      expect(holder.current.totalBytes, 2);
    });
  });
}
