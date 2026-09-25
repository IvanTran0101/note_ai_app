import 'package:flutter/material.dart';

import '../../application/note_intelligence/model_provisioning/model_provisioning_boundary.dart';
import '../../application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import '../../domain/note_intelligence/summary.dart';
import '../notes/model_provisioning_status_panel.dart';
import '../notes/notes_localizations.dart';

/// Signature for the summarizer injected into [LocalLlmDebugPage].
typedef SummarizeFunction = Future<Summary> Function(String content);

/// Loads a display-only model-readiness label for the diagnostics surface.
typedef LoadModelReadiness = Future<String?> Function();

/// Runs one authenticated remote sync smoke through Infrastructure.
typedef RunRemoteSyncSmoke = Future<String> Function();

/// Minimal debug screen proving the local-LLM summarization path end to end.
///
/// Accepts note text and shows loading / error / result states. It calls the
/// injected application callback — never FFI or the bridge package directly.
/// Widget tests can provide a fake callback.
class LocalLlmDebugPage extends StatefulWidget {
  const LocalLlmDebugPage({
    super.key,
    required this.summarize,
    this.loadModelReadiness,
    this.provisioningReader,
    this.onProvisioningCancel,
    this.runRemoteSyncSmoke,
  });

  final SummarizeFunction summarize;
  final LoadModelReadiness? loadModelReadiness;
  final IModelProvisioningReader? provisioningReader;
  final VoidCallback? onProvisioningCancel;
  final RunRemoteSyncSmoke? runRemoteSyncSmoke;

  @override
  State<LocalLlmDebugPage> createState() => _LocalLlmDebugPageState();
}

class _LocalLlmDebugPageState extends State<LocalLlmDebugPage> {
  final TextEditingController _noteController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _result;
  bool _remoteBusy = false;
  String? _remoteError;
  String? _remoteResult;
  Future<String?>? _readinessFuture;

  @override
  void initState() {
    super.initState();
    _refreshReadiness();
  }

  void _refreshReadiness() {
    final LoadModelReadiness? loadModelReadiness = widget.loadModelReadiness;
    if (loadModelReadiness != null) {
      _readinessFuture = loadModelReadiness();
    }
  }

  Future<void> _onSummarize() async {
    final SummarizeFunction summarize = widget.summarize;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final Summary summary = await summarize(_noteController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = summary.text;
        _refreshReadiness();
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      final ModelProvisioningPhase? provisioningPhase =
          widget.provisioningReader?.current.phase;
      setState(
        () => _error = provisioningPhase == ModelProvisioningPhase.cancelled
            ? null
            : error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onRemoteSyncSmoke() async {
    final RunRemoteSyncSmoke? run = widget.runRemoteSyncSmoke;
    if (run == null) {
      return;
    }
    setState(() {
      _remoteBusy = true;
      _remoteError = null;
      _remoteResult = null;
    });
    try {
      final String result = await run();
      if (!mounted) {
        return;
      }
      setState(() => _remoteResult = result);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _remoteError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _remoteBusy = false);
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NotesCopy copy = NotesCopy.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(copy.debugTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(copy.debugDescription),
            if (widget.provisioningReader != null) ...<Widget>[
              ModelProvisioningStatusPanel(
                reader: widget.provisioningReader!,
                onRetry: _onSummarize,
                onCancel: widget.onProvisioningCancel,
              ),
              const SizedBox(height: 12),
            ] else if (widget.loadModelReadiness != null) ...<Widget>[
              const SizedBox(height: 8),
              FutureBuilder<String?>(
                future: _readinessFuture,
                builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
                  final String label;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    label = '${copy.modelStatus}: ${copy.modelStatusLoading}';
                  } else if (snapshot.hasError) {
                    label =
                        '${copy.modelStatus}: ${copy.modelStatusUnavailable}';
                  } else {
                    label =
                        '${copy.modelStatus}: '
                        '${snapshot.data ?? copy.modelNotProvisioned}';
                  }
                  return Text(
                    label,
                    key: const ValueKey<String>('model-readiness-status'),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('debug-note-field'),
              controller: _noteController,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: copy.debugNoteLabel,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey<String>('debug-summarize'),
              onPressed: _busy ? null : _onSummarize,
              child: Text(copy.summarize),
            ),
            if (widget.runRemoteSyncSmoke != null) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey<String>('debug-remote-sync'),
                onPressed: _remoteBusy ? null : _onRemoteSyncSmoke,
                child: Text(
                  _remoteBusy ? copy.remoteSyncRunning : copy.remoteSyncSmoke,
                ),
              ),
              if (_remoteError != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    '${copy.remoteSyncError} $_remoteError',
                    key: const ValueKey<String>('debug-remote-sync-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_remoteResult != null)
                Card(
                  key: const ValueKey<String>('debug-remote-sync-result'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_remoteResult!),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (_busy) ...<Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  '${copy.debugError} $_error',
                  key: const ValueKey<String>('debug-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_result != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        copy.debugSummary,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(_result!),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
