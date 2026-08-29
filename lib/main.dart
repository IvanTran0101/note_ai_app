import 'dart:async';

import 'package:flutter/material.dart';

import 'application/ai/note_summary_app_service.dart';
import 'domain/note_intelligence/summary.dart';
import 'infrastructure/ai/llm_worker_client.dart';
import 'infrastructure/ai/local_summarization_service.dart';
import 'presentation/debug/local_llm_debug_page.dart';

void main() {
  runApp(const NoteFlowApp());
}

/// Root composition for the local-LLM summarization proof.
///
/// Infrastructure is assembled here, while the Application service only sees
/// its Domain summarization contract and the debug page only receives a
/// summarization function.
class NoteFlowApp extends StatefulWidget {
  const NoteFlowApp({super.key});

  @override
  State<NoteFlowApp> createState() => _NoteFlowAppState();
}

class _NoteFlowAppState extends State<NoteFlowApp> {
  static const String _modelPath = String.fromEnvironment(
    'LOCAL_LLM_MODEL_PATH',
  );

  LlmWorkerClient? _workerClient;
  NoteSummaryAppService? _appService;
  Future<NoteSummaryAppService>? _serviceStart;
  bool _disposed = false;

  Future<Summary> _summarize(String content) async {
    final NoteSummaryAppService service = await _ensureService();
    return service.summarize(content);
  }

  Future<NoteSummaryAppService> _ensureService() async {
    final NoteSummaryAppService? existing = _appService;
    if (existing != null) {
      return existing;
    }

    final Future<NoteSummaryAppService>? pending = _serviceStart;
    if (pending != null) {
      return pending;
    }

    final Future<NoteSummaryAppService> start = _startService();
    _serviceStart = start;
    try {
      final NoteSummaryAppService service = await start;
      _appService ??= service;
      return service;
    } finally {
      if (identical(_serviceStart, start)) {
        _serviceStart = null;
      }
    }
  }

  Future<NoteSummaryAppService> _startService() async {
    final String modelPath = _modelPath.trim();
    if (modelPath.isEmpty) {
      throw StateError(
        'LOCAL_LLM_MODEL_PATH is not set. Pass '
        '--dart-define=LOCAL_LLM_MODEL_PATH=/path/to/model.gguf.',
      );
    }

    final LlmWorkerClient client = await startLlmWorkerClient(
      modelPath: modelPath,
    );
    if (_disposed) {
      await client.dispose();
      throw StateError('NoteFlowApp was disposed while starting local AI');
    }

    try {
      final LocalSummarizationService infrastructureService =
          LocalSummarizationService(workerClient: client);
      _workerClient = client;
      return NoteSummaryAppService(summarizationService: infrastructureService);
    } on Object {
      await client.dispose();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteFlow',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: LocalLlmDebugPage(summarize: _summarize),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    final LlmWorkerClient? client = _workerClient;
    if (client != null) {
      unawaited(client.dispose());
    }
    super.dispose();
  }
}
