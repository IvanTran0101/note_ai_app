import 'application/users/profile_app_service.dart';

import 'application/users/profile_snapshot.dart';
import 'domain/users/profile_failure.dart';
import 'infrastructure/users/http_user_profile_repository.dart';
import 'infrastructure/users/http_profile_avatar_gateway.dart';
import 'infrastructure/users/profile_avatar_picker.dart';
import 'presentation/profile/profile_page.dart';
import 'application/labels/label_application.dart';
import 'presentation/labels/label_catalog_scope.dart';
import 'presentation/common/note_flow_system_bars.dart';
import 'infrastructure/security/note_security_runtime.dart';
import 'infrastructure/security/encrypted_sync_store.dart';
import 'infrastructure/attachments/attachment_runtime.dart';
import 'infrastructure/attachments/flutter_attachment_picker.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'amplify_outputs.dart' as generated_amplify;
import 'application/auth/authentication_app_service.dart';
import 'application/auth/auth_models.dart';
import 'application/auth/current_user_session.dart';
import 'application/sync/local_sync_store.dart';
import 'application/sync/sync_conflict_resolver.dart';
import 'application/sync/account_realtime_service.dart';
import 'infrastructure/sync/appsync_revision_source.dart';
import 'infrastructure/sync/cognito_id_token_provider.dart';
import 'application/note_intelligence/model_provisioning/model_provisioning_runtime_load.dart';
import 'application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';
import 'application/note_intelligence/summary_run_context.dart';
import 'application/note_intelligence/summary_consent_app_service.dart';
import 'application/note_intelligence/note_summary_app_service.dart';
import 'application/note_intelligence/rag_app_service.dart';
import 'application/note_intelligence/rag_state.dart';
import 'application/notes/note_application.dart';
import 'application/notes/note_sharing_app_service.dart';
import 'infrastructure/notes/http_share_gateway.dart';
import 'infrastructure/sync/cognito_access_token_provider.dart';
import 'application/notes/local_note_vault.dart';
import 'application/dashboard/get_dashboard_overview.dart';
import 'domain/auth/auth_identity.dart';
import 'domain/note_intelligence/summary.dart';
import 'domain/note_intelligence/i_rag_gateway.dart';
import 'domain/note_intelligence/rag_models.dart';
import 'domain/notes/note_repository.dart';
import 'domain/users/user_preferences_repository.dart';
import 'infrastructure/ai/llm_worker_client.dart';
import 'infrastructure/ai/model_catalog.dart';
import 'infrastructure/ai/model_downloader.dart';
import 'infrastructure/ai/model_integrity_verifier.dart';
import 'infrastructure/ai/model_manager.dart';
import 'infrastructure/ai/model_provisioning_contract.dart';
import 'infrastructure/ai/model_selection.dart';
import 'infrastructure/ai/model_storage.dart';
import 'infrastructure/auth/amplify_auth_initializer.dart';
import 'infrastructure/auth/cognito_authentication_service.dart';
import 'infrastructure/configuration/ai_configuration.dart';
import 'infrastructure/configuration/ai_configuration_store.dart';
import 'infrastructure/configuration/note_connection.dart';
import 'infrastructure/device/device_info_plus_hardware_detection.dart';
import 'infrastructure/note_intelligence/local_summarization_service.dart';
import 'infrastructure/note_intelligence/summary_run_runtime.dart';
import 'infrastructure/note_intelligence/summary_failure_mapper.dart';
import 'infrastructure/notes/note_repository.dart' as note_infrastructure;
import 'infrastructure/note_intelligence/rag_http_gateway.dart';
import 'infrastructure/sync/account_sync_runtime.dart';
import 'infrastructure/sync/local_sync_store.dart' as local_sync_infrastructure;
import 'infrastructure/users/user_profile_repository.dart'
    as user_profile_infrastructure;
import 'infrastructure/users/local_user_preferences_repository.dart'
    as user_preferences_infrastructure;
import 'presentation/debug/local_llm_debug_page.dart';
import 'presentation/auth/auth_localizations.dart';
import 'presentation/auth/auth_pages.dart';
import 'presentation/auth/controllers/auth_controller.dart';
import 'presentation/dashboard/dashboard_controller.dart';
import 'presentation/dashboard/dashboard_localizations.dart';
import 'presentation/dashboard/dashboard_page.dart';
import 'presentation/editor/editor_localizations.dart';
import 'presentation/notes/note_detail_localizations.dart';
import 'presentation/notes/note_detail_page.dart';
import 'presentation/notes/note_detail_route_result.dart';
import 'presentation/notes/notes_localizations.dart';
import 'presentation/notes/notes_application_controller.dart';
import 'presentation/notes/summary_cloud_settings_tile.dart';
import 'presentation/common/note_flow_settings.dart';
import 'presentation/notes/notes_theme_tokens.dart';
import 'presentation/notes/notes_workspace_page.dart';
import 'presentation/rag/rag_consent_settings_tile.dart';
import 'presentation/rag/rag_copy.dart';
import 'presentation/rag/rag_page.dart';
import 'presentation/sync/sync_localizations.dart';
import 'presentation/sync/sync_presentation_controller.dart';
import 'presentation/routing/app_router.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/workspace/workspace_localizations.dart';
import 'presentation/workspace/workspace_shell.dart';

part 'main_realtime.dart';
part 'main_rag_part.dart';
part 'main_rag_navigation_part.dart';

// Public deployment outputs only; AWS operator credentials never enter Flutter.
const String amplifyConfig = String.fromEnvironment(
  'NOTEFLOW_AMPLIFY_OUTPUTS',
  defaultValue: generated_amplify.amplifyConfig,
);
const String _noteFlowAuthMode = String.fromEnvironment(
  'NOTEFLOW_AUTH_MODE',
  defaultValue: 'cognito',
);
const String _noteFlowSyncApi = String.fromEnvironment('NOTEFLOW_SYNC_API');
const Color _noteFlowSeedColor = Color(0xFF236BB3);

enum _NoteFlowLanguageChoice { system, vietnamese, english }

