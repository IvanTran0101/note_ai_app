import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/auth/auth_models.dart';
import '../notes/notes_theme_tokens.dart';
import '../routing/app_routes.dart';
import 'auth_localizations.dart';
import 'controllers/auth_controller.dart';
import 'controllers/auth_state.dart';

final class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.controller, this.redirect});

  static const Key emailFieldKey = ValueKey<String>('auth-login-email');
  static const Key passwordFieldKey = ValueKey<String>('auth-login-password');
  static const Key submitKey = ValueKey<String>('auth-login-submit');

  final AuthController controller;
  final String? redirect;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

final class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  bool _passwordStep = false;

  @override
  Widget build(BuildContext context) {
    final AuthCopy copy = AuthCopy.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = widget.controller.state;
        return _AuthFormScaffold(
          title: copy.loginTitle,
          subtitle: copy.loginSubtitle,
          compactTopPadding: 38,
          compactBrandTitleSpacing: 34,
          compactTitleSubtitleSpacing: 0,
          compactContentSpacing: NoteFlowSpacing.xl + NoteFlowSpacing.xs,
          desktopContentSpacing: NoteFlowSpacing.xl + NoteFlowSpacing.sm,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: LoginPage.emailFieldKey,
                  controller: _emailController,
                  focusNode: _emailFocusNode,
                  label: copy.email,
                  hintText: copy.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  readOnly: _passwordStep,
                  autofillHints: const <String>[AutofillHints.username],
                  validator: (String? value) =>
                      _required(value, copy.emailRequired),
                  onFieldSubmitted: _passwordStep
                      ? null
                      : (_) => _continueToPassword(),
                ),
                if (_passwordStep) ...<Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: state.isBusy ? null : _changeEmail,
                      child: Text(copy.changeEmail),
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  _authField(
                    key: LoginPage.passwordFieldKey,
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    label: copy.password,
                    hintText: copy.passwordHint,
                    obscureText: true,
                    autofillHints: const <String>[AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    validator: (String? value) =>
                        _required(value, copy.passwordRequired),
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: LoginPage.submitKey,
                  label: _passwordStep ? copy.loginAction : copy.continueAction,
                  busy: state.isBusy,
                  onPressed: _passwordStep ? _submit : _continueToPassword,
                ),
                if (_passwordStep)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: state.isBusy ? null : _openForgotPassword,
                      child: Text(copy.forgotPassword),
                    ),
                  ),
                const SizedBox(height: 12.0),
                _AuthLinkRow(
                  prompt: copy.newToNoteFlow,
                  action: copy.registerAction,
                  onPressed: state.isBusy ? null : _openRegister,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _continueToPassword() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _passwordStep = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _passwordFocusNode.requestFocus();
      }
    });
  }

  void _changeEmail() {
    _passwordController.clear();
    setState(() => _passwordStep = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _emailFocusNode.requestFocus();
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await widget.controller.login(
        LoginInput(
          email: _emailController.text,
          password: _passwordController.text,
        ),
      );
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  void _openRegister() {
    context.go(_withRedirect(AppRoutes.register));
  }

  void _openForgotPassword() {
    context.go(_withRedirect(AppRoutes.forgotPassword));
  }

  String _withRedirect(String path) {
    return Uri(
      path: path,
      queryParameters: widget.redirect == null
          ? null
          : <String, String>{'redirect': widget.redirect!},
    ).toString();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }
}

final class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, required this.controller, this.redirect});

  static const Key displayNameFieldKey = ValueKey<String>(
    'auth-register-display-name',
  );
  static const Key emailFieldKey = ValueKey<String>('auth-register-email');
  static const Key passwordFieldKey = ValueKey<String>(
    'auth-register-password',
  );
  static const Key confirmPasswordFieldKey = ValueKey<String>(
    'auth-register-confirm-password',
  );
  static const Key submitKey = ValueKey<String>('auth-register-submit');

  final AuthController controller;
  final String? redirect;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

