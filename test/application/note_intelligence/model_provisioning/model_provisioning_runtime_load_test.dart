import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_runtime_load.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';

final DateTime _updatedAt = DateTime.utc(2026, 9, 9, 12, 0, 0);
DateTime _fixedNow() => _updatedAt;

ModelProvisioningFailure _mapAs(Object error) {
  return ModelProvisioningFailure(
    code: ModelProvisioningFailureCode.runtimeLoadFailed,
    detail: 'safe runtime detail',
  );
}

/// Records the relative order of publication and load execution so the helper
/// ordering can be asserted deterministically.
final class _OrderRecordingReporter implements IModelProvisioningReporter {
  final List<String> events = <String>[];

  @override
  void publish(ModelProvisioningState state) {
    events.add('publish:${state.phase.name}');
  }
}

void main() {
  group('runModelProvisioningRuntimeLoad', () {
    test(
      'publishes loadingRuntime before load and ready only after success',
      () async {
        final _OrderRecordingReporter reporter = _OrderRecordingReporter();
        final Completer<String> loadGate = Completer<String>();
        final List<String> loadEvents = <String>[];

        final Future<String> pending = runModelProvisioningRuntimeLoad<String>(
          reporter: reporter,
          modelId: 'gemma-3-1b-it',
          modelName: 'gemma-3-1b-it-Q4_K_M.gguf',
          mapFailure: _mapAs,
          now: _fixedNow,
          load: () async {
            loadEvents.add('load:start');
            final String result = await loadGate.future;
            loadEvents.add('load:end');
            return result;
          },
        );

        await pumpEventQueue();
        expect(reporter.events, <String>[
          'publish:loadingRuntime',
        ], reason: 'loadingRuntime is published before the load starts');
        expect(loadEvents, <String>['load:start']);

        loadGate.complete('service');
        expect(await pending, 'service');

        expect(reporter.events, <String>[
          'publish:loadingRuntime',
          'publish:ready',
        ], reason: 'ready is published only after the load completes');
      },
    );

    test(
      'publishes a successful load with model identity and UTC time',
      () async {
        final ModelProvisioningStatusHolder holder =
            ModelProvisioningStatusHolder();
        addTearDown(holder.close);
        final IModelProvisioningReporter reporter = holder;
        final List<ModelProvisioningState> received =
            <ModelProvisioningState>[];
        final StreamSubscription<ModelProvisioningState> subscription = holder
            .watch()
            .listen(received.add);
        addTearDown(subscription.cancel);

        final String result = await runModelProvisioningRuntimeLoad<String>(
          reporter: reporter,
          modelId: 'gemma-3-1b-it',
          modelName: 'gemma-3-1b-it-Q4_K_M.gguf',
          mapFailure: _mapAs,
          now: _fixedNow,
          load: () async => 'service',
        );
        await pumpEventQueue();

        expect(result, 'service');
        expect(received.map((s) => s.phase), <ModelProvisioningPhase>[
          ModelProvisioningPhase.loadingRuntime,
          ModelProvisioningPhase.ready,
        ]);
        for (final ModelProvisioningState state in received) {
          expect(state.modelId, 'gemma-3-1b-it');
          expect(state.modelName, 'gemma-3-1b-it-Q4_K_M.gguf');
          expect(state.updatedAt, _updatedAt);
          expect(state.updatedAt.isUtc, isTrue);
          expect(state.failure, isNull);
          expect(state.totalBytes, isNull);
        }
        expect(holder.current, received.last);
      },
    );

    test('a failed load publishes failed and never publishes ready', () async {
      final Object expected = StateError('runtime failed to start');
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);
      final IModelProvisioningReporter reporter = holder;
      final List<ModelProvisioningState> received = <ModelProvisioningState>[];
      final StreamSubscription<ModelProvisioningState> subscription = holder
          .watch()
          .listen(received.add);
      addTearDown(subscription.cancel);

      await expectLater(
        runModelProvisioningRuntimeLoad<String>(
          reporter: reporter,
          modelId: 'gemma-3-1b-it',
          modelName: 'gemma-3-1b-it-Q4_K_M.gguf',
          mapFailure: _mapAs,
          now: _fixedNow,
          load: () async => throw expected,
        ),
        throwsA(same(expected)),
      );
      await pumpEventQueue();

      expect(received.map((s) => s.phase), <ModelProvisioningPhase>[
        ModelProvisioningPhase.loadingRuntime,
        ModelProvisioningPhase.failed,
      ]);
      expect(holder.current.phase, ModelProvisioningPhase.failed);
      expect(
        holder.current.failure!.code,
        ModelProvisioningFailureCode.runtimeLoadFailed,
      );
      expect(
        received.map((s) => s.phase),
        isNot(contains(ModelProvisioningPhase.ready)),
      );
    });

    test(
      'non-failed snapshots carry no failure and failed carries one',
      () async {
        final List<ModelProvisioningState> published =
            <ModelProvisioningState>[];
        final IModelProvisioningReporter reporter = _ListReporter(published);
        final Object expected = StateError('boom');

        await expectLater(
          runModelProvisioningRuntimeLoad<String>(
            reporter: reporter,
            mapFailure: _mapAs,
            now: _fixedNow,
            load: () async => throw expected,
          ),
          throwsA(same(expected)),
        );

        expect(published, hasLength(2));
        expect(published.first.phase, ModelProvisioningPhase.loadingRuntime);
        expect(published.first.failure, isNull);
        expect(published.last.phase, ModelProvisioningPhase.failed);
        expect(published.last.failure, isNotNull);
      },
    );

    test('uses the mapper result for the failed snapshot', () async {
      final List<ModelProvisioningState> published = <ModelProvisioningState>[];
      final IModelProvisioningReporter reporter = _ListReporter(published);

      await expectLater(
        runModelProvisioningRuntimeLoad<String>(
          reporter: reporter,
          mapFailure: (Object error) => ModelProvisioningFailure(
            code: ModelProvisioningFailureCode.unexpected,
            detail: 'mapped by the caller',
          ),
          now: _fixedNow,
          load: () async => throw StateError('boom'),
        ),
        throwsStateError,
      );

      expect(
        published.last.failure!.code,
        ModelProvisioningFailureCode.unexpected,
      );
      expect(published.last.failure!.detail, 'mapped by the caller');
    });
  });
}

final class _ListReporter implements IModelProvisioningReporter {
  _ListReporter(this.published);

  final List<ModelProvisioningState> published;

  @override
  void publish(ModelProvisioningState state) {
    published.add(state);
  }
}
