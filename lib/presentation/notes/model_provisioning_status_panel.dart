import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'notes_localizations.dart';

/// Displays the live model-provisioning state without coupling Presentation to
/// ModelManager, storage, device plugins, or native runtime types.
final class ModelProvisioningStatusPanel extends StatelessWidget {
  const ModelProvisioningStatusPanel({
    super.key,
    required this.reader,
    this.onRetry,
  });

  final IModelProvisioningReader reader;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ModelProvisioningState>(
      stream: reader.watch(),
      initialData: reader.current,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<ModelProvisioningState> snapshot,
          ) {
            return _buildState(context, snapshot.data ?? reader.current);
          },
    );
  }

  Widget _buildState(BuildContext context, ModelProvisioningState state) {
    if (state.phase == ModelProvisioningPhase.idle ||
        state.phase == ModelProvisioningPhase.ready) {
      return const SizedBox.shrink();
    }

    final NotesCopy copy = NotesCopy.of(context);
    final ThemeData theme = Theme.of(context);
    final bool failed = state.phase == ModelProvisioningPhase.failed;
    final String phaseLabel = copy.provisioningPhase(state.phase);

    return Semantics(
      container: true,
      liveRegion: true,
      label: '${copy.provisioningStatus}: $phaseLabel',
      child: Card(
        key: const ValueKey<String>('model-provisioning-status'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                phaseLabel,
                key: const ValueKey<String>('model-provisioning-phase'),
                style: theme.textTheme.titleSmall,
              ),
              if (state.modelName != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '${copy.provisioningModel}: ${state.modelName}',
                  key: const ValueKey<String>('model-provisioning-model'),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (!failed) ...<Widget>[
                const SizedBox(height: 10),
                _progressIndicator(state),
              ],
              if (state.phase ==
                  ModelProvisioningPhase.downloading) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  copy.provisioningDownloadHint,
                  key: const ValueKey<String>('model-provisioning-hint'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _progressText(copy, state),
                  key: const ValueKey<String>('model-provisioning-bytes'),
                  semanticsLabel: _progressText(copy, state),
                ),
              ],
              if (failed) _failureContent(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progressIndicator(ModelProvisioningState state) {
    double? value;
    if (state.phase == ModelProvisioningPhase.downloading &&
        state.totalBytes != null &&
        state.totalBytes! > 0) {
      value = (state.downloadedBytes / state.totalBytes!).clamp(0.0, 1.0);
    }
    return LinearProgressIndicator(
      key: const ValueKey<String>('model-provisioning-progress'),
      value: value,
    );
  }

  String _progressText(NotesCopy copy, ModelProvisioningState state) {
    final String downloaded = _formatBytes(state.downloadedBytes);
    final int? totalBytes = state.totalBytes;
    if (totalBytes == null) {
      return '${copy.provisioningDownloaded} $downloaded';
    }
    return copy.provisioningBytes(downloaded, _formatBytes(totalBytes));
  }

  Widget _failureContent(BuildContext context, ModelProvisioningState state) {
    final NotesCopy copy = NotesCopy.of(context);
    final ThemeData theme = Theme.of(context);
    final failure = state.failure;
    if (failure == null) {
      return Text(
        copy.provisioningNoDetail,
        key: const ValueKey<String>('model-provisioning-error'),
        style: TextStyle(color: theme.colorScheme.error),
      );
    }

    final List<Widget> children = <Widget>[
      const SizedBox(height: 8),
      Text(
        copy.provisioningFailure(failure.code),
        key: const ValueKey<String>('model-provisioning-error'),
        style: TextStyle(color: theme.colorScheme.error),
      ),
    ];
    final String? detail = failure.detail?.trim();
    if (detail != null && detail.isNotEmpty) {
      children.addAll(<Widget>[
        const SizedBox(height: 4),
        Text(detail, key: const ValueKey<String>('model-provisioning-detail')),
      ]);
    }
    if (failure.retryable && onRetry != null) {
      children.addAll(<Widget>[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            key: const ValueKey<String>('model-provisioning-retry'),
            onPressed: onRetry,
            child: Text(copy.provisioningRetry),
          ),
        ),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final double kibibytes = bytes / 1024;
    if (kibibytes < 1024) {
      return '${kibibytes.toStringAsFixed(1)} KB';
    }
    final double mebibytes = kibibytes / 1024;
    if (mebibytes < 1024) {
      return '${mebibytes.toStringAsFixed(1)} MB';
    }
    return '${(mebibytes / 1024).toStringAsFixed(1)} GB';
  }
}
