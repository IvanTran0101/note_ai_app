import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_state.dart';
import 'package:note_ai_app/presentation/routing/app_router.dart';
import 'package:note_ai_app/presentation/routing/app_routes.dart';

void main() {
  test('initializing state stays on splash', () {
    expect(
      redirectForAuth(
        state: const AuthState.initializing(),
        uri: Uri.parse(AppRoutes.home),
      ),
      AppRoutes.splash,
    );
    expect(
      redirectForAuth(
        state: const AuthState.initializing(),
        uri: Uri.parse(AppRoutes.splash),
      ),
      isNull,
    );
  });

  test('unauthenticated protected route preserves intended route', () {
    final String? result = redirectForAuth(
      state: const AuthState.unauthenticated(),
      uri: Uri.parse('/notes/note-1?tab=summary'),
    );

    final Uri redirect = Uri.parse(result!);
    expect(redirect.path, AppRoutes.login);
    expect(redirect.queryParameters['redirect'], '/notes/note-1?tab=summary');
  });

  test('profile is protected and keeps a safe login redirect', () {
    final result = redirectForAuth(
      state: const AuthState.unauthenticated(),
      uri: Uri.parse(AppRoutes.profile),
    );
    final redirect = Uri.parse(result!);
    expect(redirect.path, AppRoutes.login);
    expect(redirect.queryParameters['redirect'], AppRoutes.profile);
    expect(
      redirectForAuth(
        state: AuthState.authenticated(user: testUser),
        uri: Uri.parse(AppRoutes.profile),
      ),
      isNull,
    );
  });

  test('unauthenticated public route is allowed', () {
    expect(
      redirectForAuth(
        state: const AuthState.unauthenticated(),
        uri: Uri.parse(AppRoutes.forgotPassword),
      ),
      isNull,
    );
  });

  test('authenticated user returns from login to a safe intended route', () {
    final String? result = redirectForAuth(
      state: AuthState.authenticated(user: testUser),
      uri: Uri.parse('/login?redirect=%2Fnotes%2Fnote-1'),
    );

    expect(result, '/notes/note-1');
  });

  test('authenticated user falls back home for an external redirect', () {
    final String? result = redirectForAuth(
      state: AuthState.authenticated(user: testUser),
      uri: Uri.parse('/login?redirect=https%3A%2F%2Fevil.example'),
    );

    expect(result, AppRoutes.home);
  });

  test('authenticated user can open the verification route', () {
    expect(
      redirectForAuth(
        state: AuthState.authenticated(user: testUser),
        uri: Uri.parse(AppRoutes.verifyEmail),
      ),
      isNull,
    );
  });

  test('authenticated user leaves splash for the workspace', () {
    expect(
      redirectForAuth(
        state: AuthState.authenticated(user: testUser),
        uri: Uri.parse(AppRoutes.splash),
      ),
      AppRoutes.home,
    );
  });
}

const AuthUserDto testUser = AuthUserDto(
  userId: 'user-1',
  email: 'user@example.com',
  isEmailVerified: false,
);
