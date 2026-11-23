/// Explicit local development root. Never selected by plain flutter run.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/auth/auth_models.dart';
import 'application/auth/current_user_session.dart';
import 'dev/m06_local_connection.dart';
import 'domain/auth/auth_identity.dart';
import 'main.dart' show NoteFlowApp;
import 'presentation/auth/controllers/auth_controller.dart';

void main() {
  if (!kDebugMode) throw StateError('main_dev supports debug builds only.');
  if (kIsWeb && !{'localhost', '127.0.0.1'}.contains(Uri.base.host)) {
    throw StateError('main_dev must be served on loopback.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  const configured = String.fromEnvironment(
    'M06_DEV_USER',
    defaultValue: 'owner',
  );
  final selected = kIsWeb
      ? (Uri.base.queryParameters['devUser'] ?? configured)
      : configured;
  final actor = devActors[selected], email = devEmails[selected];
  if (actor == null || email == null) {
    throw StateError('Use devUser=owner or recipient.');
  }
  final session = CurrentUserSession()
    ..setIdentity(
      AuthIdentity(userId: actor, email: email, isEmailVerified: true),
    );
  final controller = AuthController(
    authenticationAppService: null,
    initialUser: AuthUserDto.fromIdentity(session.identity!),
  );
  runApp(
    _LocalDevRoot(session: session, controller: controller, selected: selected),
  );
}

class _LocalDevRoot extends StatefulWidget {
  const _LocalDevRoot({
    required this.session,
    required this.controller,
    required this.selected,
  });
  final CurrentUserSession session;
  final AuthController controller;
  final String selected;
  @override
  State<_LocalDevRoot> createState() => _LocalDevRootState();
}

class _LocalDevRootState extends State<_LocalDevRoot> {
  late final client = M06LoopbackClient();
  late final connection = devConnection(widget.session.requiredUserId, client);
  @override
  Widget build(BuildContext context) => MediaQuery.fromView(
    view: View.of(context),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Material(
          color: const Color(0xFFFAFAF9),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Material(
                  color: const Color(0xFFFAFAF9),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    constraints: const BoxConstraints(minHeight: 20),
                    child: Center(
                      child: Text(
                        'LOCAL DEV · ${widget.selected}'
                        '${kIsWeb ? ' · ?devUser=owner / ?devUser=recipient' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF60635F),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: NoteFlowApp(
                    authController: widget.controller,
                    currentUserSession: widget.session,
                    connection: connection,
                    enableLabels: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
