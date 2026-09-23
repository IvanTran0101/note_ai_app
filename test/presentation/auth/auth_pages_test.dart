import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/application/auth/authentication_app_service.dart';
import 'package:note_ai_app/presentation/auth/auth_localizations.dart';
import 'package:note_ai_app/presentation/auth/auth_pages.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  testWidgets('login keeps a centered narrow form across desktop and phone', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    final SemanticsHandle semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1035, 737);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('NoteFlow'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Email\b')), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    semantics.dispose();
    expect(
      tester.getRect(find.byKey(LoginPage.emailFieldKey)).width,
      lessThanOrEqualTo(360),
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(393, 852);
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(LoginPage.emailFieldKey)).width,
      lessThanOrEqualTo(345),
    );
    expect(tester.getRect(find.text('NoteFlow')).top, inInclusiveRange(36, 48));
    expect(
      tester.getRect(find.text('Welcome back')).top,
      inInclusiveRange(92, 104),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AuthCopy.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: LoginPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chào mừng trở lại'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('auth fields use page labels and preserve field semantics', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    final Rect labelRect = tester.getRect(find.text('Email'));
    final Rect fieldRect = tester.getRect(find.byKey(LoginPage.emailFieldKey));
    final TextField field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(LoginPage.emailFieldKey),
        matching: find.byType(TextField),
      ),
    );

    expect(labelRect.bottom, lessThanOrEqualTo(fieldRect.top));
    expect(field.decoration?.hintText, 'Enter your email address');
    expect(find.bySemanticsLabel(RegExp(r'^Email\b')), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth form uses dark surface and accent tokens', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.dark();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: <ThemeExtension<dynamic>>[tokens],
        ),
        home: LoginPage(controller: controller),
      ),
    );

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, tokens.pageSurface);
    final BuildContext submitContext = tester.element(
      find.byKey(LoginPage.submitKey),
    );
    expect(
      Theme.of(submitContext).filledButtonTheme.style?.backgroundColor
          ?.resolve(const <WidgetState>{}),
      tokens.link,
    );
    expect(
      Theme.of(submitContext).inputDecorationTheme.fillColor,
      tokens.pageSurface,
    );
  });

  testWidgets(
    'register starts with email and aligns its desktop panel with Notion',
    (WidgetTester tester) async {
      final AuthController controller = AuthController(
        authenticationAppService: _FakeAuthenticationAppService(),
      );
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(home: RegisterPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('NoteFlow')).top,
        inInclusiveRange(70, 90),
      );
      expect(
        find.byKey(const ValueKey<String>('auth-register-desktop-panel')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpWidget(
        MaterialApp(home: RegisterPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.text('NoteFlow')).top,
        inInclusiveRange(80, 100),
      );
      final Finder desktopPanel = find.byKey(
        const ValueKey<String>('auth-register-desktop-panel'),
      );
      expect(desktopPanel, findsOneWidget);
      expect(tester.getRect(desktopPanel).width, 496);
      expect(tester.getRect(desktopPanel).top, inInclusiveRange(28, 36));
      expect(
        tester.getRect(find.byKey(RegisterPage.emailFieldKey)).width,
        inInclusiveRange(356, 360),
      );
      expect(
        tester.getRect(find.byKey(RegisterPage.emailFieldKey)).top,
        lessThan(
          tester.getRect(find.byKey(RegisterPage.displayNameFieldKey)).top,
        ),
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(768, 1024);
      await tester.pumpWidget(
        MaterialApp(home: RegisterPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(desktopPanel, findsOneWidget);
      expect(tester.getRect(desktopPanel).width, 496);
      expect(tester.takeException(), isNull);
    },
  );

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