Future<String> _profileAccessToken({bool forceRefresh = false}) async {
  final token = await const CognitoAccessTokenProvider().call(
    forceRefresh: forceRefresh,
  );
  if (token == null) {
    throw const ProfileFailure(ProfileFailureCode.unauthorized);
  }
  return token;
}

Uri? _configuredSyncUri() {
  try {
    final config = jsonDecode(amplifyConfig) as Map;
    final endpoint = _noteFlowSyncApi.trim().isNotEmpty
        ? _noteFlowSyncApi.trim()
        : (config['custom'] as Map?)?['syncApiEndpoint'];
    final uri = endpoint is String ? Uri.tryParse(endpoint) : null;
    return uri?.scheme == 'https' && uri!.host.isNotEmpty ? uri : null;
  } on Object {
    return null;
  }
}

ThemeData _buildNoteFlowTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final NoteFlowUiTokens tokens = isDark
      ? NoteFlowUiTokens.dark()
      : NoteFlowUiTokens.light();
  final ColorScheme colorScheme =
      ColorScheme.fromSeed(
        seedColor: _noteFlowSeedColor,
        brightness: brightness,
      ).copyWith(
        primary: tokens.link,
        onPrimary: isDark ? const Color(0xFF102A43) : const Color(0xFFFFFFFF),
        primaryContainer: tokens.selectedSurface,
        onPrimaryContainer: tokens.textPrimary,
        secondaryContainer: tokens.selectedSurface,
        onSecondaryContainer: tokens.textPrimary,
        error: tokens.error,
        outline: tokens.divider,
        surface: tokens.pageSurface,
        onSurface: tokens.textPrimary,
        onSurfaceVariant: tokens.textSecondary,
        surfaceContainerLowest: tokens.pageSurface,
        surfaceContainerLow: tokens.sidebarSurface,
        surfaceContainer: tokens.elevatedSurface,
        surfaceContainerHigh: tokens.elevatedSurface,
        surfaceContainerHighest: tokens.subtleSurface,
      );
  final BorderRadius fieldRadius = BorderRadius.circular(NoteFlowRadius.input);
  final BorderSide fieldBorder = BorderSide(color: tokens.divider);
  final BorderSide focusedFieldBorder = BorderSide(
    color: tokens.focusRing,
    width: 2.0,
  );

  return ThemeData(
    brightness: brightness,
    fontFamily: kIsWeb ? 'NoteFlowSans' : null,
    colorScheme: colorScheme,
    useMaterial3: true,
    extensions: <ThemeExtension<dynamic>>[
      NoteFlowSemanticColors.fromColorScheme(colorScheme),
      tokens,
    ],
    appBarTheme: AppBarThemeData(
      backgroundColor: tokens.pageSurface,
      foregroundColor: tokens.textPrimary,
      elevation: 0.0,
      scrolledUnderElevation: 0.0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 52.0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: tokens.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0.0,
      margin: const EdgeInsets.symmetric(vertical: NoteFlowSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteFlowRadius.card),
        side: BorderSide(color: tokens.divider),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.link,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: tokens.subtleSurface,
        disabledForegroundColor: tokens.textMuted,
        minimumSize: const Size(48.0, 44.0),
        padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.input),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: tokens.subtleSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NoteFlowSpacing.lg,
        vertical: NoteFlowSpacing.md + 2,
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
        borderSide: BorderSide(color: tokens.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: tokens.error, width: 2.0),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.textPrimary,
        foregroundColor: tokens.pageSurface,
        minimumSize: const Size(48.0, 44.0),
        padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.input),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textSecondary,
        side: BorderSide(color: tokens.divider),
        minimumSize: const Size(48.0, 44.0),
        padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.input),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.link,
        minimumSize: const Size(48.0, 44.0),
        padding: const EdgeInsets.symmetric(horizontal: NoteFlowSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NoteFlowRadius.input),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.textSecondary,
      textColor: tokens.textPrimary,
      minTileHeight: 44.0,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NoteFlowSpacing.md,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteFlowRadius.row),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteFlowRadius.dialog),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NoteFlowRadius.dialog),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(NoteFlowRadius.row),
      ),
      textStyle: TextStyle(color: colorScheme.onInverseSurface, fontSize: 12.0),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.divider,
      thickness: 1.0,
      space: 1.0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.link,
      linearTrackColor: tokens.subtleSurface,
      circularTrackColor: tokens.subtleSurface,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      actionTextColor: colorScheme.inversePrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NoteFlowRadius.card),
      ),
      insetPadding: const EdgeInsets.all(NoteFlowSpacing.lg),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ({AuthController authController, CurrentUserSession currentUserSession})
  bootstrap = await _bootstrapAuth();
  runApp(
    NoteFlowApp(
      authController: bootstrap.authController,
      currentUserSession: bootstrap.currentUserSession,
    ),
  );
}

Future<({AuthController authController, CurrentUserSession currentUserSession})>
_bootstrapAuth() async {
  if (_noteFlowAuthMode != 'local' && _noteFlowAuthMode != 'cognito') {
    throw StateError(
      'Unsupported NOTEFLOW_AUTH_MODE: $_noteFlowAuthMode. '
      'Use local or cognito.',
    );
  }

  final CurrentUserSession session = CurrentUserSession();
  if (_noteFlowAuthMode == 'local') {
    session.setIdentity(
      AuthIdentity(
        userId: 'local-user',
        email: 'local-user@noteflow.local',
        isEmailVerified: true,
      ),
    );
    return (
      currentUserSession: session,
      authController: AuthController(
        authenticationAppService: null,
        initialUser: AuthUserDto.fromIdentity(session.identity!),
      ),
    );
  }

  await configureAmplifyAuthCognito(amplifyConfig: amplifyConfig);
  final AuthenticationAppService authenticationAppService =
      AuthenticationAppService(
        authenticationService: const CognitoAuthenticationService(),
        currentUserSession: session,
        userProfileRepository: _configuredSyncUri() == null
            ? user_profile_infrastructure.createUserProfileRepository()
            : HttpUserProfileRepository(
                baseUri: _configuredSyncUri()!,
                accessTokenProvider: _profileAccessToken,
                authenticatedUserId: () async =>
                    (await const CognitoAuthenticationService()
                            .getCurrentIdentity())
                        ?.userId,
              ),
      );
  return (
    currentUserSession: session,
    authController: AuthController(
      authenticationAppService: authenticationAppService,
    ),
  );
}

