import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/main.dart';
import 'package:note_ai_app/presentation/auth/auth_pages.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

void main() {
  for (final verified in [false, true]) {
    testWidgets('workspace respects top inset when verified is $verified', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 48);
      addTearDown(tester.view.reset);

      final identity = AuthIdentity(
        userId: 'test-user',
        email: 'test@example.com',
        isEmailVerified: verified,
      );
      final session = CurrentUserSession()..setIdentity(identity);
      final controller = AuthController(
        authenticationAppService: null,
        initialUser: AuthUserDto.fromIdentity(identity),
      );
      await tester.pumpWidget(
        NoteFlowApp(authController: controller, currentUserSession: session),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final banner = find.byKey(EmailVerificationBanner.bannerKey);
      final shell = find.byType(WorkspaceShell);
      expect(shell, findsOneWidget);
      if (verified) {
        expect(banner, findsNothing);
        expect(tester.getTopLeft(shell).dy, 48);
      } else {
        expect(banner, findsOneWidget);
        expect(tester.getTopLeft(banner).dy, 48);
        expect(tester.getTopLeft(shell).dy, tester.getBottomLeft(banner).dy);
      }
    });
  }
}
