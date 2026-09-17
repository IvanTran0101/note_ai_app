import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/auth/auth_models.dart';
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: LoginPage.emailFieldKey,
                  controller: _emailController,
                  label: copy.email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.username],
                  validator: (String? value) =>
                      _required(value, copy.emailRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: LoginPage.passwordFieldKey,
                  controller: _passwordController,
                  label: copy.password,
                  obscureText: true,
                  autofillHints: const <String>[AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  validator: (String? value) =>
                      _required(value, copy.passwordRequired),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: LoginPage.submitKey,
                  label: copy.loginAction,
                  busy: state.isBusy,
                  onPressed: _submit,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: state.isBusy ? null : _openForgotPassword,
                    child: Text(copy.forgotPassword),
                  ),
                ),
                const Divider(height: 24.0),
                _AuthLinkRow(
                  prompt: copy.createAccount,
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _AuthErrorMessage(error: state.error),
                _authField(
                  key: RegisterPage.displayNameFieldKey,
                  controller: _displayNameController,
                  label: copy.displayName,
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.displayNameRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: RegisterPage.emailFieldKey,
                  controller: _emailController,
                  label: copy.email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.username],
                  validator: (String? value) =>
                      _required(value, copy.emailRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: RegisterPage.passwordFieldKey,
                  controller: _passwordController,
                  label: copy.password,
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
                const SizedBox(height: 20.0),
                _authSubmitButton(
                  key: RegisterPage.submitKey,
                  label: copy.registerAction,
                  busy: state.isBusy,
                  onPressed: _submit,
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
                  textInputAction: TextInputAction.next,
                  validator: (String? value) =>
                      _required(value, copy.verificationCodeRequired),
                ),
                const SizedBox(height: 12.0),
                _authField(
                  key: ResetPasswordPage.passwordFieldKey,
                  controller: _passwordController,
                  label: copy.password,
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

final class _AuthFormScaffold extends StatelessWidget {
  const _AuthFormScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440.0),
              child: Card(
                color: colors.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24.0),
                      child,
                    ],
                  ),
                ),
              ),
            ),
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
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
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
  required String? Function(String?) validator,
  bool obscureText = false,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  Iterable<String>? autofillHints,
  ValueChanged<String>? onFieldSubmitted,
}) {
  return TextFormField(
    key: key,
    controller: controller,
    decoration: InputDecoration(labelText: label),
    obscureText: obscureText,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    autofillHints: autofillHints,
    validator: validator,
  );
}

String? _required(String? value, String message) {
  return value == null || value.trim().isEmpty ? message : null;
}
