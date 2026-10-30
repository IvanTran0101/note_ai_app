import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'notes_localizations.dart';

/// A compact, app-wide view of active model preparation and recovery.
final class ModelPreparationBanner extends StatelessWidget {
  const ModelPreparationBanner({
    super.key,
    required this.reader,
    required this.onCancel,
    required this.onRetry,
  });

  final IModelProvisioningReader reader;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  /// Whether the banner reserves space above the app's navigation content.
  static bool isVisible(ModelProvisioningPhase phase) =>
      phase != ModelProvisioningPhase.idle &&
      phase != ModelProvisioningPhase.ready &&
      phase != ModelProvisioningPhase.awaitingDownloadApproval;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ModelProvisioningState>(
      stream: reader.watch(),
      initialData: reader.current,
      builder: (context, snapshot) {
        final state = snapshot.data ?? reader.current;
        if (!isVisible(state.phase)) {
          return const SizedBox.shrink();
        }
        final copy = NotesCopy.of(context);
        final failed = state.phase == ModelProvisioningPhase.failed;
        final cancelled = state.phase == ModelProvisioningPhase.cancelled;
        final canRetry =
            cancelled || (failed && state.failure?.retryable == true);
        final String? detail = failed && state.failure != null
            ? copy.provisioningFailure(state.failure!.code)
            : state.phase == ModelProvisioningPhase.downloading &&
                  state.totalBytes != null &&
                  state.totalBytes! > 0
            ? '${(state.downloadedBytes * 100 / state.totalBytes!).clamp(0, 100).round()}%'
            : null;
        final canCancel = switch (state.phase) {
          ModelProvisioningPhase.detectingDevice ||
          ModelProvisioningPhase.selectingModel ||
          ModelProvisioningPhase.checkingExistingModel ||
          ModelProvisioningPhase.downloading ||
          ModelProvisioningPhase.verifying => true,
          _ => false,
        };
        final double? progress =
            state.phase == ModelProvisioningPhase.downloading &&
                state.totalBytes != null &&
                state.totalBytes! > 0
            ? (state.downloadedBytes / state.totalBytes!).clamp(0.0, 1.0)
            : null;
        return Material(
          color: failed
              ? Theme.of(context).colorScheme.errorContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Icon(
                          failed
                              ? Icons.error_outline
                              : cancelled
                              ? Icons.pause_circle_outline
                              : Icons.auto_awesome_outlined,
                          size: 20,
                          color: failed
                              ? Theme.of(context).colorScheme.onErrorContainer
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                copy.provisioningPhase(state.phase),
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: failed
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onErrorContainer
                                          : null,
                                    ),
                              ),
                              if (detail != null)
                                Text(
                                  detail,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: failed
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onErrorContainer
                                            : null,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (canCancel)
                        TextButton(
                          onPressed: onCancel,
                          child: Text(
                            state.phase == ModelProvisioningPhase.downloading
                                ? copy.provisioningCancel
                                : Localizations.localeOf(context)
                                          .languageCode ==
                                      'vi'
                                ? 'Hủy chuẩn bị'
                                : 'Cancel preparation',
                          ),
                        ),
                      if (canRetry)
                        TextButton(
                          onPressed: onRetry,
                          child: Text(copy.provisioningRetry),
                        ),
                    ],
                  ),
                  if (!failed && !cancelled)
                    LinearProgressIndicator(value: progress),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