/// Root composition for the local-LLM summarization proof.
///
/// Infrastructure is assembled here, while the Application service only sees
/// its Domain summarization contract and the debug page only receives a
/// summarization function.
class NoteFlowApp extends StatefulWidget {
  const NoteFlowApp({
    super.key,
    required this.authController,
    required this.currentUserSession,
    this.summaryRuntime,
    this.localSyncStoreFactory,
    this.localSummarizer,
    this.enableSync = true,
    this.enableLabels = const bool.fromEnvironment('NOTEFLOW_LABELS_ENABLED'),
    this.connection,
    this.ragGateway,
    this.ragApiBaseUri,
  });

  final AuthController authController;
  final CurrentUserSession currentUserSession;

  /// Optional composition collaborators for offline acceptance runs.
  final SummaryRunRuntime? summaryRuntime;
  final ILocalSyncStore Function({required String accountUserId})?
  localSyncStoreFactory;
  final SummarizeNoteContent? localSummarizer;

  /// Offline acceptance roots disable unrelated background synchronization.
  final bool enableSync;
  final bool enableLabels;
  final NoteConnection? connection;

  /// Optional RAG collaborators for offline composition tests.
  ///
  /// When [ragGateway] is supplied, the root owns its lifetime and closes it
  /// once on dispose (a gateway over a borrowed HTTP client keeps that client
  /// open). When only [ragApiBaseUri] is supplied, the root builds an HTTP
  /// gateway over it with the sync connection's client/token when compatible.
  final IRagGateway? ragGateway;
  final Uri? ragApiBaseUri;

  @override
  State<NoteFlowApp> createState() => _NoteFlowAppState();
}

class _NoteFlowAppState extends State<NoteFlowApp> with WidgetsBindingObserver {
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
  late final CurrentUserSession _currentUserSession = widget.currentUserSession;
  SummaryRunRuntime? _summaryRuntime;
  int? _lastSummarySessionGeneration;
  final Map<String, ILocalSyncStore> _localSyncStores =
      <String, ILocalSyncStore>{};
  AccountSyncRuntime? _syncRuntime;
  AccountRealtimeService? _realtimeService;
  HttpShareGateway? _sharingGateway;
  NoteSharingAppService? _sharingService;
  bool get _remoteEnabled =>
      widget.connection != null || _noteFlowAuthMode == 'cognito';
  NoteSharingAppService? _sharingForCurrentAccount() {
    final actor = _currentUserSession.userId, uri = _syncApiBaseUri();
    if (!_remoteEnabled || actor == null || uri == null) {
      return null;
    }
    if (_sharingService != null) return _sharingService;
    final generation = _currentUserSession.sessionGeneration;
    final gateway = _sharingGateway = HttpShareGateway(
      baseUri: uri,
      actorId: actor,
      tokenProvider: widget.connection?.tokenProvider ?? _profileAccessToken,
      client: widget.connection?.client,
      isCurrent: () =>
          !_disposed &&
          _currentUserSession.userId == actor &&
          _currentUserSession.sessionGeneration == generation,
      grantHeader: _noteSecurityRuntime.sharingGrant,
    );
    return _sharingService = NoteSharingAppService(
      notes: _noteApplicationService,
      gateway: gateway,
      generateRequestId: _generateMutationId,
      sessionGeneration: () => _currentUserSession.sessionGeneration,
    );
  }

  late final NoteSecurityRuntime _noteSecurityRuntime = NoteSecurityRuntime(
    session: _currentUserSession,
    storeForAccount: _localSyncStoreForAccount,
    baseUri: _remoteEnabled ? _syncApiBaseUri() : null,
    tokenProvider: widget.connection?.tokenProvider,
    client: widget.connection?.client,
    cancelSummaries: () =>
        _summaryRuntime?.cancelActive(reason: SummaryRunFailureCode.noteLocked),
    syncNow: (account) async {
      await _accountSyncRuntime()?.syncNow(account);
    },
  );
  SyncPresentationController? _syncPresentationController;
  String? _syncPresentationAccountUserId;
  String? _lastSyncAccountUserId;
  late final INoteRepository _noteRepository = note_infrastructure
      .createNoteRepository(
        currentAccountUserId: () => _currentUserSession.requiredUserId,
        localSyncStoreFactory: _localSyncStoreForAccount,
        generateMutationId: _generateMutationId,
        now: _nowUtc,
        accessGuard: _noteSecurityRuntime,
        labelsEnabled: widget.enableLabels,
        sessionGeneration: () => _currentUserSession.sessionGeneration,
      );
  late final LabelApplication _labelApplication = LabelApplication(
    currentActor: () => _currentUserSession.userId ?? '',
    generation: () => _currentUserSession.sessionGeneration,
    storeFor: (actor) => _localSyncStoreForAccount(accountUserId: actor),
    notes: _noteRepository,
    generateId: _generateNoteId,
    now: _nowUtc,
    requestSync: _requestSyncForAccount,
  );
  late final IUserPreferencesRepository _userPreferencesRepository =
      user_preferences_infrastructure.createLocalUserPreferencesRepository(
        currentAccountUserId: () => _currentUserSession.userId ?? '',
        localSyncStoreFactory: _localSyncStoreForAccount,
        sessionGeneration: () => _currentUserSession.sessionGeneration,
      );
  late final NoteApplicationService _noteApplicationService =
      NoteApplicationService(
        noteRepository: _noteRepository,
        userPreferencesRepository: _userPreferencesRepository,
        currentUser: _currentUserSession,
        generateId: _generateNoteId,
        now: _nowUtc,
        summarizeContent: (String content) =>
            withSummaryFailureBoundary(() => _summarize(content)),
        summarizeRun: _summaryRunRuntime.dispatchesSummary
            ? _summaryRunRuntime.summarize
            : null,
        cloudConsent: _summaryRunRuntime.consent,
        sessionGeneration: () => _currentUserSession.sessionGeneration,
        requestSync: _requestSyncForAccount,
        security: _noteSecurityRuntime,
      );
  late final _attachmentRuntime = AttachmentRuntime(
    security: _noteSecurityRuntime,
    notes: _noteRepository,
    allowLocalAttachmentUploads:
        widget.connection?.allowLocalAttachmentUploads ?? false,
    storeForAccount: (actor) {
      final store = _localSyncStoreForAccount(accountUserId: actor);
      if (store is! EncryptedSyncStore) {
        throw StateError('Attachments require the encrypted account store.');
      }
      return store;
    },
    requestSync: _requestSyncForAccount,
  );
  late final _attachmentPicker = FlutterAttachmentPicker();
  late final NotesApplicationController _notesController =
      NoteApplicationServiceController(
        _noteApplicationService,
        summaryConsent: _summaryConsentService,
        securityForCurrentAccount: () =>
            _noteSecurityRuntime.forAccount(_currentUserSession.requiredUserId),
        securityEvents: _noteSecurityRuntime.changes,
        readAccessGeneration: () => _noteSecurityRuntime.accessGeneration,
        readSessionGeneration: () => _currentUserSession.sessionGeneration,
        serverAvailable: _noteSecurityRuntime.serverAvailable,
        sharingForCurrentAccount: _sharingForCurrentAccount,
        attachmentsForCurrentAccount: () {
          if (_currentUserSession.userId == null) return null;
          final store = _localSyncStoreForAccount(
            accountUserId: _currentUserSession.requiredUserId,
          );
          return store is EncryptedSyncStore
              ? _attachmentRuntime.forCurrentAccount()
              : null;
        },
        attachmentPicker: _attachmentPicker.pick,
      );