final class _RegisterPageState extends State<RegisterPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _displayNameFocusNode = FocusNode();
  bool _detailsStep = false;

  @override
  Widget build(BuildContext context) {
    final AuthCopy copy = AuthCopy.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = widget.controller.state;
        return _AuthFormScaffold(
          title: copy.registerTitle,
          subtitle: copy.registerSubtitle,
          compactTopPadding: 76,
          desktopTopPadding: 32,
          compactBrandTitleSpacing: NoteFlowSpacing.xxl,
          compactTitleSubtitleSpacing: 0,
          compactContentSpacing: NoteFlowSpacing.xl,
          desktopContentSpacing: NoteFlowSpacing.xl + NoteFlowSpacing.sm,
          desktopPanel: true,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: RegisterPage.emailFieldKey,
                  controller: _emailController,
                  focusNode: _emailFocusNode,
                  label: copy.email,
                  hintText: copy.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  readOnly: _detailsStep,
                  textInputAction: _detailsStep
                      ? TextInputAction.done
                      : TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.username],
                  validator: (String? value) =>
                      _required(value, copy.emailRequired),
                  onFieldSubmitted: _detailsStep
                      ? null
                      : (_) => _continueToDetails(),
                ),
                if (_detailsStep) ...<Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: state.isBusy ? null : _changeEmail,
                      child: Text(copy.changeEmail),
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  _authField(
                    key: RegisterPage.displayNameFieldKey,
                    controller: _displayNameController,
                    focusNode: _displayNameFocusNode,
                    label: copy.displayName,
                    hintText: copy.displayNameHint,
                    textInputAction: TextInputAction.next,
                    validator: (String? value) =>
                        _required(value, copy.displayNameRequired),
                  ),
                  const SizedBox(height: 12.0),
                  _authField(
                    key: RegisterPage.passwordFieldKey,
                    controller: _passwordController,
                    label: copy.password,
                    hintText: copy.passwordHint,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    validator: (String? value) =>
                        _required(value, copy.passwordRequired),
                  ),
                  const SizedBox(height: 12.0),
                  _authField(
                    key: RegisterPage.confirmPasswordFieldKey,
                    controller: _confirmPasswordController,
                    label: copy.confirmPassword,
                    hintText: copy.confirmPasswordHint,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.newPassword],
                    validator: (String? value) {
                      final String? requiredError = _required(
                        value,
                        copy.passwordRequired,
                      );
                      if (requiredError != null) {
                        return requiredError;
                      }
                      return value == _passwordController.text
                          ? null
                          : copy.passwordConfirmationMismatch;
                    },
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: RegisterPage.submitKey,
                  label: _detailsStep
                      ? copy.registerAction
                      : copy.continueAction,
                  busy: state.isBusy,
                  onPressed: _detailsStep ? _submit : _continueToDetails,
                ),
                const SizedBox(height: 8.0),
                _AuthLinkRow(
                  prompt: copy.alreadyHaveAccount,
                  action: copy.loginAction,
                  onPressed: state.isBusy ? null : _openLogin,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _continueToDetails() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _detailsStep = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _displayNameFocusNode.requestFocus();
      }
    });
  }

  void _changeEmail() {
    _passwordController.clear();
    _confirmPasswordController.clear();
    setState(() => _detailsStep = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _emailFocusNode.requestFocus();
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await widget.controller.register(
        RegisterInput(
          email: _emailController.text,
          displayName: _displayNameController.text,
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        ),
      );
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  void _openLogin() {
    context.go(_withRedirect(AppRoutes.login));
  }

  String _withRedirect(String path) {
    return Uri(
      path: path,
      queryParameters: widget.redirect == null
          ? null
          : <String, String>{'redirect': widget.redirect!},
    ).toString();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailFocusNode.dispose();
    _displayNameFocusNode.dispose();
    super.dispose();
  }
}

final class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    required this.controller,
    this.redirect,
  });

  static const Key emailFieldKey = ValueKey<String>('auth-forgot-email');
  static const Key submitKey = ValueKey<String>('auth-forgot-submit');

  final AuthController controller;
  final String? redirect;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

final class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final AuthCopy copy = AuthCopy.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = widget.controller.state;
        return _AuthFormScaffold(
          title: copy.forgotTitle,
          subtitle: copy.forgotSubtitle,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: ForgotPasswordPage.emailFieldKey,
                  controller: _emailController,
                  label: copy.email,
                  hintText: copy.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.username],
                  validator: (String? value) =>
                      _required(value, copy.emailRequired),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: ForgotPasswordPage.submitKey,
                  label: copy.sendResetCode,
                  busy: state.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8.0),
                TextButton(
                  onPressed: state.isBusy
                      ? null
                      : () => context.go(AppRoutes.login),
                  child: Text(copy.backToLogin),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String email = _emailController.text.trim();
    try {
      await widget.controller.requestPasswordReset(email: email);
      if (!mounted) {
        return;
      }
      final Map<String, String> query = <String, String>{'email': email};
      final String? redirect = widget.redirect;
      if (redirect != null) {
        query['redirect'] = redirect;
      }
      context.go(
        Uri(path: AppRoutes.resetPassword, queryParameters: query).toString(),
      );
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}

final class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    super.key,
    required this.controller,
    this.initialEmail,
    this.redirect,
  });

  static const Key emailFieldKey = ValueKey<String>('auth-reset-email');
  static const Key codeFieldKey = ValueKey<String>('auth-reset-code');
  static const Key passwordFieldKey = ValueKey<String>('auth-reset-password');
  static const Key confirmPasswordFieldKey = ValueKey<String>(
    'auth-reset-confirm-password',
  );
  static const Key submitKey = ValueKey<String>('auth-reset-submit');

  final AuthController controller;
  final String? initialEmail;
  final String? redirect;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

