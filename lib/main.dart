import 'dart:async';

import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/note_intelligence/model_provisioning/model_provisioning_runtime_load.dart';
import 'application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';
import 'application/note_intelligence/note_summary_app_service.dart';
import 'application/notes/note_application.dart';
import 'application/dashboard/get_dashboard_overview.dart';
import 'domain/note_intelligence/summary.dart';
import 'domain/notes/note_repository.dart';
import 'infrastructure/ai/llm_worker_client.dart';
import 'infrastructure/ai/model_catalog.dart';
import 'infrastructure/ai/model_downloader.dart';
import 'infrastructure/ai/model_integrity_verifier.dart';
import 'infrastructure/ai/model_manager.dart';
import 'infrastructure/ai/model_provisioning_contract.dart';
import 'infrastructure/ai/model_selection.dart';
import 'infrastructure/ai/model_storage.dart';
import 'infrastructure/configuration/ai_configuration.dart';
import 'infrastructure/configuration/ai_configuration_store.dart';
import 'infrastructure/device/device_info_plus_hardware_detection.dart';
import 'infrastructure/note_intelligence/local_summarization_service.dart';
import 'infrastructure/notes/note_repository.dart' as note_infrastructure;
import 'presentation/debug/local_llm_debug_page.dart';
import 'presentation/dashboard/dashboard_controller.dart';
import 'presentation/dashboard/dashboard_localizations.dart';
import 'presentation/dashboard/dashboard_page.dart';
import 'presentation/notes/note_detail_localizations.dart';
import 'presentation/notes/note_detail_page.dart';
import 'presentation/notes/note_detail_route_result.dart';
import 'presentation/notes/notes_localizations.dart';
import 'presentation/notes/notes_application_controller.dart';
import 'presentation/notes/notes_theme_tokens.dart';
import 'presentation/notes/notes_workspace_page.dart';
import 'presentation/workspace/workspace_localizations.dart';
import 'presentation/workspace/workspace_shell.dart';

const String _noteFlowFontFamily = 'Inter';
const List<String> _noteFlowFontFallback = <String>[
  'Roboto',
  'Arial',
  'monospace',
];
const Color _noteFlowSeedColor = Color(0xFF5B4FA6);

enum _NoteFlowLanguageChoice { system, vietnamese, english }