  late final SummaryConsentAppService _summaryConsentService =
      SummaryConsentAppService(
        currentUser: _currentUserSession,
        session: _currentUserSession,
        consent: _summaryRunRuntime.consent,
        requiresCloudConsent: _summaryRunRuntime.dispatchesSummary,
        isAvailable: () =>
            !_disposed &&
            (_summaryRunRuntime.configuration.isLocal
                ? !kIsWeb
                : _summaryRunRuntime.configuration.isRemote &&
                      _summaryRunRuntime.configuration.canSummarize &&
                      widget.connection == null &&
                      _noteFlowAuthMode == 'cognito'),
        cancelActiveRuns: () => _summaryRunRuntime.cancelActive(
          reason: SummaryRunFailureCode.consentRequired,
        ),
      );

  SummaryRunRuntime get _summaryRunRuntime => _summaryRuntime ??=
      widget.summaryRuntime ??
      SummaryRunRuntime.fromEnvironment(
        session: _currentUserSession,
        localSyncStoreForAccount: _localSyncStoreForAccount,
        amplifyOutputsJson: amplifyConfig,
        cognitoMode:
            widget.connection == null && _noteFlowAuthMode == 'cognito',
        accessGuardForAccount: (_) => _noteSecurityRuntime,
        grantHeaderForRun: _noteSecurityRuntime.summaryGrant,
      );
  late final DashboardController _dashboardController = DashboardController(
    securityEvents: _noteSecurityRuntime.changes,
    query: GetDashboardOverview(
      noteRepository: _noteRepository,
      currentUser: _currentUserSession,
    ),
    recentLimit: 20,
  );
  final GlobalKey<WorkspaceShellState> _workspaceShellKey =
      GlobalKey<WorkspaceShellState>();
  final GlobalKey<DashboardPageState> _dashboardPageKey =
      GlobalKey<DashboardPageState>();
  final GlobalKey<NotesWorkspacePageState> _notesPageKey =
      GlobalKey<NotesWorkspacePageState>();

  /// Lazily created root owner of the shared RAG service/gateway. Kept nullable
  /// so a session that never touches ask-notes never constructs it.
  _RagRoot? _ragRootInstance;
  _RagRoot get _ragRoot => _ragRootInstance ??= _RagRoot(this);
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
  late final GoRouter _router;
  ProfileAppService? _profileService;
  ProfileAppService? _profilePageService;
  HttpUserProfileRepository? _profileRepository;
  HttpProfileAvatarGateway? _profileAvatarGateway;

  void _closeProfileClients() {
    _profileRepository?.close();
    _profileAvatarGateway?.close();
    _profileRepository = null;
    _profileAvatarGateway = null;
    _profileService = null;
    _profilePageService = null;
  }

  final _profileView =
      ValueNotifier<
        ({ProfileSnapshot? snapshot, bool loaded, bool unavailable})
      >((snapshot: null, loaded: false, unavailable: false));
  ProfileSnapshot? get _profile => _profileView.value.snapshot;
  bool get _profileUnavailable => _profileView.value.unavailable;
  bool get _profileLoaded => _profileView.value.loaded;
  int? _presentationGeneration;
  int _profileRequest = 0;
  int _themeRequest = 0;
  bool _disposed = false;

  ProfileAppService? _profileForCurrentAccount() {
    if (!_remoteEnabled ||
        widget.connection != null ||
        _currentUserSession.userId == null) {
      return null;
    }
    final uri = _syncApiBaseUri();
    if (uri == null) return null;
    final generation = _currentUserSession.sessionGeneration;
    Future<String?> authenticatedActor() async {
      if (generation != _currentUserSession.sessionGeneration) return null;
      final identity = await const CognitoAuthenticationService()
          .getCurrentIdentity();
      return generation == _currentUserSession.sessionGeneration
          ? identity?.userId
          : null;
    }

    return _profileService ??= ProfileAppService(
      repository: _profileRepository = HttpUserProfileRepository(
        baseUri: uri,
        accessTokenProvider: _profileAccessToken,
        authenticatedUserId: authenticatedActor,
      ),
      avatarGateway: _profileAvatarGateway = HttpProfileAvatarGateway(
        baseUri: uri,
        accessTokenProvider: _profileAccessToken,
        authenticatedUserId: authenticatedActor,
      ),
      session: _currentUserSession,
    );
  }

