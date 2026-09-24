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

    final Rect phoneEmailRect = tester.getRect(
      find.byKey(LoginPage.emailFieldKey),
    );
    expect(phoneEmailRect.width, inInclusiveRange(351, 355));
    expect(phoneEmailRect.left, inInclusiveRange(19, 21));
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

  testWidgets('login registration link sits low without hiding Continue', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    final Rect continueRect = tester.getRect(find.byKey(LoginPage.submitKey));
    final Rect registerLinkRect = tester.getRect(find.text('Create account'));
    expect(continueRect.top, inInclusiveRange(300, 400));
    expect(registerLinkRect.top, inInclusiveRange(690, 714));
    expect(registerLinkRect.top - continueRect.bottom, greaterThan(240));
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(LoginPage.submitKey)).bottom,
      lessThan(844 - 320),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login validates email before showing the password step', (
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
    expect(
      find.text(
        'Use an email you can access to sign in or recover your account.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(LoginPage.passwordFieldKey), findsNothing);
    expect(controller.state.isBusy, isFalse);

    await tester.enterText(
      find.byKey(LoginPage.emailFieldKey),
      'user@example.com',
    );
    await tester.tap(find.byKey(LoginPage.submitKey));
    await tester.pumpAndSettle();

    expect(find.byKey(LoginPage.passwordFieldKey), findsOneWidget);
    expect(
      find.text(
        'Use an email you can access to sign in or recover your account.',
      ),
      findsNothing,
    );
    expect(find.text('Password is required.'), findsNothing);
    expect(controller.state.isBusy, isFalse);
  });

  testWidgets('login sends the existing email/password input after step two', (
    WidgetTester tester,
  ) async {
    final _FakeAuthenticationAppService service =
        _FakeAuthenticationAppService();
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(controller: controller)),
    );
    await tester.enterText(
      find.byKey(LoginPage.emailFieldKey),
      'user@example.com',
    );
    await tester.tap(find.byKey(LoginPage.submitKey));
    await tester.pumpAndSettle();

    expect(service.loginCalls, 0);
    await tester.enterText(
      find.byKey(LoginPage.passwordFieldKey),
      'existing-password',
    );
    await tester.tap(find.byKey(LoginPage.submitKey));
    await tester.pumpAndSettle();

    expect(service.loginCalls, 1);
    expect(service.lastLoginInput?.email, 'user@example.com');
    expect(service.lastLoginInput?.password, 'existing-password');
  });

  testWidgets(
    'register calls the existing service only after its details step',
    (WidgetTester tester) async {
      final _FakeAuthenticationAppService service =
          _FakeAuthenticationAppService();
      final AuthController controller = AuthController(
        authenticationAppService: service,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: RegisterPage(controller: controller)),
      );
      expect(find.byKey(RegisterPage.displayNameFieldKey), findsNothing);
      expect(
        find.text('You will need access to this email to verify your account.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(RegisterPage.emailFieldKey),
        'user@example.com',
      );
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      expect(service.registerCalls, 0);
      expect(find.byKey(RegisterPage.displayNameFieldKey), findsOneWidget);
      expect(
        find.text('You will need access to this email to verify your account.'),
        findsNothing,
      );
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      expect(service.registerCalls, 1);
      expect(service.lastRegisterInput?.email, 'user@example.com');
      expect(service.lastRegisterInput?.displayName, 'User');
      expect(service.lastRegisterInput?.password, 'Existing1!');
      expect(service.lastRegisterInput?.confirmPassword, 'Existing1!');
    },
  );

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

  testWidgets('auth page background fills supported viewports', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const List<Size> viewports = <Size>[
      Size(360, 800),
      Size(393, 852),
      Size(768, 1024),
      Size(1280, 550),
      Size(1280, 800),
      Size(1440, 900),
    ];
    final List<Widget> pages = <Widget>[
      LoginPage(controller: controller),
      RegisterPage(controller: controller),
    ];
    for (final Size viewport in viewports) {
      tester.view.physicalSize = viewport;
      for (final Widget page in pages) {
        await tester.pumpWidget(MaterialApp(home: page));
        await tester.pumpAndSettle();

        final Finder background = find.byKey(
          const ValueKey<String>('auth-form-page-background'),
        );
        expect(background, findsOneWidget);
        expect(tester.getSize(background), viewport);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('register email step preserves order and CTA reachability', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    final ThemeData theme = ThemeData(useMaterial3: true);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RegisterPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('NoteFlow')).top, inInclusiveRange(74, 86));
    final Rect mobileHeading = tester.getRect(find.text('Create your account'));
    final Rect mobileEmailLabel = tester.getRect(find.text('Email'));
    final Rect mobileEmailField = tester.getRect(
      find.byKey(RegisterPage.emailFieldKey),
    );
    final Rect mobileHint = tester.getRect(
      find.text('You will need access to this email to verify your account.'),
    );
    final Rect mobileSubmit = tester.getRect(
      find.byKey(RegisterPage.submitKey),
    );
    expect(mobileEmailLabel.top, greaterThan(mobileHeading.bottom));
    expect(mobileEmailField.top, greaterThan(mobileEmailLabel.bottom));
    expect(mobileHint.top, greaterThan(mobileEmailField.bottom));
    expect(mobileSubmit.top, greaterThan(mobileHint.bottom));
    expect(mobileSubmit.bottom, lessThan(844));
    expect(tester.getRect(find.text('Email')).left, inInclusiveRange(19, 21));
    expect(mobileEmailField.width, inInclusiveRange(348, 352));
    expect(
      tester.getSize(find.byKey(RegisterPage.submitKey)).height,
      inInclusiveRange(46, 50),
    );
    expect(
      find.byKey(const ValueKey<String>('auth-register-desktop-panel')),
      findsNothing,
    );
    expect(find.byKey(RegisterPage.displayNameFieldKey), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RegisterPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('NoteFlow')).top, greaterThan(0));
    final Finder desktopPanel = find.byKey(
      const ValueKey<String>('auth-register-desktop-panel'),
    );
    expect(desktopPanel, findsOneWidget);
    expect(tester.getRect(desktopPanel).width, 496);
    expect(
      tester.getRect(find.byKey(RegisterPage.submitKey)).bottom,
      lessThanOrEqualTo(tester.getRect(desktopPanel).bottom),
    );

    await tester.enterText(
      find.byKey(RegisterPage.emailFieldKey),
      'user@example.com',
    );
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();

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
      MaterialApp(
        theme: theme,
        home: RegisterPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(desktopPanel, findsOneWidget);
    expect(tester.getRect(desktopPanel).width, 496);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register login link matches the mobile signup anchor', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    final Rect continueRect = tester.getRect(
      find.byKey(RegisterPage.submitKey),
    );
    final Rect loginLinkRect = tester.getRect(find.text('Log in'));
    expect(continueRect.bottom, lessThan(844));
    expect(loginLinkRect.center.dy, inInclusiveRange(598, 618));
    expect(loginLinkRect.top - continueRect.bottom, greaterThan(64));
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(RegisterPage.submitKey)).bottom,
      lessThan(844 - 320),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('register details keep Create account clear of the footer', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(controller: controller)),
    );
    await tester.enterText(
      find.byKey(RegisterPage.emailFieldKey),
      'qa.noteflow@example.test',
    );
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();

    final Rect createAccountRect = tester.getRect(
      find.byKey(RegisterPage.submitKey),
    );
    final Rect loginLinkRect = tester.getRect(find.text('Log in'));
    expect(createAccountRect.height, greaterThanOrEqualTo(48));
    expect(createAccountRect.bottom, lessThan(844));
    expect(loginLinkRect.top - createAccountRect.bottom, greaterThan(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'login and register remain reachable at 200% text scale on a small phone',
    (WidgetTester tester) async {
      final AuthController controller = AuthController(
        authenticationAppService: _FakeAuthenticationAppService(),
      );
      addTearDown(controller.dispose);
      tester.view
        ..physicalSize = const Size(360, 800)
        ..devicePixelRatio = 1.0;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      final List<Widget> pages = <Widget>[
        LoginPage(controller: controller),
        RegisterPage(controller: controller),
      ];
      for (final Widget page in pages) {
        await tester.pumpWidget(MaterialApp(home: page));
        await tester.pumpAndSettle();

        final Finder submit = find.byKey(
          page is LoginPage ? LoginPage.submitKey : RegisterPage.submitKey,
        );
        expect(submit, findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        final Rect submitBounds = tester.getRect(submit);
        expect(submitBounds.top, greaterThanOrEqualTo(0));
        expect(submitBounds.bottom, lessThanOrEqualTo(800));
        expect(tester.takeException(), isNull);

        final Key emailKey = page is LoginPage
            ? LoginPage.emailFieldKey
            : RegisterPage.emailFieldKey;
        await tester.enterText(find.byKey(emailKey), 'user@example.com');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        final Rect nextStepSubmitBounds = tester.getRect(submit);
        expect(nextStepSubmitBounds.top, greaterThanOrEqualTo(0));
        expect(nextStepSubmitBounds.bottom, lessThanOrEqualTo(800));
        expect(tester.takeException(), isNull);
      }
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
      find.byKey(RegisterPage.emailFieldKey),
      'user@example.com',
    );
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(RegisterPage.displayNameFieldKey),
      'User',
    );
    await tester.enterText(
      find.byKey(RegisterPage.passwordFieldKey),
      'Password-1!',
    );
    await tester.enterText(
      find.byKey(RegisterPage.confirmPasswordFieldKey),
      'Password-2!',
    );
    await tester.ensureVisible(find.byKey(RegisterPage.submitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RegisterPage.submitKey));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('register shows only unmet password requirements as it changes', (
    WidgetTester tester,
  ) async {
    final _FakeAuthenticationAppService service =
        _FakeAuthenticationAppService();
    final AuthController controller = AuthController(
      authenticationAppService: service,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RegisterPage(controller: controller)),
    );
    await _advanceRegistrationToDetails(tester);

    expect(find.byKey(RegisterPage.passwordRequirementsKey), findsOneWidget);
    expect(
      find.text('Password must contain at least 8 characters.'),
      findsNothing,
    );

    await tester.enterText(find.byKey(RegisterPage.passwordFieldKey), 'abc');
    await tester.pumpAndSettle();
    expect(
      find.text('Password must contain at least 8 characters.'),
      findsOneWidget,
    );
    expect(
      find.text('Password must contain an uppercase letter.'),
      findsOneWidget,
    );
    expect(
      find.text('Password must contain a lowercase letter.'),
      findsNothing,
    );
    expect(find.text('Password must contain a number.'), findsOneWidget);
    expect(
      find.text('Password must contain a special character.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Password must contain an uppercase letter.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(RegisterPage.passwordFieldKey),
      'Abcdefg1',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Password must contain at least 8 characters.'),
      findsNothing,
    );
    expect(
      find.text('Password must contain an uppercase letter.'),
      findsNothing,
    );
    expect(
      find.text('Password must contain a lowercase letter.'),
      findsNothing,
    );
    expect(find.text('Password must contain a number.'), findsNothing);
    expect(
      find.text('Password must contain a special character.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(RegisterPage.passwordFieldKey),
      'Abcdefg1!',
    );
    await tester.pumpAndSettle();
    expect(find.text('Password meets all requirements.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Password meets all requirements.'),
      findsOneWidget,
    );
    expect(
      find.text('Password must contain a special character.'),
      findsNothing,
    );
    expect(service.registerCalls, 0);
  });

  testWidgets('register password guidance follows the selected locale', (
    WidgetTester tester,
  ) async {
    final AuthController controller = AuthController(
      authenticationAppService: _FakeAuthenticationAppService(),
    );
    addTearDown(controller.dispose);

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
        home: RegisterPage(controller: controller),
      ),
    );
    await _advanceRegistrationToDetails(tester);
    await tester.enterText(find.byKey(RegisterPage.passwordFieldKey), 'abc');
    await tester.pumpAndSettle();

    expect(find.text('Mật khẩu phải có ít nhất 8 ký tự.'), findsOneWidget);
    expect(find.text('Mật khẩu phải có ít nhất một chữ hoa.'), findsOneWidget);
    expect(find.text('Mật khẩu phải có ít nhất một chữ số.'), findsOneWidget);
    expect(find.text('Mật khẩu phải có ký tự đặc biệt.'), findsOneWidget);
    expect(find.text('Mật khẩu phải có ít nhất một chữ thường.'), findsNothing);
  });

  testWidgets(
    'register does not submit while password requirements are missing',
    (WidgetTester tester) async {
      final _FakeAuthenticationAppService service =
          _FakeAuthenticationAppService();
      final AuthController controller = AuthController(
        authenticationAppService: service,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: RegisterPage(controller: controller)),
      );
      await _advanceRegistrationToDetails(tester);
      await tester.enterText(
        find.byKey(RegisterPage.displayNameFieldKey),
        'User',
      );
      await tester.enterText(find.byKey(RegisterPage.passwordFieldKey), 'abc');
      await tester.enterText(
        find.byKey(RegisterPage.confirmPasswordFieldKey),
        'abc',
      );
      await tester.ensureVisible(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RegisterPage.submitKey));
      await tester.pumpAndSettle();

      expect(service.registerCalls, 0);
      expect(
        find.text('Password must contain at least 8 characters.'),
        findsWidgets,
      );
      expect(
        find.text('Password must contain an uppercase letter.'),
        findsWidgets,
      );
    },
  );

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

Future<void> _advanceRegistrationToDetails(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(RegisterPage.emailFieldKey),
    'user@example.com',
  );
  await tester.tap(find.byKey(RegisterPage.submitKey));
  await tester.pumpAndSettle();
}

final class _FakeAuthenticationAppService implements IAuthenticationAppService {
  int loginCalls = 0;
  int registerCalls = 0;
  LoginInput? lastLoginInput;
  RegisterInput? lastRegisterInput;

  @override
  Future<RegistrationResult> register(RegisterInput input) async {
    registerCalls++;
    lastRegisterInput = input;
    return const RegistrationResult(
      user: testUser,
      verificationDispatchStatus: VerificationDispatchStatus.notRequired,
    );
  }

  @override
  Future<AuthUserDto> login(LoginInput input) async {
    loginCalls++;
    lastLoginInput = input;
    return testUser;
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