ThemeData _buildNoteFlowTheme(Brightness brightness) {
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    seedColor: _noteFlowSeedColor,
    brightness: brightness,
  );
  final BorderRadius fieldRadius = BorderRadius.circular(12.0);
  final BorderSide fieldBorder = BorderSide(color: colorScheme.outline);
  final BorderSide focusedFieldBorder = BorderSide(
    color: colorScheme.primary,
    width: 2.0,
  );

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    useMaterial3: true,
    extensions: <ThemeExtension<dynamic>>[
      NoteFlowSemanticColors.fromColorScheme(colorScheme),
    ],
    fontFamily: _noteFlowFontFamily,
    fontFamilyFallback: _noteFlowFontFallback,
    appBarTheme: AppBarThemeData(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0.0,
      scrolledUnderElevation: 2.0,
      surfaceTintColor: colorScheme.surfaceTint,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surfaceContainerLow,
      surfaceTintColor: colorScheme.surfaceTint,
      elevation: 0.0,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 14.0,
      ),
      border: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: fieldBorder,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: fieldBorder,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: focusedFieldBorder,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: colorScheme.error, width: 2.0),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(48.0, 48.0),
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48.0, 48.0),
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48.0, 48.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.surfaceContainerHighest,
      circularTrackColor: colorScheme.surfaceContainerHighest,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      actionTextColor: colorScheme.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
      insetPadding: const EdgeInsets.all(16.0),
    ),
  );
}

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
  static const String _localOwnerId = 'local-user';

  ThemeMode _themeMode = ThemeMode.system;
  _NoteFlowLanguageChoice _languageChoice = _NoteFlowLanguageChoice.system;
  LlmWorkerClient? _workerClient;
  NoteSummaryAppService? _appService;
  Future<NoteSummaryAppService>? _serviceStart;
  int _noteIdSequence = 0;
  late final AiConfiguration _aiConfiguration =
      AiConfiguration.fromEnvironment();
  late final AiConfigurationStore _aiConfigurationStore =
      createAiConfigurationStore();
  late final INoteRepository _noteRepository = note_infrastructure
      .createNoteRepository();
  late final NoteApplicationService _noteApplicationService =
      NoteApplicationService(
        noteRepository: _noteRepository,
        ownerId: _localOwnerId,
        generateId: _generateNoteId,
        now: _nowUtc,
        summarizeContent: _summarize,
      );
  late final NotesApplicationController _notesController =
      NoteApplicationServiceController(_noteApplicationService);
  late final DashboardController _dashboardController = DashboardController(
    query: GetDashboardOverview(
      noteRepository: _noteRepository,
      ownerId: _localOwnerId,
    ),
    recentLimit: 20,
  );
  final GlobalKey<WorkspaceShellState> _workspaceShellKey =
      GlobalKey<WorkspaceShellState>();
  late final IModelStorage _modelStorage = createModelStorage(
    overrideModelPath: _aiConfiguration.modelPathOverride,
  );
  // Shared provisioning state holder (M4.5.a). ModelManager and the
  // runtime-load composition publish into it; a later Presentation slice
  // subscribes through the same instance. UI is not wired in this slice.
  late final ModelProvisioningStatusHolder _modelProvisioningStatus =
      ModelProvisioningStatusHolder();
  late final ModelManager _modelManager = ModelManager(
    hardwareDetectionService: createHardwareDetectionService(),
    modelCatalog: const ModelCatalog(),
    modelSelectionPolicy: const ModelSelectionPolicy(),
    modelStorage: _modelStorage,
    modelDownloader: createModelDownloader(
      maxRedirects: _aiConfiguration.maxRedirects,
      requestTimeout: _aiConfiguration.downloadTimeout,
    ),
    integrityVerifier: createModelIntegrityVerifier(),
    aiConfigurationStore: _aiConfigurationStore,
    modelProvisioningReporter: _modelProvisioningStatus,
  );
  bool _disposed = false;

  Future<Summary> _summarize(String content) async {
    final NoteSummaryAppService service = await _ensureService();
    return service.summarize(content);
  }

  void _cancelModelProvisioning() {
    _modelManager.cancelProvisioning();
  }

  Future<NoteDetailRouteResult?> _openNoteDetail(
    BuildContext context,
    NoteDto? note,
  ) async {
    return Navigator.of(context).push<NoteDetailRouteResult>(
      MaterialPageRoute<NoteDetailRouteResult>(
        builder: (_) => NoteDetailPage(
          notesController: _notesController,
          note: note,
          provisioningReader: _modelProvisioningStatus,
          onProvisioningCancel: _cancelModelProvisioning,
        ),
      ),
    );
  }

  String _generateNoteId() {
    _noteIdSequence++;
    return 'note-${DateTime.now().microsecondsSinceEpoch}-$_noteIdSequence';
  }

  DateTime _nowUtc() => DateTime.now().toUtc();

  Future<String?> _loadModelReadiness() async {
    try {
      final AiReadinessSnapshot? snapshot = await _aiConfigurationStore.read();
      if (snapshot == null) {
        return null;
      }
      return switch (snapshot.runtimeStatus) {
        RuntimeReadinessStatus.loading =>
          'runtime-loading · ${snapshot.modelId}',
        RuntimeReadinessStatus.failed => 'runtime-failed · ${snapshot.modelId}',
        RuntimeReadinessStatus.ready => 'ready · ${snapshot.modelId}',
        RuntimeReadinessStatus.unknown => switch (snapshot.status) {
          ModelReadinessStatus.preparing => 'preparing · ${snapshot.modelId}',
          ModelReadinessStatus.ready => 'ready · ${snapshot.modelId}',
          ModelReadinessStatus.failed => 'failed · ${snapshot.modelId}',
          ModelReadinessStatus.cancelled => 'cancelled · ${snapshot.modelId}',
        },
      };
    } on Object {
      // Diagnostics must remain usable when advisory state is unavailable or
      // unsupported on the current platform.
      return 'unavailable';
    }
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
    final int contextSize;
    final int maxOutputTokens;
    PreparedModel? preparedModel;
    String? modelId;
    String? modelName;
    if (_usesAutomaticModelProvisioning) {
      preparedModel = await _modelManager.ensureModelReady();
      modelPath = preparedModel.path;
      contextSize = preparedModel.model.contextSize;
      maxOutputTokens = preparedModel.model.maxOutputTokens;
      modelId = preparedModel.model.id;
      modelName = preparedModel.model.fileName;
    } else {
      // Preserve the existing explicit-path/macOS/Web fallback. Automatic
      // provisioning is only enabled for mobile targets without an explicit
      // LOCAL_LLM_MODEL_PATH override.
      modelPath = await _modelStorage.resolveModelPath();
      contextSize = _aiConfiguration.defaultContextSize;
      maxOutputTokens = _aiConfiguration.defaultMaxOutputTokens;
    }

    if (_disposed) {
      throw StateError('NoteFlowApp was disposed while preparing local AI');
    }

    if (preparedModel != null) {
      await _persistRuntimeReadiness(
        preparedModel: preparedModel,
        status: RuntimeReadinessStatus.loading,
      );
    }

    // Publish loadingRuntime before the worker starts, ready only after the
    // summarization service is constructed, and failed (runtimeLoadFailed for
    // worker failures) when startup throws. ModelManager never publishes these
    // runtime phases itself.
    try {
      final NoteSummaryAppService service =
          await runModelProvisioningRuntimeLoad<NoteSummaryAppService>(
            reporter: _modelProvisioningStatus,
            modelId: modelId,
            modelName: modelName,
            mapFailure: mapModelProvisioningFailure,
            load: () async {
              final LlmWorkerClient client = await startLlmWorkerClient(
                modelPath: modelPath,
                contextSize: contextSize,
                threads: _aiConfiguration.workerThreads,
              );
              if (_disposed) {
                await client.dispose();
                throw StateError(
                  'NoteFlowApp was disposed while starting local AI',
                );
              }

              try {
                final LocalSummarizationService infrastructureService =
                    LocalSummarizationService(
                      workerClient: client,
                      maxTokens: maxOutputTokens,
                      contextSize: contextSize,
                    );
                _workerClient = client;
                return NoteSummaryAppService(
                  summarizationService: infrastructureService,
                );
              } on Object {
                await client.dispose();
                rethrow;
              }
            },
          );
      if (preparedModel != null) {
        await _persistRuntimeReadiness(
          preparedModel: preparedModel,
          status: RuntimeReadinessStatus.ready,
        );
      }
      return service;
    } on Object catch (error, stackTrace) {
      if (preparedModel != null) {
        await _persistRuntimeReadiness(
          preparedModel: preparedModel,
          status: RuntimeReadinessStatus.failed,
          runtimeError: mapModelProvisioningFailure(error).detail,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _persistRuntimeReadiness({
    required PreparedModel preparedModel,
    required RuntimeReadinessStatus status,
    String? runtimeError,
  }) async {
    try {
      final AiReadinessSnapshot? snapshot = await _aiConfigurationStore.read();
      if (snapshot == null ||
          snapshot.modelId != preparedModel.model.id ||
          snapshot.modelVersion != preparedModel.model.version ||
          snapshot.modelSha256 != preparedModel.model.sha256) {
        return;
      }
      await _aiConfigurationStore.save(
        snapshot.withRuntimeStatus(
          status,
          runtimeError: runtimeError,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on Object {
      // Runtime readiness is advisory bookkeeping. A store failure must never
      // mask a usable runtime or its original startup failure.
    }
  }

  bool get _usesAutomaticModelProvisioning {
    if (kIsWeb || _aiConfiguration.modelPathOverride != null) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  Locale? get _selectedLocale {
    return switch (_languageChoice) {
      _NoteFlowLanguageChoice.system => null,
      _NoteFlowLanguageChoice.vietnamese => const Locale('vi'),
      _NoteFlowLanguageChoice.english => const Locale('en'),
    };
  }

  Future<void> _showAppearanceSettings(BuildContext context) async {
    ThemeMode selectedTheme = _themeMode;
    _NoteFlowLanguageChoice selectedLanguage = _languageChoice;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'Appearance & language / Giao diện & ngôn ngữ',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<ThemeMode>(
                      key: ValueKey<ThemeMode>(selectedTheme),
                      initialValue: selectedTheme,
                      decoration: const InputDecoration(
                        labelText: 'Theme / Giao diện',
                        border: OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<ThemeMode>>[
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('System / Theo hệ thống'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('Light / Sáng'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Dark / Tối'),
                        ),
                      ],
                      onChanged: (ThemeMode? value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedTheme = value);
                        setState(() => _themeMode = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<_NoteFlowLanguageChoice>(
                      key: ValueKey<_NoteFlowLanguageChoice>(selectedLanguage),
                      initialValue: selectedLanguage,
                      decoration: const InputDecoration(
                        labelText: 'Language / Ngôn ngữ',
                        border: OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<_NoteFlowLanguageChoice>>[
                        DropdownMenuItem(
                          value: _NoteFlowLanguageChoice.system,
                          child: Text('System / Theo hệ thống'),
                        ),
                        DropdownMenuItem(
                          value: _NoteFlowLanguageChoice.vietnamese,
                          child: Text('Tiếng Việt'),
                        ),
                        DropdownMenuItem(
                          value: _NoteFlowLanguageChoice.english,
                          child: Text('English'),
                        ),
                      ],
                      onChanged: (_NoteFlowLanguageChoice? value) {
                        if (value == null) {
                          return;
                        }
                        setSheetState(() => selectedLanguage = value);
                        setState(() => _languageChoice = value);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoteFlow',
      theme: _buildNoteFlowTheme(Brightness.light),
      darkTheme: _buildNoteFlowTheme(Brightness.dark),
      themeMode: _themeMode,
      locale: _selectedLocale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        NotesCopy.delegate,
        NoteDetailCopy.delegate,
        DashboardCopy.delegate,
        WorkspaceCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      home: Builder(
        builder: (BuildContext context) {
          return WorkspaceShell(
            key: _workspaceShellKey,
            dashboard: DashboardPage(
              dashboardController: _dashboardController,
              notesController: _notesController,
              onOpenNote: (NoteDto note) => _openNoteDetail(context, note),
              onCreateNote: () => _openNoteDetail(context, null),
              onOpenSettings: () => _showAppearanceSettings(context),
              onOpenDiagnostics: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalLlmDebugPage(
                      summarize: _summarize,
                      loadModelReadiness: _loadModelReadiness,
                      provisioningReader: _modelProvisioningStatus,
                      onProvisioningCancel: _cancelModelProvisioning,
                    ),
                  ),
                );
              },
            ),
            notes: NotesWorkspacePage(
              applicationService: _noteApplicationService,
              provisioningReader: _modelProvisioningStatus,
              onProvisioningCancel: _cancelModelProvisioning,
              onOpenSettings: () => _showAppearanceSettings(context),
              onOpenDiagnostics: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LocalLlmDebugPage(
                      summarize: _summarize,
                      loadModelReadiness: _loadModelReadiness,
                      provisioningReader: _modelProvisioningStatus,
                      onProvisioningCancel: _cancelModelProvisioning,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
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
