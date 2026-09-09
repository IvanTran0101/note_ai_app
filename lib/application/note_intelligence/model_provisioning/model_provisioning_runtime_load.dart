/// Runtime-load composition segment of the M4.5.a state boundary.
///
/// The composition root owns the concrete local-runtime start — calling
/// `startLlmWorkerClient` and constructing the summarization service — and
/// passes it as the [load] closure, so this library stays free of Flutter and
/// Infrastructure types. The helper fixes the only allowed publication order
/// around one runtime-load attempt:
///
/// 1. [ModelProvisioningPhase.loadingRuntime] is published before [load] runs;
/// 2. [ModelProvisioningPhase.ready] is published only after [load] completes
///    successfully;
/// 3. when [load] throws, [ModelProvisioningPhase.failed] is published with
///    the failure produced by [mapFailure], and the original error is
///    rethrown unchanged — a failed load never becomes ready.
///
/// The composition root reports [IModelProvisioningReporter] snapshots through
/// this helper so the ordering is owned once and stays fake-driven testable.
library;

import 'model_provisioning_boundary.dart';
import 'model_provisioning_failure.dart';
import 'model_provisioning_state.dart';

DateTime _utcNow() => DateTime.now().toUtc();

/// Runs one local-runtime [load] while publishing the runtime-load snapshots.
///
/// [load] may start the worker and/or construct the summarization service; it
/// must throw when the runtime cannot be made ready. [mapFailure] converts the
/// thrown infrastructure error into the Application failure vocabulary (e.g.
/// `LlmWorkerException` to [ModelProvisioningFailureCode.runtimeLoadFailed]);
/// it must never leak a stack trace, URL, or raw path into
/// [ModelProvisioningFailure.detail].
Future<T> runModelProvisioningRuntimeLoad<T>({
  required IModelProvisioningReporter reporter,
  required Future<T> Function() load,
  required ModelProvisioningFailure Function(Object error) mapFailure,
  String? modelId,
  String? modelName,
  DateTime Function() now = _utcNow,
}) async {
  _publishBestEffort(
    reporter,
    ModelProvisioningState(
      phase: ModelProvisioningPhase.loadingRuntime,
      modelId: modelId,
      modelName: modelName,
      updatedAt: now(),
    ),
  );

  final T result;
  try {
    result = await load();
  } on Object catch (error, stackTrace) {
    _publishBestEffort(
      reporter,
      ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        modelId: modelId,
        modelName: modelName,
        failure: mapFailure(error),
        updatedAt: now(),
      ),
    );
    Error.throwWithStackTrace(error, stackTrace);
  }

  _publishBestEffort(
    reporter,
    ModelProvisioningState(
      phase: ModelProvisioningPhase.ready,
      modelId: modelId,
      modelName: modelName,
      updatedAt: now(),
    ),
  );
  return result;
}

void _publishBestEffort(
  IModelProvisioningReporter reporter,
  ModelProvisioningState state,
) {
  try {
    reporter.publish(state);
  } on Object {
    // Status reporting is advisory and must not mask runtime startup or its
    // original failure.
  }
}