  Future<void> _refreshProfile() async {
    final service = _profileForCurrentAccount();
    if (service == null) return;
    final generation = _currentUserSession.sessionGeneration;
    final request = ++_profileRequest;
    try {
      final snapshot = await service.load();
      if (!mounted ||
          _disposed ||
          generation != _currentUserSession.sessionGeneration ||
          request != _profileRequest) {
        return;
      }
      _profileView.value = (
        snapshot: snapshot,
        loaded: true,
        unavailable: false,
      );
    } on Object {
      if (!mounted ||
          _disposed ||
          generation != _currentUserSession.sessionGeneration ||
          request != _profileRequest) {
        return;
      }
      _profileView.value = (
        snapshot: _profile,
        loaded: true,
        unavailable: true,
      );
    }
  }

  Future<void> _restoreTheme() async {
    final generation = _currentUserSession.sessionGeneration;
    final request = ++_themeRequest;
    try {
      final theme = await _noteApplicationService.getTheme();
      if (!mounted ||
          _disposed ||
          generation != _currentUserSession.sessionGeneration ||
          request != _themeRequest) {
        return;
      }
      setState(() => _themeMode = ThemeMode.values.byName(theme.name));
    } on Object {
      // A failed preference read leaves notes usable with the system theme.
    }
  }

