import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/presentation/auth/auth_pages.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/routing/app_router.dart';
import 'package:note_ai_app/presentation/routing/app_routes.dart';

void main() {
  testWidgets('cancelling recovery preserves the intended protected route', (
    tester,
  ) async {
    final controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    await controller.initialize();
    final router = createAppRouter(
      authController: controller,
      workspaceBuilder: (_) => const Text('Workspace'),
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    const intended = '/notes/note-1?tab=summary';
    for (final path in <String>[
      AppRoutes.forgotPassword,
      AppRoutes.resetPassword,
    ]) {
      router.go(
        Uri(
          path: path,
          queryParameters: const <String, String>{'redirect': intended},
        ).toString(),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Back to log in'));
      await tester.tap(find.text('Back to log in'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
      expect(
        router.routeInformationProvider.value.uri.queryParameters['redirect'],
        intended,
      );
    }
  });

  testWidgets(
    'protected route redirects to login and returns after successful login',
    (WidgetTester tester) async {
      final _FakeAuthenticationAppService service =
          _FakeAuthenticationAppService()..loginResult = verifiedUser;
      final AuthController controller = AuthController(
        authenticationAppService: service,
      );
      await controller.initialize();
      final router = createAppRouter(
        authController: controller,
        workspaceBuilder: (_) => const Text('Workspace'),
      );
      addTearDown(router.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/notes/note-1?tab=summary');
      await tester.pumpAndSettle();

      expect(find.byKey(LoginPage.submitKey), findsOneWidget);
      await tester.enterText(
        find.byKey(LoginPage.emailFieldKey),
        'user@example.com',
      );
      await tester.tap(find.byKey(LoginPage.submitKey));
      await tester.pumpAndSettle();
      expect(service.loginCalls, 0);

      await tester.enterText(
        find.byKey(LoginPage.passwordFieldKey),
        'password',
      );
      await tester.tap(find.byKey(LoginPage.submitKey));
      await tester.pumpAndSettle();

      expect(find.text('Workspace'), findsOneWidget);
      expect(service.loginCalls, 1);
    },
  );

  testWidgets('register auto-login returns to the protected workspace', (
    WidgetTester tester,
  ) async {
    final _FakeAuthenticationAppService service =
        _FakeAuthenticationAppService()
          ..registerResult = const RegistrationResult(
            user: unverifiedUser,
            verificationDispatchStatus: VerificationDispatchStatus.requested,
          );
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );
    await controller.initialize();
    final router = createAppRouter(
      authController: controller,
      workspaceBuilder: (_) => const Text('Workspace'),
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go(AppRoutes.register);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(RegisterPage.emailFieldKey),
      'user@example.com',
    );
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();
    expect(service.registerCalls, 0);

    await tester.enterText(
      find.byKey(RegisterPage.displayNameFieldKey),
      'User',
    );
    await tester.enterText(
      find.byKey(RegisterPage.passwordFieldKey),
      'Existing1!',
    );
    await tester.enterText(
      find.byKey(RegisterPage.confirmPasswordFieldKey),
      'Existing1!',
    );
    await tester.ensureVisible(find.byKey(RegisterPage.submitKey));
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsOneWidget);
    expect(service.registerCalls, 1);
  });

  testWidgets('forgot and reset password return to login', (
    WidgetTester tester,
  ) async {
    final _FakeAuthenticationAppService service =
        _FakeAuthenticationAppService();
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );
    await controller.initialize();
    final router = createAppRouter(
      authController: controller,
      workspaceBuilder: (_) => const Text('Workspace'),
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go(AppRoutes.forgotPassword);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ForgotPasswordPage.emailFieldKey),
      'user@example.com',
    );
    await tester.tap(find.byKey(ForgotPasswordPage.submitKey));
    await tester.pumpAndSettle();

    expect(find.byKey(ResetPasswordPage.codeFieldKey), findsOneWidget);
    await tester.enterText(
      find.byKey(ResetPasswordPage.codeFieldKey),
      '123456',
    );
    await tester.enterText(
      find.byKey(ResetPasswordPage.passwordFieldKey),
      'new-password',
    );
    await tester.enterText(
      find.byKey(ResetPasswordPage.confirmPasswordFieldKey),
      'new-password',
    );
    await tester.ensureVisible(find.byKey(ResetPasswordPage.submitKey));
    await tester.tap(find.byKey(ResetPasswordPage.submitKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LoginPage.submitKey), findsOneWidget);
    expect(service.passwordResetRequests, 1);
    expect(service.passwordResetConfirmations, 1);
    expect(
      find.text('Password reset. Log in with your new password.'),
      findsOneWidget,
    );
  });

  testWidgets('change password succeeds and logout returns to login', (
    WidgetTester tester,
  ) async {
    final _FakeAuthenticationAppService service =
        _FakeAuthenticationAppService();
    final AuthController controller = AuthController(
      authenticationAppService: service,
      initialUser: verifiedUser,
    );
    final router = createAppRouter(
      authController: controller,
      workspaceBuilder: (_) => const Text('Workspace'),
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go(AppRoutes.changePassword);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(ChangePasswordPage.currentPasswordFieldKey),
      'old-password',
    );
    await tester.enterText(
      find.byKey(ChangePasswordPage.passwordFieldKey),
      'new-password',
    );
    await tester.enterText(
      find.byKey(ChangePasswordPage.confirmPasswordFieldKey),
      'new-password',
    );
    await tester.ensureVisible(find.byKey(ChangePasswordPage.submitKey));
    await tester.tap(find.byKey(ChangePasswordPage.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('Password changed.'), findsOneWidget);
    expect(service.changePasswordCalls, 1);

    await controller.logout();
    await tester.pumpAndSettle();
    expect(find.byKey(LoginPage.submitKey), findsOneWidget);
  });

  testWidgets('a provider sign-out event redirects the workspace to login', (
    WidgetTester tester,
  ) async {
    final _FakeAuthenticationAppService service =
        _FakeAuthenticationAppService()..restoreResult = verifiedUser;
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );
    await controller.initialize();
    final router = createAppRouter(
      authController: controller,
      workspaceBuilder: (_) => const Text('Workspace'),
    );
    addTearDown(router.dispose);
    addTearDown(controller.dispose);
    addTearDown(service.authState.close);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('Workspace'), findsOneWidget);

    service.authState.add(null);
    await tester.pumpAndSettle();

    expect(find.byKey(LoginPage.submitKey), findsOneWidget);
    expect(find.text('Workspace'), findsNothing);
  });
}

