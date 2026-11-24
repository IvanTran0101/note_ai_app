import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:note_ai_app/domain/users/user_preferences.dart';
import 'package:note_ai_app/infrastructure/users/local_user_preferences_repository.dart';
import 'package:note_ai_app/infrastructure/sync/local_sync_store.dart' as local;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:note_ai_app/main.dart' as app;
import 'package:note_ai_app/application/auth/auth_models.dart';
import 'package:note_ai_app/presentation/auth/controllers/auth_state.dart';
import 'package:note_ai_app/presentation/profile/profile_page.dart';
import 'package:note_ai_app/presentation/routing/app_routes.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';
import 'package:note_ai_app/infrastructure/users/profile_avatar_picker.dart';
import 'package:note_ai_app/domain/users/profile_avatar_gateway.dart';

// Explicit opt-in; credentials stay in an owner-only runtime file, never in source/defines/logs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Native Cognito/profile/avatar cross-device slice', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/m01-runtime.json');
    for (var i = 0; i < 30 && !await file.exists(); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!await file.exists()) {
      throw StateError('M01 private runtime fixture is missing.');
    }
    final input = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    await app.main();
    await until(
      tester,
      () => find.byType(app.NoteFlowApp).evaluate().isNotEmpty,
    );
    final root = tester.widget<app.NoteFlowApp>(find.byType(app.NoteFlowApp));
    await until(
      tester,
      () => root.authController.state.status != AuthStatus.initializing,
    );
    if (!root.authController.state.isAuthenticated) {
      await tester.runAsync(
        () => root.authController.login(
          LoginInput(
            email: input['email'] as String,
            password: input['password'] as String,
          ),
        ),
      );
    }
    await until(
      tester,
      () => find.byType(WorkspaceShell).evaluate().isNotEmpty,
    );
    GoRouter.of(tester.element(find.byType(WorkspaceShell)))
        .go(AppRoutes.profile);
    await until(
      tester,
      () =>
          find.byType(ProfilePage).evaluate().isNotEmpty &&
          find.byKey(ProfilePageKeys.nameField).evaluate().isNotEmpty,
    );
    final page = tester.widget<ProfilePage>(find.byType(ProfilePage));
    final loaded = await tester.runAsync(page.service.load);
    expect(
      loaded?.profile?.displayName,
      isIn(['M01 Web Test', 'M01 Native Test']),
    );
    expect(loaded?.avatarBytes, isNotNull);
    final named = await tester.runAsync(
      () => page.service.saveName('M01 Native Test'),
    );
    page.onChanged(named!);
    final raw = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mO4IyICAALUAQVnjQBuAAAAAElFTkSuQmCC',
    );
    final bytes = await tester.runAsync(() => prepareProfileAvatarBytes(raw));
    final changed = await tester.runAsync(
      () => page.service.uploadAvatar(bytes!, ProfileAvatarRules.pngMime),
    );
    expect(changed?.profile?.displayName, 'M01 Native Test');
    expect(changed?.avatarBytes, isNotNull);
    page.onChanged(changed!);
    await tester.pump();
    final preferences = LocalUserPreferencesRepository(
      currentAccountUserId: () => root.currentUserSession.requiredUserId,
      sessionGeneration: () => root.currentUserSession.sessionGeneration,
      localSyncStoreFactory: local.createLocalSyncStore,
    );
    final saved =
        await tester.runAsync(
          () =>
              preferences.findByUserId(root.currentUserSession.requiredUserId),
        ) ??
        UserPreferences.create(
          userId: root.currentUserSession.requiredUserId,
          theme: AppThemePreference.system,
          noteFontSize: NoteFontSizePreference.medium,
        );
    saved.changeTheme(AppThemePreference.dark);
    await tester.runAsync(() => preferences.save(saved));
    await tester.pumpWidget(const SizedBox());
    await app.main();
    await until(
      tester,
      () => find.byType(app.NoteFlowApp).evaluate().isNotEmpty,
    );
    final restarted = tester.widget<app.NoteFlowApp>(
      find.byType(app.NoteFlowApp),
    );
    await until(
      tester,
      () => restarted.authController.state.status != AuthStatus.initializing,
    );
    expect(
      restarted.authController.state.isAuthenticated,
      isTrue,
      reason: 'SDK session restore after root recreation',
    );
    final reopened = LocalUserPreferencesRepository(
      currentAccountUserId: () => restarted.currentUserSession.requiredUserId,
      localSyncStoreFactory: local.createLocalSyncStore,
    );
    final persisted = await tester.runAsync(
      () => reopened.findByUserId(restarted.currentUserSession.requiredUserId),
    );
    expect(
      persisted?.theme,
      AppThemePreference.dark,
      reason: 'Fresh native repository reads persisted theme',
    );
    await until(
      tester,
      () =>
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode ==
          ThemeMode.dark,
    );
    binding.reportData = {
      'nativeThemeRootRecreation': true,
      'nativeCognitoLogin': true,
      'webProfileReadOnNative': true,
      'nativeNameAndAvatarWrite': true,
      'nativeThemeDiskWrite': true,
    };
  }, skip: !const bool.fromEnvironment('NOTEFLOW_M01_LIVE_TEST'));
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (ready()) return;
  }
  throw StateError('M01 Native UI did not reach its expected state.');
}