  Widget _buildProfile(BuildContext context) {
    final service = _profileForCurrentAccount();
    final vi = Localizations.localeOf(context).languageCode == 'vi';
    if (service == null) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(AppRoutes.home)),
          title: Text(vi ? 'Hồ sơ' : 'Profile'),
        ),
        body: Center(
          child: Text(
            vi
                ? 'Chưa cấu hình dịch vụ hồ sơ.'
                : 'Profile service is not configured.',
          ),
        ),
      );
    }
    final generation = _currentUserSession.sessionGeneration;
    final page = ProfilePage(
      key: ValueKey('profile-$generation'),
      service: _profilePageService ??= ProfileAppService(
        repository: service.repository,
        avatarGateway: service.avatarGateway,
        session: _currentUserSession,
      ),
      pickAvatar: ProfileAvatarPicker().pick,
      initialDisplayName: widget.authController.pendingProfileDisplayName,
      onBack: () => context.go(AppRoutes.home),
      onChanged: (snapshot) {
        if (!mounted ||
            _disposed ||
            generation != _currentUserSession.sessionGeneration) {
          return;
        }
        _profileRequest++;
        _profileView.value = (
          snapshot: snapshot,
          loaded: true,
          unavailable: false,
        );
        if (snapshot.profile != null) {
          widget.authController.pendingProfileDisplayName = null;
        }
      },
    );
    return Column(
      children: [
        EmailVerificationBanner(controller: widget.authController),
        Expanded(child: page),
      ],
    );
  }

  // ponytail: one local model worker; per-model latches if multiple runtimes exist.
  bool _localSummaryRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.authController.addListener(_onAuthenticationChanged);
    // A restored/local identity must own sync before the router mounts Notes.
    // Otherwise initialize() can dispose the controller handed to that page.
    _onAuthenticationChanged();
    _router = createAppRouter(
      authController: widget.authController,
      workspaceBuilder: (context) => ValueListenableBuilder(
        valueListenable: _profileView,
        builder: (context, _, _) => _buildWorkspace(context),
      ),
      profileBuilder: _buildProfile,
    );
    unawaited(_initializeAuth());
  }

  Future<void> _initializeAuth() async {
    try {
      await widget.authController.initialize();
    } on Object {
      // AuthController retains the safe mapped startup error for the router's
      // splash/retry page; startup must not become an uncaught async error.
    }
    _onAuthenticationChanged();
  }

  String _generateMutationId() => 'mutation-${_generateNoteId()}';

  String _syncApiEndpoint() {
    final String configuredEndpoint = _noteFlowSyncApi.trim();
    if (configuredEndpoint.isNotEmpty) {
      return configuredEndpoint;
    }

    try {
      final Object? decoded = jsonDecode(amplifyConfig);
      if (decoded is Map) {
        final Object? custom = decoded['custom'];
        if (custom is Map) {
          final Object? endpoint = custom['syncApiEndpoint'];
          if (endpoint is String) {
            return endpoint.trim();
          }
        }
      }
    } on Object {
      // Sync remains local-only when generated Amplify outputs are unavailable.
    }
    return '';
  }

  Uri? _syncApiBaseUri() {
    if (widget.connection != null) return widget.connection!.baseUri;
    final Uri? uri = Uri.tryParse(_syncApiEndpoint());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  void _requestSyncForAccount(String accountUserId) {
    _accountSyncRuntime()?.requestSync(accountUserId);
  }

  AccountSyncRuntime? _accountSyncRuntime() {
    if (!widget.enableSync || !_remoteEnabled) {
      return null;
    }
    final Uri? baseUri = _syncApiBaseUri();
    if (baseUri == null) {
      return null;
    }
    return _syncRuntime ??= AccountSyncRuntime(
      baseUri: baseUri,
      documentsEnabled: true,
      labelsEnabled: widget.enableLabels,
      projectionGrant: _noteSecurityRuntime.labelProjectionGrant,
      onCatalogChanged: (_) => _labelApplication.notifyChanged(),
      tokenProvider: widget.connection?.tokenProvider,
      client: widget.connection?.client,
      localSyncStoreFactory: _localSyncStoreForAccount,
      clock: _nowUtc,
      mutationGrant: _noteSecurityRuntime.mutationGrant,
      observeSnapshot: _noteSecurityRuntime.observe,
      hydrateSnapshot: _noteSecurityRuntime.hydrate,
      requireSession: _noteSecurityRuntime.requireSession,
      sessionGeneration: () => _currentUserSession.sessionGeneration,
    );
  }

  void _onAuthenticationChanged() {
    final int generation = _currentUserSession.sessionGeneration;
    final int? previous = _lastSummarySessionGeneration;
    final presentationChanged = _presentationGeneration != generation;
    if (presentationChanged) {
      _presentationGeneration = generation;
      _profileRequest++;
      _themeRequest++;
      _closeProfileClients();
      _profileView.value = (snapshot: null, loaded: false, unavailable: false);
      _themeMode = ThemeMode.system;
      if (mounted) setState(() {});
    }
    if (previous != null && previous != generation) {
      _stopRealtime();
      _invalidateSummaryRuns();
      _noteSecurityRuntime.invalidateSession();
      _sharingGateway?.close();
      _sharingGateway = null;
      _sharingService = null;
      final previousSync = _syncRuntime;
      _syncRuntime = null;
      if (previousSync != null) unawaited(previousSync.dispose());
      _lastSyncAccountUserId = null;
      for (final store in _localSyncStores.values) {
        if (store is ILocalNoteVault) {
          (store as ILocalNoteVault).lock(null);
        }
      }
    }
    _lastSummarySessionGeneration = generation;
    _ragRoot.onAuthenticationChanged(sessionChanged: previous != generation);
    if (presentationChanged && _currentUserSession.userId != null) {
      unawaited(_restoreTheme());
      unawaited(_refreshProfile());
    }

    final String? accountUserId = _currentUserSession.userId;
    if (accountUserId == null) {
      _stopRealtime();
      _lastSyncAccountUserId = null;
      _disposeSyncPresentationController();
      return;
    }
    if (accountUserId == _lastSyncAccountUserId) {
      return;
    }
    _lastSyncAccountUserId = accountUserId;
    _disposeSyncPresentationController();
    _requestSyncForAccount(accountUserId);
    _startRealtime(accountUserId);
  }

  void _invalidateSummaryRuns() {
    _summaryRuntime?.cancelActive(reason: SummaryRunFailureCode.sessionChanged);
    _summaryRuntime?.consent.revoke();
  }

  void _disposeSyncPresentationController() {
    _ragRootInstance?.attachSyncController(null);
    final SyncPresentationController? controller = _syncPresentationController;
    _syncPresentationController = null;
    _syncPresentationAccountUserId = null;
    if (controller == null) return;
    // The workspace route subtree is built by the router, not by this state's
    // build, so a sign-out/account rebuild can still attach to the controller
    // in the current frame. Retire it after the frame instead of disposing it
    // synchronously, so a disposed controller is never handed to a new
    // listener during the route teardown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  SyncPresentationController? _syncPresentationControllerForCurrentAccount() {
    final String? accountUserId = _currentUserSession.userId;
    if (accountUserId == null) return null;
    final AccountSyncRuntime? runtime = _accountSyncRuntime();
    if (runtime == null) return null;
    if (_syncPresentationAccountUserId == accountUserId &&
        _syncPresentationController != null) {
      return _syncPresentationController;
    }
    _disposeSyncPresentationController();
    final ILocalSyncStore localStore = _localSyncStoreForAccount(
      accountUserId: accountUserId,
    );
    _syncPresentationAccountUserId = accountUserId;
    final int generation = _currentUserSession.sessionGeneration;
    final SyncPresentationController controller = _syncPresentationController =
        SyncPresentationController(
          accountUserId: accountUserId,
          localStore: localStore,
          coordinator: runtime.coordinatorFor(accountUserId),
          securityEvents: _noteSecurityRuntime.changes,
          isCurrentSession: () =>
              _currentUserSession.userId == accountUserId &&
              _currentUserSession.sessionGeneration == generation,
          conflictResolver: SyncConflictResolver(
            localSyncStore: localStore,
            generateNoteId: _generateNoteId,
            generateMutationId: _generateMutationId,
            now: _nowUtc,
            accessGuard: _noteSecurityRuntime,
          ),
        );
    // The RAG root revalidates its answer on the same sync changes without
    // duplicating any business state.
    _ragRoot.attachSyncController(controller);
    return controller;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ragRootInstance?.onLifecycle(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _noteSecurityRuntime.lockAll();
      _stopRealtime();
    }
    if (state == AppLifecycleState.resumed) {
      final String? accountUserId = _currentUserSession.userId;
      if (accountUserId != null) {
        _requestSyncForAccount(accountUserId);
        _startRealtime(accountUserId);
        unawaited(_refreshProfile());
      }
    }
  }

  ILocalSyncStore _localSyncStoreForAccount({required String accountUserId}) {
    return _localSyncStores.putIfAbsent(
      accountUserId,
      () =>
          widget.localSyncStoreFactory?.call(accountUserId: accountUserId) ??
          local_sync_infrastructure.createLocalSyncStore(
            accountUserId: accountUserId,
          ),
    );
  }

  Future<Summary> _summarize(String content) async {
    if (_localSummaryRunning) {
      throw const SummaryRunFailure(SummaryRunFailureCode.alreadyRunning);
    }
    _localSummaryRunning = true;
    try {
      final SummarizeNoteContent? supplied = widget.localSummarizer;
      if (supplied != null) return await supplied(content);
      final NoteSummaryAppService service = await _ensureService();
      return await service.summarize(content);
    } finally {
      _localSummaryRunning = false;
    }
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
          syncController: _syncPresentationControllerForCurrentAccount(),
          provisioningReader: _summaryRunRuntime.configuration.isLocal
              ? _modelProvisioningStatus
              : null,
          onProvisioningCancel: _summaryRunRuntime.configuration.isLocal
              ? _cancelModelProvisioning
              : null,
          showAppBar: false,
        ),
      ),
    );
  }

  Future<NoteDetailRouteResult?> _openNoteInWorkspace(
    BuildContext context, {
    NoteDto? note,
  }) async {
    final NotesWorkspacePageState? notesPage = _notesPageKey.currentState;
    final bool preserveUnsavedChanges = notesPage?.hasUnsavedChanges ?? false;
    _workspaceShellKey.currentState?.showDestination(
      WorkspaceDestination.notes,
    );
    if (notesPage == null) {
      return _openNoteDetail(context, note);
    }
    if (!preserveUnsavedChanges) {
      await notesPage.reload();
    }
    if (note == null) {
      notesPage.startNewNote();
    } else {
      notesPage.openNote(note);
    }
    return null;
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

  Future<void> _logout() async {
    _invalidateSummaryRuns();
    try {
      await widget.authController.logout();
    } on Object {
      // AuthController clears local state even when provider sign-out fails;
      // the router will move the user to the public login route.
    }
  }

  void _reloadWorkspaceDestination(WorkspaceDestination destination) {
    switch (destination) {
      case WorkspaceDestination.dashboard:
        final DashboardPageState? page = _dashboardPageKey.currentState;
        if (page != null) {
          unawaited(page.reload());
        }
      case WorkspaceDestination.notes:
        final NotesWorkspacePageState? page = _notesPageKey.currentState;
        if (page != null && !page.hasUnsavedChanges) {
          unawaited(page.reload());
        }
    }
  }

  void _openLocalDiagnostics(BuildContext context) {
    if (!_summaryRunRuntime.configuration.isLocal) return;
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
  }

  Future<void> _showAppearanceSettings(BuildContext context) async {
    ThemeMode selectedTheme = _themeMode;
    _NoteFlowLanguageChoice selectedLanguage = _languageChoice;
    final generation = _currentUserSession.sessionGeneration;
    bool savingTheme = false;
    String? themeError;
    // Ask-notes consent is shown separately from cloud Summary consent. The
    // service is created only when the feature is actually configured.
    final RagAppService? ragService = _ragRoot.ensureService();

    await showNoteFlowSettings(
      context: context,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final NotesCopy copy = NotesCopy.of(context);
            final AuthCopy authCopy = AuthCopy.of(context);
            final bool webPreferences =
                kIsWeb && !NoteFlowLayout.isCompact(context);
            final bool vi =
                Localizations.localeOf(context).languageCode == 'vi';
            return NoteFlowSettingsSurface(
              title: webPreferences
                  ? (vi ? 'Tùy chọn' : 'Preferences')
                  : copy.appearanceAndLanguage,
              subtitle: Localizations.localeOf(context).languageCode == 'vi'
                  ? 'Chọn giao diện và ngôn ngữ cho ứng dụng.'
                  : 'Choose how the app looks and which language it uses.',
              accountActions: <Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline, size: 20),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  title: Text(
                    Localizations.localeOf(context).languageCode == 'vi'
                        ? 'Hồ sơ'
                        : 'Profile',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(AppRoutes.profile);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lock_outline, size: 20),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  title: Text(authCopy.changePassword),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go(AppRoutes.changePassword);
                  },
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, size: 20),
                  title: Text(authCopy.logout),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_logout());
                  },
                ),
              ],
              children: <Widget>[
                if (webPreferences)
                  NoteFlowSettingsSectionTitle(vi ? 'Giao diện' : 'Appearance'),
                NoteFlowSettingsChoice<ThemeMode>(
                  key: ValueKey<ThemeMode>(selectedTheme),
                  initialValue: selectedTheme,
                  label: copy.theme,
                  helperText:
                      Localizations.localeOf(context).languageCode == 'vi'
                      ? 'Chọn giao diện cho thiết bị này.'
                      : 'Choose the appearance on this device.',
                  items: <DropdownMenuItem<ThemeMode>>[
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(copy.themeSystem),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(copy.themeLight),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(copy.themeDark),
                    ),
                  ],
                  onChanged: savingTheme
                      ? null
                      : (ThemeMode? value) async {
                          if (value == null ||
                              generation !=
                                  _currentUserSession.sessionGeneration) {
                            return;
                          }
                          final request = ++_themeRequest;
                          setSheetState(() {
                            savingTheme = true;
                            themeError = null;
                          });
                          try {
                            await _noteApplicationService.setTheme(
                              AppThemePreference.values.byName(value.name),
                            );
                            if (!mounted ||
                                generation !=
                                    _currentUserSession.sessionGeneration ||
                                request != _themeRequest) {
                              return;
                            }
                            setState(() => _themeMode = value);
                            if (sheetContext.mounted) {
                              setSheetState(() => selectedTheme = value);
                            }
                          } on Object {
                            if (sheetContext.mounted &&
                                generation ==
                                    _currentUserSession.sessionGeneration) {
                              setSheetState(
                                () => themeError =
                                    Localizations.localeOf(context)
                                            .languageCode ==
                                        'vi'
                                    ? 'Chưa lưu được giao diện. Hãy thử lại.'
                                    : 'Theme was not saved. Please try again.',
                              );
                            }
                          } finally {
                            if (sheetContext.mounted) {
                              setSheetState(() => savingTheme = false);
                            }
                          }
                        },
                ),
                if (savingTheme) const LinearProgressIndicator(),
                if (themeError != null)
                  Text(
                    themeError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (webPreferences) ...[
                  const SizedBox(height: 24),
                  NoteFlowSettingsSectionTitle(vi ? 'Ngôn ngữ' : 'Language'),
                ] else
                  const Divider(height: 1),
                NoteFlowSettingsChoice<_NoteFlowLanguageChoice>(
                  key: ValueKey<_NoteFlowLanguageChoice>(selectedLanguage),
                  initialValue: selectedLanguage,
                  label: copy.language,
                  helperText:
                      Localizations.localeOf(context).languageCode == 'vi'
                      ? 'Ngôn ngữ hiển thị trong ứng dụng.'
                      : 'The language used throughout the app.',
                  items: <DropdownMenuItem<_NoteFlowLanguageChoice>>[
                    DropdownMenuItem(
                      value: _NoteFlowLanguageChoice.system,
                      child: Text(copy.languageSystem),
                    ),
                    DropdownMenuItem(
                      value: _NoteFlowLanguageChoice.vietnamese,
                      child: Text(copy.languageVietnamese),
                    ),
                    DropdownMenuItem(
                      value: _NoteFlowLanguageChoice.english,
                      child: Text(copy.languageEnglish),
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
                if (webPreferences &&
                    (_summaryConsentService.requiresCloudConsent ||
                        ragService != null)) ...[
                  const SizedBox(height: 24),
                  NoteFlowSettingsSectionTitle(
                    vi ? 'Tính năng AI' : 'AI features',
                  ),
                  const SizedBox(height: 16),
                ] else
                  const Divider(height: 32),
                if (_summaryConsentService.requiresCloudConsent) ...<Widget>[
                  SummaryCloudSettingsTile(service: _summaryConsentService),
                  const SizedBox(height: 24),
                ],
                if (ragService != null) ...<Widget>[
                  RagConsentSettingsTile(
                    key: const ValueKey<String>('settings-rag-consent'),
                    service: ragService,
                  ),
                  const SizedBox(height: 24),
                ],
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NoteFlow',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => NoteFlowSystemBars(
        child: LabelCatalogHost(
          application: widget.enableLabels ? _labelApplication : null,
          securityChanges: _noteSecurityRuntime.changes,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      theme: _buildNoteFlowTheme(Brightness.light),
      darkTheme: _buildNoteFlowTheme(Brightness.dark),
      themeMode: _themeMode,
      locale: _selectedLocale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        NoteFlowEditorLocalizationsDelegate(),
        AuthCopy.delegate,
        NotesCopy.delegate,
        NoteDetailCopy.delegate,
        SyncCopy.delegate,
        DashboardCopy.delegate,
        WorkspaceCopy.delegate,
        RagCopy.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      routerConfig: _router,
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return Column(
      children: <Widget>[
        EmailVerificationBanner(controller: widget.authController),
        if (_remoteEnabled &&
            (_profileUnavailable ||
                (_profileLoaded && _profile?.profile == null)))
          MaterialBanner(
            content: Text(
              Localizations.localeOf(context).languageCode == 'vi'
                  ? (_profileUnavailable
                        ? 'Hồ sơ hiện không tải được. Ghi chú vẫn dùng được.'
                        : 'Hoàn tất tên và ảnh hồ sơ của bạn.')
                  : (_profileUnavailable
                        ? 'Profile is unavailable. You can still use your notes.'
                        : 'Complete your name and profile photo.'),
            ),
            actions: [
              TextButton(
                onPressed: () => context.go(AppRoutes.profile),
                child: Text(
                  Localizations.localeOf(context).languageCode == 'vi'
                      ? 'Mở hồ sơ'
                      : 'Open Profile',
                ),
              ),
            ],
          ),
        Expanded(
          child: WorkspaceShell(
            key: _workspaceShellKey,
            accountAvatar: _profile?.avatarBytes == null
                ? null
                : MemoryImage(_profile!.avatarBytes!),
            accountName:
                _profile?.profile?.displayName ??
                widget.currentUserSession.identity?.email.split('@').first,
            onDestinationChanged: (WorkspaceDestination destination) {
              if (destination != WorkspaceDestination.dashboard) {
                _dashboardPageKey.currentState?.closeSearch();
              }
              _reloadWorkspaceDestination(destination);
            },
            onOpenSearch: () {
              _workspaceShellKey.currentState?.showDestination(
                WorkspaceDestination.dashboard,
              );
              _dashboardPageKey.currentState?.openSearch();
            },
            onCreateNote: () => unawaited(_openNoteInWorkspace(context)),
            onOpenSettings: () => _showAppearanceSettings(context),
            onOpenRag: _ragRoot.available
                ? () => _ragRoot.openAccountScope(context)
                : null,
            onOpenDiagnostics: _summaryRunRuntime.configuration.isLocal
                ? () => _openLocalDiagnostics(context)
                : null,
            dashboard: DashboardPage(
              key: _dashboardPageKey,
              noteChanges: _syncPresentationControllerForCurrentAccount(),
              embeddedInWorkspace: true,
              dashboardController: _dashboardController,
              notesController: _notesController,
              onOpenNote: (NoteDto note) =>
                  _openNoteInWorkspace(context, note: note),
              onCreateNote: () => _openNoteInWorkspace(context),
              onOpenSettings: () => _showAppearanceSettings(context),
              onOpenDiagnostics: _summaryRunRuntime.configuration.isLocal
                  ? () => _openLocalDiagnostics(context)
                  : null,
              onSearchVisibilityChanged: (bool active) {
                _workspaceShellKey.currentState?.setCompactSearchActive(active);
              },
            ),
            notes: NotesWorkspacePage(
              key: _notesPageKey,
              onDetailVisibilityChanged: (visible) =>
                  _workspaceShellKey.currentState?.setNoteEditorActive(visible),
              embeddedInWorkspace: true,
              controller: _notesController,
              provisioningReader: _summaryRunRuntime.configuration.isLocal
                  ? _modelProvisioningStatus
                  : null,
              onProvisioningCancel: _summaryRunRuntime.configuration.isLocal
                  ? _cancelModelProvisioning
                  : null,
              syncController: _syncPresentationControllerForCurrentAccount(),
              onNoteEdited: _ragRoot.onNoteEdited,
              onOpenNoteRag: _ragRoot.available
                  ? (NoteDto note) => _ragRoot.openNoteScope(context, note)
                  : null,
              onOpenSettings: () => _showAppearanceSettings(context),
              onOpenDiagnostics: _summaryRunRuntime.configuration.isLocal
                  ? () => _openLocalDiagnostics(context)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _closeProfileClients();
    _stopRealtime();
    _noteSecurityRuntime.dispose();
    if (widget.enableLabels) unawaited(_labelApplication.dispose());
    _disposed = true;
    _profileView.dispose();
    for (final store in _localSyncStores.values) {
      if (store is ILocalNoteVault) {
        (store as ILocalNoteVault).dispose();
      }
    }
    _summaryRuntime?.dispose();
    _sharingGateway?.close();
    WidgetsBinding.instance.removeObserver(this);
    widget.authController.removeListener(_onAuthenticationChanged);
    _disposeSyncPresentationController();
    _ragRootInstance?.dispose();
    _router.dispose();
    widget.authController.dispose();
    final LlmWorkerClient? client = _workerClient;
    if (client != null) {
      unawaited(client.dispose());
    }
    final AccountSyncRuntime? syncRuntime = _syncRuntime;
    if (syncRuntime != null) {
      unawaited(syncRuntime.dispose());
    }
    super.dispose();
  }
}
