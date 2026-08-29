import 'package:flutter/material.dart';

import '../../domain/note_intelligence/summary.dart';

/// Signature for the summarizer injected into [LocalLlmDebugPage].
typedef SummarizeFunction = Future<Summary> Function(String content);

/// Minimal debug screen proving the local-LLM summarization path end to end.
///
/// Accepts note text and shows loading / error / result states. It calls the
/// injected application callback — never FFI or the bridge package directly.
/// Widget tests can provide a fake callback.
class LocalLlmDebugPage extends StatefulWidget {
  const LocalLlmDebugPage({super.key, required this.summarize});

  final SummarizeFunction summarize;

  @override
  State<LocalLlmDebugPage> createState() => _LocalLlmDebugPageState();
}

class _LocalLlmDebugPageState extends State<LocalLlmDebugPage> {
  final TextEditingController _noteController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _result;

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
      setState(() => _result = summary.text);
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
              'On-device summarization proof (macOS debug). The model path '
              'comes from --dart-define=LOCAL_LLM_MODEL_PATH.',
            ),
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