final class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  Widget build(BuildContext context) {
    final AuthCopy copy = AuthCopy.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = widget.controller.state;
        return _AuthFormScaffold(
          title: copy.resetTitle,
          subtitle: copy.resetSubtitle,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: ResetPasswordPage.emailFieldKey,
                  controller: _emailController,
                  label: copy.email,
                  hintText: copy.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.emailRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: ResetPasswordPage.codeFieldKey,
                  controller: _codeController,
                  label: copy.verificationCode,
                  hintText: copy.verificationCodeHint,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.verificationCodeRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: ResetPasswordPage.passwordFieldKey,
                  controller: _passwordController,
                  label: copy.password,
                  hintText: copy.passwordHint,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.passwordRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: ResetPasswordPage.confirmPasswordFieldKey,
                  controller: _confirmPasswordController,
                  label: copy.confirmPassword,
                  hintText: copy.confirmPasswordHint,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  validator: (String? value) {
                    final String? requiredError = _required(
                      value,
                      copy.passwordRequired,
                    );
                    if (requiredError != null) {
                      return requiredError;
                    }
                    return value == _passwordController.text
                        ? null
                        : copy.passwordConfirmationMismatch;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: ResetPasswordPage.submitKey,
                  label: copy.resetPasswordAction,
                  busy: state.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8.0),
                TextButton(
                  onPressed: state.isBusy
                      ? null
                      : () => context.go(AppRoutes.login),
                  child: Text(copy.backToLogin),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await widget.controller.confirmPasswordReset(
        email: _emailController.text,
        code: _codeController.text,
        newPassword: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
      );
      if (!mounted) {
        return;
      }
      final String? redirect = widget.redirect;
      context.go(
        Uri(
          path: AppRoutes.login,
          queryParameters: redirect == null
              ? null
              : <String, String>{'redirect': redirect},
        ).toString(),
      );
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}

final class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.controller});

  static const Key codeFieldKey = ValueKey<String>('auth-verify-code');
  static const Key submitKey = ValueKey<String>('auth-verify-submit');

  final AuthController controller;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

