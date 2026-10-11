import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_pages.dart';
import '../auth/auth_localizations.dart';
import '../notes/notes_theme_tokens.dart';
import '../auth/controllers/auth_controller.dart';
import '../auth/controllers/auth_state.dart';
import 'app_routes.dart';

typedef AppWorkspaceBuilder = Widget Function(BuildContext context);

/// Creates the single application router over the shared auth controller.
GoRouter createAppRouter({
  required AuthController authController,
  required AppWorkspaceBuilder workspaceBuilder,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: authController,
    redirect: (BuildContext context, GoRouterState state) {
      return redirectForAuth(state: authController.state, uri: state.uri);
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        builder: (BuildContext context, GoRouterState state) {
          return _AuthStartupPage(controller: authController);
        },
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (BuildContext context, GoRouterState state) {
          return LoginPage(
            controller: authController,
            passwordResetComplete:
                state.extra == AuthRouteNotice.passwordResetComplete,
            redirect: state.uri.queryParameters['redirect'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (BuildContext context, GoRouterState state) {
          return RegisterPage(
            controller: authController,
            redirect: state.uri.queryParameters['redirect'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (BuildContext context, GoRouterState state) {
          return ForgotPasswordPage(
            controller: authController,
            redirect: state.uri.queryParameters['redirect'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (BuildContext context, GoRouterState state) {
          return ResetPasswordPage(
            controller: authController,
            initialEmail: state.uri.queryParameters['email'],
            redirect: state.uri.queryParameters['redirect'],
          );
        },
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (BuildContext context, GoRouterState state) {
          return VerifyEmailPage(controller: authController);
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (BuildContext context, GoRouterState state) {
          return workspaceBuilder(context);
        },
      ),
      GoRoute(
        path: AppRoutes.notes,
        builder: (BuildContext context, GoRouterState state) {
          return workspaceBuilder(context);
        },
      ),
      GoRoute(
        path: AppRoutes.noteDetails,
        builder: (BuildContext context, GoRouterState state) {
          return workspaceBuilder(context);
        },
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (BuildContext context, GoRouterState state) {
          return ChangePasswordPage(controller: authController);
        },
      ),
    ],
  );
}

/// Pure route-guard policy, kept separate so it can be tested without a
/// running Navigator or provider connection.
String? redirectForAuth({required AuthState state, required Uri uri}) {
  final String path = uri.path;
  if (state.status == AuthStatus.initializing) {
    return path == AppRoutes.splash ? null : AppRoutes.splash;
  }

  if (path == AppRoutes.splash) {
    return state.isAuthenticated ? AppRoutes.home : AppRoutes.login;
  }

  if (!state.isAuthenticated && _isProtectedPath(path)) {
    final String? target = _safeProtectedTarget(uri);
    final Uri login = Uri(
      path: AppRoutes.login,
      queryParameters: target == null
          ? null
          : <String, String>{'redirect': target},
    );
    return login.toString();
  }

  if (state.isAuthenticated && _guestOnlyRoutes.contains(path)) {
    return _safeIntendedRoute(uri.queryParameters['redirect']) ??
        AppRoutes.home;
  }

  return null;
}

const Set<String> _guestOnlyRoutes = <String>{
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.forgotPassword,
  AppRoutes.resetPassword,
};

bool _isProtectedPath(String path) {
  return path == AppRoutes.home ||
      path == AppRoutes.notes ||
      path.startsWith('/notes/') ||
      path == AppRoutes.changePassword;
}

String? _safeProtectedTarget(Uri uri) {
  return _isProtectedPath(uri.path) ? uri.toString() : null;
}

String? _safeIntendedRoute(String? rawRoute) {
  if (rawRoute == null || rawRoute.isEmpty) {
    return null;
  }
  final Uri? candidate = Uri.tryParse(rawRoute);
  if (candidate == null ||
      candidate.hasScheme ||
      candidate.hasAuthority ||
      candidate.path.startsWith('//') ||
      !_isProtectedPath(candidate.path)) {
    return null;
  }
  return candidate.toString();
}

final class _AuthStartupPage extends StatelessWidget {
  const _AuthStartupPage({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? child) {
          final AuthState state = controller.state;
          final AuthPresentationError? error = state.error;
          final copy = AuthCopy.of(context);
          final tokens = NoteFlowUiTokens.of(context);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(NoteFlowSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.note_alt_outlined,
                        size: 32,
                        color: tokens.textPrimary,
                      ),
                      const SizedBox(height: NoteFlowSpacing.md),
                      Text(
                        'NoteFlow',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: NoteFlowSpacing.xl),
                      if (error == null) ...<Widget>[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: MediaQuery.disableAnimationsOf(context)
                              ? Icon(
                                  Icons.hourglass_top,
                                  color: tokens.textSecondary,
                                )
                              : CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: tokens.link,
                                ),
                        ),
                        const SizedBox(height: NoteFlowSpacing.lg),
                        Text(
                          copy.restoringSession,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: tokens.textSecondary),
                        ),
                      ] else ...<Widget>[
                        Icon(Icons.error_outline, color: tokens.error),
                        const SizedBox(height: NoteFlowSpacing.sm),
                        Text(
                          copy.sessionRestoreFailed,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: NoteFlowSpacing.lg),
                        FilledButton(
                          onPressed: state.isBusy
                              ? null
                              : () => unawaited(_retry()),
                          child: Text(copy.retry),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _retry() async {
    try {
      await controller.initialize();
    } on Object {
      // AuthController already exposes the safe mapped error in state.
    }
  }
}
