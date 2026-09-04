import 'package:flutter/material.dart';

import '../../domain/note_intelligence/summary.dart';

/// Signature for the summarizer injected into [LocalLlmDebugPage].
typedef SummarizeFunction = Future<Summary> Function(String content);

/// Loads a display-only model-readiness label for the diagnostics surface.
typedef LoadModelReadiness = Future<String?> Function();

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
  });

  final SummarizeFunction summarize;
  final LoadModelReadiness? loadModelReadiness;

  @override
  State<LocalLlmDebugPage> createState() => _LocalLlmDebugPageState();
}

class _LocalLlmDebugPageState extends State<LocalLlmDebugPage> {
  final TextEditingController _noteController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _result;
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
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteFlow · Local LLM Debug'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'On-device summarization proof. Native platforms resolve the '
              'model from app-private storage; macOS Debug also accepts the '
              'LOCAL_LLM_MODEL_PATH override.',
            ),
            if (widget.loadModelReadiness != null) ...<Widget>[
              const SizedBox(height: 8),
              FutureBuilder<String?>(
                future: _readinessFuture,
                builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
                  final String label;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    label = 'Model status: loading…';
                  } else if (snapshot.hasError) {
                    label = 'Model status: unavailable';
                  } else {
                    label =
                        'Model status: ${snapshot.data ?? 'not provisioned'}';
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
              controller: _noteController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Paste note content here…',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _onSummarize,
              child: const Text('Summarize'),
            ),
            const SizedBox(height: 16),
            if (_busy) ...<Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            if (_error != null)
              Text(
                'Error: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_result != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_result!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
