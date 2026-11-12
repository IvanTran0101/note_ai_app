import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/users/profile_app_service.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/users/profile_avatar_gateway.dart';
import 'package:note_ai_app/domain/users/profile_failure.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/domain/users/user_profile_repository.dart';
import 'package:note_ai_app/presentation/profile/profile_page.dart';

UserProfile _profile() => UserProfile.reconstitute(
  userId: 'profile43-account',
  displayName: 'Ada Lovelace',
  avatarReference: null,
  revision: 1,
);

CurrentUserSession _session() {
  final CurrentUserSession session = CurrentUserSession();
  session.setIdentity(
    AuthIdentity(
      userId: 'profile43-account',
      email: 'profile43@example.test',
      isEmailVerified: true,
    ),
  );
  return session;
}

final class _Repository implements IUserProfileRepository {
  _Repository({required this.profile, this.saveFailure});

  UserProfile? profile;
  final ProfileFailure? saveFailure;

  @override
  Future<UserProfile?> findByUserId(String userId) async => profile?.copy();

  @override
  Future<void> save(UserProfile candidate) async {
    final ProfileFailure? failure = saveFailure;
    if (failure != null) {
      throw failure;
    }
    profile = candidate.copy();
  }
}

final class _AvatarGateway implements IProfileAvatarGateway {
  @override
  Future<Uint8List?> getAvatar(String userId) async => null;

  @override
  Future<void> uploadAvatar({
    required String userId,
    required int expectedRevision,
    required Uint8List bytes,
    required String mime,
  }) async {}
}

final class _Harness {
  _Harness({ProfileFailure? saveFailure})
    : repository = _Repository(profile: _profile(), saveFailure: saveFailure),
      session = _session();

  final _Repository repository;
  final CurrentUserSession session;
  final _AvatarGateway avatarGateway = _AvatarGateway();

  late final ProfileAppService service = ProfileAppService(
    repository: repository,
    avatarGateway: avatarGateway,
    session: session,
  );
}

Future<void> _pumpProfile(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = const FakeViewPadding(bottom: 240);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        );
      },
      home: ProfilePage(
        service: harness.service,
        pickAvatar: () async => null,
        onChanged: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'compact profile remains scrollable above the keyboard at large text',
    (WidgetTester tester) async {
      final _Harness harness = _Harness();
      await _pumpProfile(tester, harness);

      final Rect avatar = tester.getRect(
        find.byKey(ProfilePageKeys.avatarPreview),
      );
      final Rect pickAvatar = tester.getRect(
        find.byKey(ProfilePageKeys.pickAvatar),
      );
      expect(pickAvatar.left, lessThan(avatar.right));
      expect(pickAvatar.top, greaterThan(avatar.bottom));

      final Finder name = find.byKey(ProfilePageKeys.nameField);
      await tester.scrollUntilVisible(
        name,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(name);
      await tester.showKeyboard(name);
      await tester.pump();

      final double keyboardTop =
          tester.view.physicalSize.height - tester.view.viewInsets.bottom;
      expect(tester.getRect(name).bottom, lessThanOrEqualTo(keyboardTop));

      final Finder save = find.byKey(ProfilePageKeys.saveName);
      await tester.ensureVisible(save);
      await tester.pump();
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact scaled error keeps its reload action below the message',
    (WidgetTester tester) async {
      final _Harness harness = _Harness(
        saveFailure: const ProfileFailure(ProfileFailureCode.conflict),
      );
      await _pumpProfile(tester, harness);

      final Finder name = find.byKey(ProfilePageKeys.nameField);
      await tester.scrollUntilVisible(
        name,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(name, 'Grace Hopper');
      final Finder save = find.byKey(ProfilePageKeys.saveName);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.pump();

      final Finder error = find.byKey(ProfilePageKeys.actionError);
      expect(error, findsOneWidget);
      final Finder message = find.text(
        'The profile changed on another device. Reload and try again.',
      );
      final Finder reload = find.text('Reload');
      expect(message, findsOneWidget);
      expect(reload, findsOneWidget);

      await tester.ensureVisible(error);
      await tester.pump();
      expect(
        tester.getRect(reload).top,
        greaterThanOrEqualTo(tester.getRect(message).bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
