import 'dart:async';

import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/material.dart';

import 'application/note_intelligence/note_summary_app_service.dart';
import 'domain/note_intelligence/summary.dart';
import 'infrastructure/ai/llm_worker_client.dart';
import 'infrastructure/ai/model_catalog.dart';
import 'infrastructure/ai/model_downloader.dart';
import 'infrastructure/ai/model_integrity_verifier.dart';
import 'infrastructure/ai/model_manager.dart';
import 'infrastructure/ai/model_provisioning_contract.dart';
import 'infrastructure/ai/model_selection.dart';
import 'infrastructure/ai/model_storage.dart';
import 'infrastructure/device/device_info_plus_hardware_detection.dart';
import 'infrastructure/note_intelligence/local_summarization_service.dart';
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
  late final IModelStorage _modelStorage = createModelStorage(
    overrideModelPath: _modelPath.trim().isEmpty ? null : _modelPath.trim(),
  );
  late final ModelManager _modelManager = ModelManager(
    hardwareDetectionService: createHardwareDetectionService(),
    modelCatalog: const ModelCatalog(),
    modelSelectionPolicy: const ModelSelectionPolicy(),
    modelStorage: _modelStorage,
    modelDownloader: createModelDownloader(),
    integrityVerifier: createModelIntegrityVerifier(),
  );
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
    if (_disposed) {
      throw StateError('NoteFlowApp was disposed while preparing local AI');
    }

    final String modelPath;
    if (_usesAutomaticModelProvisioning) {
      final PreparedModel preparedModel = await _modelManager
          .ensureModelReady();
      modelPath = preparedModel.path;
    } else {
      // Preserve the existing explicit-path/macOS/Web fallback. Automatic
      // provisioning is only enabled for mobile targets without an explicit
      // LOCAL_LLM_MODEL_PATH override.
      modelPath = await _modelStorage.resolveModelPath();
    }

    if (_disposed) {
      throw StateError('NoteFlowApp was disposed while preparing local AI');
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

  bool get _usesAutomaticModelProvisioning {
    if (kIsWeb || _modelPath.trim().isNotEmpty) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
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
