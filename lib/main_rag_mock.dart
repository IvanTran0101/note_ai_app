/// Explicit offline RAG mock root. Never selected by plain `flutter run`.
///
/// This is a debug-only, fully synthetic runtime for manual Web/macOS/iOS
/// checks of the real ask-my-notes surfaces. It hard-fails a release build and
/// any non-loopback Web host, shows a visible synthetic banner, and answers the
/// two documented fixture questions through the real `RagHttpGateway` over an
/// in-process transport.
///
/// The synthetic RAG, sync, and consent state is memory-only: this root never
/// reaches AWS, a real account, a key, a provider, the network, or a model
/// download, and it injects a local-summarization refusal so no model runtime
/// can start from it. This is not whole-app disk isolation: unrelated
/// [NoteFlowApp] diagnostics may still read the native readiness file through
/// `AiConfigurationStore`; only the synthetic surfaces above are promised to
/// stay in memory.
library;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'application/auth/auth_models.dart';
import 'application/auth/current_user_session.dart';
import 'application/note_intelligence/summary_run_context.dart';
import 'dev/rag_mock_actors.dart';
import 'dev/rag_mock_runtime.dart';
import 'domain/auth/auth_identity.dart';
import 'domain/note_intelligence/summary.dart';
import 'main.dart' show NoteFlowApp;
import 'presentation/auth/controllers/auth_controller.dart';

void main() {
  requireRagMockRuntime(
    isDebugMode: kDebugMode,
    isWeb: kIsWeb,
    baseUri: Uri.base,
  );
  WidgetsFlutterBinding.ensureInitialized();
  final RagMockActor actor = ragMockActorFromEnvironment();
  final CurrentUserSession session = CurrentUserSession()
    ..setIdentity(
      AuthIdentity(
        userId: actor.userId,
        email: actor.email,
        isEmailVerified: true,
      ),
    );
  final AuthController controller = AuthController(
    authenticationAppService: null,
    initialUser: AuthUserDto.fromIdentity(session.identity!),
  );
  runApp(
    _RagMockRoot(
      runtime: RagMockRuntime.create(actor),
      session: session,
      controller: controller,
    ),
  );
}

/// Refuses every local summarization before any engine, model, or download work.
///
/// This is the composition-root answer to `NoteFlowApp.localSummarizer`, the
/// same seam the production root uses to supply an offline summarizer. That seam
/// is checked by `_summarize` before `_ensureService`/`_startService`, so the
/// note-detail Summary action and the local diagnostics page both get the typed
/// refusal instead of a `mobileModelManager.download`.
Future<Summary> _refuseLocalSummarization(String content) {
  throw const SummaryRunFailure(SummaryRunFailureCode.runtimeUnavailable);
}

class _RagMockRoot extends StatefulWidget {
  const _RagMockRoot({
    required this.runtime,
    required this.session,
    required this.controller,
  });

  final RagMockRuntime runtime;
  final CurrentUserSession session;
  final AuthController controller;

  @override
  State<_RagMockRoot> createState() => _RagMockRootState();
}

class _RagMockRootState extends State<_RagMockRoot> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: <Widget>[
          Material(
            color: const Color(0xFFFFE3A3),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  widget.runtime.bannerText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black),
                ),
              ),
            ),
          ),
          Expanded(
            child: NoteFlowApp(
              authController: widget.controller,
              currentUserSession: widget.session,
              connection: widget.runtime.connection,
              ragApiBaseUri: widget.runtime.ragApiBaseUri,
              localSyncStoreFactory: widget.runtime.storeFor,
              localSummarizer: _refuseLocalSummarization,
              enableLabels: false,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.runtime.dispose();
    super.dispose();
  }
}
