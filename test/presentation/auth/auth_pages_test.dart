import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/presentation/auth/auth_pages.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';

void main() {
  testWidgets('login validates required fields before submitting', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );

    await tester.tap(find.byKey(LoginPage.submitKey));
    await tester.pump();

    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });

  testWidgets('register validates password confirmation', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(controller: controller)),
    );

    await tester.enterText(
      find.byKey(RegisterPage.displayNameFieldKey),
      'User',
    );
    await tester.enterText(
      find.byKey(RegisterPage.emailFieldKey),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(RegisterPage.passwordFieldKey),
      'password-1',
    );
    await tester.enterText(
      find.byKey(RegisterPage.confirmPasswordFieldKey),
      'password-2',
    );
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('forgot-password page exposes email and reset action', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordPage(controller: controller)),
    );

    expect(find.byKey(ForgotPasswordPage.emailFieldKey), findsOneWidget);
    expect(find.byKey(ForgotPasswordPage.submitKey), findsOneWidget);
    expect(find.text('Reset your password'), findsOneWidget);
  });

  testWidgets('verification banner is visible only for unverified users', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
      initialUser: testUser,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: EmailVerificationBanner(controller: controller)),
    );
    expect(find.byKey(EmailVerificationBanner.bannerKey), findsOneWidget);

    final AuthController verifiedController = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
      initialUser: verifiedUser,
    );
    addTearDown(verifiedController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EmailVerificationBanner(controller: verifiedController),
      ),
    );
    expect(find.byKey(EmailVerificationBanner.bannerKey), findsNothing);
  });

  testWidgets('change-password page renders its protected form', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
      initialUser: testUser,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ChangePasswordPage(controller: controller)),
    );

    expect(
      find.byKey(ChangePasswordPage.currentPasswordFieldKey),
      findsOneWidget,
    );
    expect(find.byKey(ChangePasswordPage.submitKey), findsOneWidget);
    expect(find.text('Change password'), findsAtLeastNWidgets(1));
  });
}

const AuthUserDto testUser = AuthUserDto(
  userId: 'user-1',
  email: 'user@example.com',
  isEmailVerified: false,
);

const AuthUserDto verifiedUser = AuthUserDto(
  userId: 'user-1',
  email: 'user@example.com',
  isEmailVerified: true,
);

final class _FakeAuthenticationAppService implements IAuthenticationAppService {
  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    throw UnimplementedError();
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {
    throw UnimplementedError();
  }

  @override
  Future<AuthUserDto?> restoreSession() async {
    throw UnimplementedError();
  }

  @override
  Stream<AuthUserDto?> observeAuthState() => const Stream<AuthUserDto?>.empty();

  @override
  Future<AuthUserDto> refreshIdentity() async {
    throw UnimplementedError();
  }

  @override
  Future<void> resendEmailVerification() async {
    throw UnimplementedError();
  }

  @override
  Future<AuthUserDto> confirmEmailVerification({required String code}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    throw UnimplementedError();
  }
}
