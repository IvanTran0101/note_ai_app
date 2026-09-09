import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';

final DateTime _updatedAt = DateTime.utc(2026, 9, 9, 12, 0, 0);

/// Small in-memory boundary used as the contract-shape fixture.
///
/// It is the minimal conforming implementation of both ports: [publish] keeps
/// [current] equal to the last snapshot and broadcasts every snapshot to live
/// [watch] listeners without replaying to late subscribers.
final class _InMemoryProvisioningBoundary
    implements IModelProvisioningReader, IModelProvisioningReporter {
  _InMemoryProvisioningBoundary({required ModelProvisioningState initial})
    : _current = initial,
      _controller = StreamController<ModelProvisioningState>.broadcast();

  final StreamController<ModelProvisioningState> _controller;

  ModelProvisioningState _current;

  @override
  ModelProvisioningState get current => _current;

  @override
  Stream<ModelProvisioningState> watch() => _controller.stream;

  @override
  void publish(ModelProvisioningState state) {
    _current = state;
    _controller.add(state);
  }

  Future<void> close() => _controller.close();
}

ModelProvisioningState _phase(ModelProvisioningPhase phase) {
  return ModelProvisioningState(phase: phase, updatedAt: _updatedAt);
}

void main() {
  group('IModelProvisioningReader / IModelProvisioningReporter contract', () {
    test('reader exposes the initial snapshot before any publish', () async {
      final ModelProvisioningState initial = _phase(
        ModelProvisioningPhase.idle,
      );
      final _InMemoryProvisioningBoundary boundary =
          _InMemoryProvisioningBoundary(initial: initial);
      addTearDown(boundary.close);

      final IModelProvisioningReader reader = boundary;

      expect(reader.current, initial);
    });

    test(
      'publish updates current and streams each snapshot in order',
      () async {
        final _InMemoryProvisioningBoundary boundary =
            _InMemoryProvisioningBoundary(
              initial: _phase(ModelProvisioningPhase.idle),
            );
        addTearDown(boundary.close);
        final IModelProvisioningReader reader = boundary;
        final IModelProvisioningReporter reporter = boundary;

        final ModelProvisioningState downloading = ModelProvisioningState(
          phase: ModelProvisioningPhase.downloading,
          modelId: 'gemma-3-1b-it',
          downloadedBytes: 512,
          totalBytes: 1024,
          updatedAt: _updatedAt,
        );
        final ModelProvisioningState verifying = _phase(
          ModelProvisioningPhase.verifying,
        );
        final ModelProvisioningState ready = _phase(
          ModelProvisioningPhase.ready,
        );

        final List<ModelProvisioningState> received =
            <ModelProvisioningState>[];
        final StreamSubscription<ModelProvisioningState> subscription = reader
            .watch()
            .listen(received.add);
        addTearDown(subscription.cancel);

        reporter.publish(downloading);
        reporter.publish(verifying);
        reporter.publish(ready);
        await pumpEventQueue();

        expect(received, <ModelProvisioningState>[
          downloading,
          verifying,
          ready,
        ]);
        expect(reader.current, ready);
        expect(identical(reader.current, ready), isTrue);
      },
    );

    test(
      'watch does not replay published history to late subscribers',
      () async {
        final _InMemoryProvisioningBoundary boundary =
            _InMemoryProvisioningBoundary(
              initial: _phase(ModelProvisioningPhase.idle),
            );
        addTearDown(boundary.close);
        final IModelProvisioningReader reader = boundary;
        final IModelProvisioningReporter reporter = boundary;

        final ModelProvisioningState downloading = ModelProvisioningState(
          phase: ModelProvisioningPhase.downloading,
          downloadedBytes: 512,
          updatedAt: _updatedAt,
        );
        reporter.publish(downloading);

        final List<ModelProvisioningState> received =
            <ModelProvisioningState>[];
        final StreamSubscription<ModelProvisioningState> subscription = reader
            .watch()
            .listen(received.add);
        addTearDown(subscription.cancel);

        await pumpEventQueue();
        expect(received, isEmpty, reason: 'history is not replayed');
        expect(
          reader.current,
          downloading,
          reason: 'callers read current before subscribing for full state',
        );

        final ModelProvisioningState ready = _phase(
          ModelProvisioningPhase.ready,
        );
        reporter.publish(ready);
        await pumpEventQueue();

        expect(received, <ModelProvisioningState>[ready]);
        expect(reader.current, ready);
      },
    );

    test(
      'supports multiple concurrent readers of one shared boundary',
      () async {
        final _InMemoryProvisioningBoundary boundary =
            _InMemoryProvisioningBoundary(
              initial: _phase(ModelProvisioningPhase.idle),
            );
        addTearDown(boundary.close);
        final IModelProvisioningReader reader = boundary;
        final IModelProvisioningReporter reporter = boundary;

        final ModelProvisioningState downloading = ModelProvisioningState(
          phase: ModelProvisioningPhase.downloading,
          modelId: 'gemma-3-1b-it',
          downloadedBytes: 256,
          updatedAt: _updatedAt,
        );
        final List<ModelProvisioningState> first = <ModelProvisioningState>[];
        final List<ModelProvisioningState> second = <ModelProvisioningState>[];
        final StreamSubscription<ModelProvisioningState> firstSubscription =
            reader.watch().listen(first.add);
        final StreamSubscription<ModelProvisioningState> secondSubscription =
            reader.watch().listen(second.add);
        addTearDown(firstSubscription.cancel);
        addTearDown(secondSubscription.cancel);

        reporter.publish(downloading);
        await pumpEventQueue();

        expect(first, <ModelProvisioningState>[downloading]);
        expect(second, <ModelProvisioningState>[downloading]);
        expect(reader.current, downloading);
      },
    );
  });
}