final class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final AuthCopy copy = AuthCopy.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = widget.controller.state;
        if (!state.isAuthenticated) {
          return _AuthFormScaffold(
            title: copy.verifyEmailTitle,
            subtitle: copy.verifyEmailSubtitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(copy.loginToVerify),
                const SizedBox(height: 20.0),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.login),
                  child: Text(copy.loginAction),
                ),
              ],
            ),
          );
        }
        return _AuthFormScaffold(
          title: copy.verifyEmailTitle,
          subtitle: copy.verifyEmailSubtitle,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: VerifyEmailPage.codeFieldKey,
                  controller: _codeController,
                  label: copy.verificationCode,
                  hintText: copy.verificationCodeHint,
                  textInputAction: TextInputAction.done,
                  validator: (String? value) =>
                      _required(value, copy.verificationCodeRequired),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: VerifyEmailPage.submitKey,
                  label: copy.openVerification,
                  busy: state.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8.0),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    TextButton(
                      onPressed: state.isBusy ? null : _resend,
                      child: Text(copy.resendVerification),
                    ),
                    TextButton(
                      onPressed: state.isBusy ? null : _refresh,
                      child: Text(copy.refreshVerification),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      final AuthUserDto user = await widget.controller.confirmVerification(
        code: _codeController.text,
      );
      if (mounted && user.isEmailVerified) {
        context.go(AppRoutes.home);
      }
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  Future<void> _resend() async {
    try {
      await widget.controller.resendVerification();
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  Future<void> _refresh() async {
    try {
      final AuthUserDto user = await widget.controller.refreshIdentity();
      if (mounted && user.isEmailVerified) {
        context.go(AppRoutes.home);
      }
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

final class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.controller});

  static const Key currentPasswordFieldKey = ValueKey<String>(
    'auth-change-current-password',
  );
  static const Key passwordFieldKey = ValueKey<String>('auth-change-password');
  static const Key confirmPasswordFieldKey = ValueKey<String>(
    'auth-change-confirm-password',
  );
  static const Key submitKey = ValueKey<String>('auth-change-submit');

  final AuthController controller;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

final class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  Widget build(BuildContext context) {
    final AuthCopy copy = AuthCopy.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = widget.controller.state;
        return _AuthFormScaffold(
          title: copy.changePassword,
          subtitle: copy.changePasswordSubtitle,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: ChangePasswordPage.currentPasswordFieldKey,
                  controller: _currentPasswordController,
                  label: copy.currentPassword,
                  hintText: copy.currentPasswordHint,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.currentPasswordRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: ChangePasswordPage.passwordFieldKey,
                  controller: _passwordController,
                  label: copy.password,
                  hintText: copy.passwordHint,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.passwordRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: ChangePasswordPage.confirmPasswordFieldKey,
                  controller: _confirmPasswordController,
                  label: copy.confirmPassword,
                  hintText: copy.confirmPasswordHint,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  validator: (String? value) {
                    final String? requiredError = _required(
                      value,
                      copy.passwordRequired,
                    );
                    if (requiredError != null) {
                      return requiredError;
                    }
                    return value == _passwordController.text
                        ? null
                        : copy.passwordConfirmationMismatch;
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: ChangePasswordPage.submitKey,
                  label: copy.changePassword,
                  busy: state.isBusy,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8.0),
                TextButton(
                  onPressed: state.isBusy
                      ? null
                      : () => context.go(AppRoutes.home),
                  child: Text(copy.backToWorkspace),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await widget.controller.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthCopy.of(context).passwordChanged)),
        );
      }
    } on Object {
      // The controller publishes a safe error for the form to render.
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}

final class EmailVerificationBanner extends StatelessWidget {
  const EmailVerificationBanner({super.key, required this.controller});

  static const Key bannerKey = ValueKey<String>('email-verification-banner');
  static const Key resendKey = ValueKey<String>('email-verification-resend');
  static const Key refreshKey = ValueKey<String>('email-verification-refresh');

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final AuthState state = controller.state;
        if (!state.isAuthenticated || state.user?.isEmailVerified != false) {
          return const SizedBox.shrink();
        }
        final AuthCopy copy = AuthCopy.of(context);
        final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
        final String? error = copy.errorMessage(state.error);
        return Material(
          key: EmailVerificationBanner.bannerKey,
          color: tokens.subtleSurface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NoteFlowSpacing.lg,
              NoteFlowSpacing.md,
              NoteFlowSpacing.lg,
              NoteFlowSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.mark_email_unread_outlined,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: NoteFlowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        copy.verifyEmailBannerTitle,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(copy.verifyEmailBannerBody),
                      if (error != null)
                        Text(error, style: TextStyle(color: tokens.error)),
                      Wrap(
                        spacing: 4.0,
                        children: <Widget>[
                          TextButton(
                            key: EmailVerificationBanner.resendKey,
                            onPressed: state.isBusy ? null : () => _resend(),
                            child: Text(copy.resendVerification),
                          ),
                          TextButton(
                            key: EmailVerificationBanner.refreshKey,
                            onPressed: state.isBusy ? null : () => _refresh(),
                            child: Text(copy.refreshVerification),
                          ),
                          TextButton(
                            onPressed: state.isBusy
                                ? null
                                : () => context.go(AppRoutes.verifyEmail),
                            child: Text(copy.openVerification),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _resend() async {
    try {
      await controller.resendVerification();
    } on Object {
      // The controller publishes a safe error for the banner to render.
    }
  }

  Future<void> _refresh() async {
    try {
      await controller.refreshIdentity();
    } on Object {
      // The controller publishes a safe error for the banner to render.
    }
  }
}

final class _AuthFormScaffold extends StatelessWidget {
  const _AuthFormScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.compactTopPadding = 32,
    this.desktopTopPadding = 72,
    this.compactBrandTitleSpacing = 36,
    this.compactTitleSubtitleSpacing = NoteFlowSpacing.sm,
    this.compactContentSpacing = 32,
    this.desktopContentSpacing = 32,
    this.desktopPanel = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final double compactTopPadding;
  final double desktopTopPadding;
  final double compactBrandTitleSpacing;
  final double compactTitleSubtitleSpacing;
  final double compactContentSpacing;
  final double desktopContentSpacing;
  final bool desktopPanel;

  @override
  Widget build(BuildContext context) {
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    final ThemeData baseTheme = Theme.of(context);
    final ThemeData authTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: tokens.pageSurface,
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: tokens.pageSurface,
        isDense: true,
        hintStyle: baseTheme.textTheme.bodyMedium?.copyWith(
          color: tokens.textMuted,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NoteFlowSpacing.md,
          vertical: NoteFlowSpacing.sm + NoteFlowSpacing.xs,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.link,
          foregroundColor: tokens.pageSurface,
          disabledBackgroundColor: tokens.subtleSurface,
          disabledForegroundColor: tokens.textMuted,
          minimumSize: const Size(48.0, 44.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NoteFlowRadius.input),
          ),
        ),
      ),
    );

    return Theme(
      data: authTheme,
      child: Scaffold(
        backgroundColor: tokens.pageSurface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compactWidth = constraints.maxWidth < 600;
              final double topPadding = constraints.maxHeight < 600
                  ? 32
                  : compactWidth
                  ? compactTopPadding
                  : desktopTopPadding;
              final double brandTitleSpacing = compactWidth
                  ? compactBrandTitleSpacing
                  : NoteFlowSpacing.xxl;
              final double contentSpacing = compactWidth
                  ? compactContentSpacing
                  : desktopContentSpacing;
              final bool showDesktopPanel = desktopPanel && !compactWidth;
              const double bottomPadding = NoteFlowSpacing.xl;
              final double minScrollContentHeight =
                  (constraints.maxHeight - topPadding - bottomPadding)
                      .clamp(0.0, constraints.maxHeight)
                      .toDouble();
              final Widget formColumn = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.note_alt_outlined,
                          size: 25,
                          color: tokens.textPrimary,
                        ),
                        const SizedBox(width: NoteFlowSpacing.sm),
                        Text(
                          'NoteFlow',
                          style: baseTheme.textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: brandTitleSpacing),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: baseTheme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    SizedBox(
                      height: compactWidth ? compactTitleSubtitleSpacing : 0,
                    ),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: baseTheme.textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: tokens.textMuted,
                      ),
                    ),
                    SizedBox(height: contentSpacing),
                    child,
                  ],
                ),
              );
              final Widget pageContent = showDesktopPanel
                  ? SizedBox(
                      width: 496,
                      child: Container(
                        key: const ValueKey<String>(
                          'auth-register-desktop-panel',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 68,
                          vertical: 48,
                        ),
                        decoration: BoxDecoration(
                          color: tokens.elevatedSurface,
                          borderRadius: BorderRadius.circular(
                            NoteFlowRadius.dialog,
                          ),
                          border: Border.all(color: tokens.divider),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: formColumn,
                      ),
                    )
                  : formColumn;
              return ColoredBox(
                key: const ValueKey<String>('auth-form-page-background'),
                color: showDesktopPanel
                    ? tokens.sidebarSurface
                    : tokens.pageSurface,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    NoteFlowSpacing.xl,
                    topPadding,
                    NoteFlowSpacing.xl,
                    bottomPadding,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: minScrollContentHeight,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: pageContent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

final class _AuthErrorMessage extends StatelessWidget {
  const _AuthErrorMessage({required this.error});

  final AuthPresentationError? error;

  @override
  Widget build(BuildContext context) {
    final String? message = AuthCopy.of(context).errorMessage(error);
    if (message == null) {
      return const SizedBox.shrink();
    }
    final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: NoteFlowSpacing.lg),
      padding: const EdgeInsets.all(NoteFlowSpacing.md),
      decoration: BoxDecoration(
        color: tokens.subtleSurface,
        borderRadius: BorderRadius.circular(NoteFlowRadius.card),
        border: Border.all(color: tokens.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: tokens.error),
          const SizedBox(width: NoteFlowSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: tokens.error)),
          ),
        ],
      ),
    );
  }
}

final class _AuthLinkRow extends StatelessWidget {
  const _AuthLinkRow({
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Text(prompt),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    );
  }
}

Widget _authSubmitButton({
  required Key key,
  required String label,
  required bool busy,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: FilledButton(
      key: key,
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            )
          : Text(label),
    ),
  );
}

Widget _authField({
  required Key key,
  required TextEditingController controller,
  required String label,
  String? hintText,
  required String? Function(String?) validator,
  bool obscureText = false,
  bool readOnly = false,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  Iterable<String>? autofillHints,
  ValueChanged<String>? onFieldSubmitted,
  FocusNode? focusNode,
}) {
  return Builder(
    builder: (BuildContext context) {
      final NoteFlowUiTokens tokens = NoteFlowUiTokens.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: NoteFlowSpacing.sm),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Semantics(
            label: label,
            child: TextFormField(
              key: key,
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(hintText: hintText),
              obscureText: obscureText,
              readOnly: readOnly,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              onFieldSubmitted: onFieldSubmitted,
              validator: validator,
            ),
          ),
        ],
      );
    },
  );
}

String? _required(String? value, String message) {
  return value == null || value.trim().isEmpty ? message : null;
}
