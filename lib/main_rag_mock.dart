/// Explicit offline RAG mock root. Never selected by plain `flutter run`.
///
/// This is a debug-only, fully synthetic runtime for manual Web/macOS/iOS
/// checks of the real ask-my-notes surfaces. It hard-fails a release build and
/// any non-loopback Web host, shows a visible synthetic banner, and answers the
/// two documented fixture questions through the real `RagHttpGateway` over an
/// in-process transport.
///
/// The synthetic RAG, sync, and consent state is memory-only. The mock
/// connection keeps cloud Summary unavailable.
library;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'application/auth/auth_models.dart';
import 'application/auth/current_user_session.dart';
import 'dev/rag_mock_actors.dart';
import 'dev/rag_mock_runtime.dart';
import 'domain/auth/auth_identity.dart';
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