const AuthUserDto verifiedUser = AuthUserDto(
  userId: 'user-1',
  email: 'user@example.com',
  isEmailVerified: true,
);

const AuthUserDto unverifiedUser = AuthUserDto(
  userId: 'user-1',
  email: 'user@example.com',
  isEmailVerified: false,
);

final class _FakeAuthenticationAppService implements IAuthenticationAppService {
  AuthUserDto? restoreResult;
  AuthUserDto loginResult = verifiedUser;
  RegistrationResult registerResult = const RegistrationResult(
    user: verifiedUser,
    verificationDispatchStatus: VerificationDispatchStatus.notRequired,
  );

  int loginCalls = 0;
  int registerCalls = 0;
  int passwordResetRequests = 0;
  int passwordResetConfirmations = 0;
  int changePasswordCalls = 0;

  /// Application auth-state events the fake replays to its observer.
  final StreamController<AuthUserDto?> authState =
      StreamController<AuthUserDto?>.broadcast();

  @override
  Stream<AuthUserDto?> observeAuthState() => authState.stream;

  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    registerCalls++;
    return registerResult;
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    loginCalls++;
    return loginResult;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUserDto?> restoreSession() async => restoreResult;

  @override
  Future<AuthUserDto> refreshIdentity() async => loginResult;

  @override
  Future<void> resendEmailVerification() async {}

  @override
  Future<AuthUserDto> confirmEmailVerification({required String code}) async {
    return verifiedUser;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    passwordResetRequests++;
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    passwordResetConfirmations++;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    changePasswordCalls++;
  }
}
