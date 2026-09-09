/// Application-facing ports for observing and reporting model provisioning
/// (M4.5.a).
///
/// This library separates the read side from the write side of the
/// provisioning state boundary:
///
/// * [IModelProvisioningReader] is consumed by Presentation (and diagnostics)
///   to render provisioning state. Widgets depend on this port only, never on
///   `ModelManager`, `ModelDescriptor`, `AiReadinessSnapshot`, or `dart:io`.
/// * [IModelProvisioningReporter] is implemented by the Infrastructure-side
///   reporting adapter (a later slice) and invoked by the composition root to
///   publish validated snapshots.
///
/// Keeping the two responsibilities on separate interfaces prevents
/// Presentation from writing state and keeps the reader testable with an
/// in-memory fake. The library is deliberately free of Flutter and
/// Infrastructure types; only `dart:async` streams cross this boundary.
library;

import 'dart:async';

import 'model_provisioning_state.dart';

/// Read side of the provisioning state boundary.
///
/// [current] is the latest snapshot for synchronous rendering; [watch] emits
/// each subsequent snapshot as it is published. Implementations should back
/// [watch] with a broadcast stream that does not complete between provisioning
/// attempts, and must keep [current] equal to the last snapshot delivered to
/// [watch].
abstract interface class IModelProvisioningReader {
  /// The latest provisioning snapshot.
  ///
  /// Reading [current] before listening to [watch] guarantees a Presentation
  /// consumer never misses the state that changed before it subscribed.
  ModelProvisioningState get current;

  /// Emits every snapshot published after subscription.
  ///
  /// The stream never replays [current]; consumers combine it with [current]
  /// for a complete picture.
  Stream<ModelProvisioningState> watch();
}

/// Write side of the provisioning state boundary.
///
/// [publish] is the only write operation: it hands one validated, immutable
/// [ModelProvisioningState] snapshot to every current reader. Progress
/// invariants are already enforced by the snapshot constructor, so an
/// implementation does not re-validate.
abstract interface class IModelProvisioningReporter {
  /// Publishes [state] as the new current snapshot.
  ///
  /// Implementations must make [state] observable through
  /// [IModelProvisioningReader.current] and emit it on
  /// [IModelProvisioningReader.watch] without modifying it.
  void publish(ModelProvisioningState state);
}
