/// Compact in-memory provisioning status holder (M4.5.a).
///
/// The composition root instantiates one [ModelProvisioningStatusHolder] and
/// implements both sides of the provisioning boundary with it: the holder is
/// the [IModelProvisioningReporter] handed to the Infrastructure producer
/// (e.g. `ModelManager`) and to the runtime-load composition, and the
/// [IModelProvisioningReader] a later Presentation consumer subscribes to.
///
/// The holder keeps [IModelProvisioningReader.current] equal to the most
/// recently published snapshot and broadcasts every published snapshot to live
/// [IModelProvisioningReader.watch] listeners without replaying history and
/// without mutating the published value. It is deliberately framework-free:
/// only `dart:async` and the model_provisioning contracts cross this library.
library;

import 'dart:async';

import 'model_provisioning_boundary.dart';
import 'model_provisioning_state.dart';

/// Default snapshot used before the first publish: idle, no model, no bytes.
ModelProvisioningState _initialIdle() {
  return ModelProvisioningState(updatedAt: DateTime.now().toUtc());
}

/// In-memory [IModelProvisioningReader] + [IModelProvisioningReporter].
final class ModelProvisioningStatusHolder
    implements IModelProvisioningReader, IModelProvisioningReporter {
  /// Creates a holder starting from [initial] (defaults to a fresh idle
  /// snapshot observed now in UTC).
  ModelProvisioningStatusHolder({ModelProvisioningState? initial})
    : _current = initial ?? _initialIdle(),
      _controller = StreamController<ModelProvisioningState>.broadcast();

  /// The latest snapshot, available before any [watch] subscription.
  ModelProvisioningState _current;

  /// Broadcast channel for snapshots published after subscription.
  final StreamController<ModelProvisioningState> _controller;

  @override
  ModelProvisioningState get current => _current;

  @override
  Stream<ModelProvisioningState> watch() => _controller.stream;

  @override
  void publish(ModelProvisioningState state) {
    // Publish the caller's immutable snapshot unchanged; never copy or mutate.
    _current = state;
    _controller.add(state);
  }

  /// Stops the broadcast stream. Publishing after [close] is a no-op error
  /// guarded by the stream controller.
  Future<void> close() => _controller.close();
}
