import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/users/profile_app_service.dart';
import 'package:note_ai_app/application/users/profile_snapshot.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/users/profile_avatar_gateway.dart';
import 'package:note_ai_app/domain/users/profile_failure.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/domain/users/user_profile_repository.dart';
import 'package:note_ai_app/presentation/profile/profile_page.dart';

/// Widget coverage for the Profile screen over the real application service and
/// faked ports: what is loaded, what a failed save leaves on screen, that a
/// cancelled chooser makes no request, and that a stale response cannot rewrite
/// a newer state.

const String _avatarOneBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mO4IyICAALUAQVnjQBuAAAAAElFTkSuQmCC';
const String _avatarTwoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR42mMQEbkDRAwQCgAZXgQRStk/oAAAAABJRU5ErkJggg==';

Uint8List _avatarOne() => base64Decode(_avatarOneBase64);
Uint8List _avatarTwo() => base64Decode(_avatarTwoBase64);

UserProfile _profile({
  String name = 'Ada Lovelace',
  String? avatarReference,
  int revision = 3,
}) {
  return UserProfile.reconstitute(
    userId: 'account-a',
    displayName: name,
    avatarReference: avatarReference,
    revision: revision,
  );
}

final class _FakeProfileRepository implements IUserProfileRepository {
  UserProfile? profile;
  ProfileFailure? findFailure;
  ProfileFailure? saveFailure;
  Completer<void>? findGate;
  final List<UserProfile> saved = <UserProfile>[];

  @override
  Future<UserProfile?> findByUserId(String userId) async {
    final Completer<void>? gate = findGate;
    if (gate != null) {
      await gate.future;
    }
    final ProfileFailure? failure = findFailure;
    if (failure != null) {
      throw failure;
    }
    return profile?.copy();
  }

  @override
  Future<void> save(UserProfile candidate) async {
    final ProfileFailure? failure = saveFailure;
    if (failure != null) {
      throw failure;
    }
    saved.add(candidate.copy());
    profile = candidate.copy();
  }
}

final class _FakeAvatarGateway implements IProfileAvatarGateway {
  Uint8List? bytes;
  ProfileFailure? readFailure;
  ProfileFailure? uploadFailure;
  final List<
    ({String userId, int expectedRevision, Uint8List bytes, String mime})
  >
  uploads =
      <({String userId, int expectedRevision, Uint8List bytes, String mime})>[];

  /// Runs after a successful upload and before the service reloads the profile,
  /// so a test can decide what the canonical record looks like afterwards.
  void Function()? onUpload;

  int get uploadCalls => uploads.length;

  @override
  Future<Uint8List?> getAvatar(String userId) async {
    final ProfileFailure? failure = readFailure;
    if (failure != null) {
      throw failure;
    }
    return bytes;
  }

  @override
  Future<void> uploadAvatar({
    required String userId,
    required int expectedRevision,
    required Uint8List bytes,
    required String mime,
  }) async {
    uploads.add((
      userId: userId,
      expectedRevision: expectedRevision,
      bytes: bytes,
      mime: mime,
    ));
    final ProfileFailure? failure = uploadFailure;
    if (failure != null) {
      throw failure;
    }
    this.bytes = bytes;
    onUpload?.call();
  }
}

CurrentUserSession _session() {
  final CurrentUserSession session = CurrentUserSession();
  session.setIdentity(
    AuthIdentity(
      userId: 'account-a',
      email: 'account-a@example.test',
      isEmailVerified: true,
    ),
  );
  return session;
}

final class _Harness {
  _Harness({UserProfile? profile, Uint8List? avatarBytes}) {
    repository.profile = profile;
    gateway.bytes = avatarBytes;
    service = ProfileAppService(
      repository: repository,
      avatarGateway: gateway,
      session: session,
    );
  }

  final CurrentUserSession session = _session();
  final _FakeProfileRepository repository = _FakeProfileRepository();
  final _FakeAvatarGateway gateway = _FakeAvatarGateway();
  late final ProfileAppService service;
  final List<ProfileSnapshot> changes = <ProfileSnapshot>[];
  Future<Uint8List?> Function() pickAvatar = () async => null;

  Future<void> pump(WidgetTester tester, {Locale locale = const Locale('en')}) {
    return _pumpPage(
      tester,
      service: service,
      pickAvatar: () => pickAvatar(),
      onChanged: changes.add,
      locale: locale,
    );
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required ProfileAppService service,
  required Future<Uint8List?> Function() pickAvatar,
  required ValueChanged<ProfileSnapshot> onChanged,
  required Locale locale,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ProfilePage(
        service: service,
        pickAvatar: pickAvatar,
        onChanged: onChanged,
      ),
    ),
  );
  await _settle(tester);
}

/// Two frames: one to deliver the completed future, one to rebuild with it.
///
/// `pumpAndSettle` is not usable here because the loading and saving states show
/// indeterminate progress indicators that never stop scheduling frames.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

ImageProvider<Object>? _preview(WidgetTester tester) {
  return tester
      .widget<CircleAvatar>(find.byKey(ProfilePageKeys.avatarPreview))
      .foregroundImage;
}

/// Reads the bytes behind the preview image so "the old avatar is kept" is
/// asserted on the image itself, not on a flag.
Uint8List? _previewBytes(WidgetTester tester) {
  final ImageProvider<Object>? provider = _preview(tester);
  return provider is MemoryImage ? provider.bytes : null;
}

String _fieldText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(ProfilePageKeys.nameField))
      .controller!
      .text;
}

bool _enabled(WidgetTester tester, Key key) {
  return tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;
}

void main() {
  testWidgets('a chooser result after account switch uploads nothing', (
    tester,
  ) async {
    final harness = _Harness(profile: _profile());
    final pick = Completer<Uint8List?>();
    harness.pickAvatar = () => pick.future;
    await harness.pump(tester);
    await tester.tap(find.byKey(ProfilePageKeys.pickAvatar));
    await tester.pump();
    harness.session.clear();
    harness.session.setIdentity(
      AuthIdentity(
        userId: 'account-b',
        email: 'b@example.invalid',
        isEmailVerified: true,
      ),
    );
    pick.complete(_avatarTwo());
    await _settle(tester);
    expect(harness.gateway.uploadCalls, 0);
  });

  group('load', () {
    testWidgets('shows the canonical profile and reports it to the shell', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(profile: _profile());

      await harness.pump(tester);

      expect(find.byKey(ProfilePageKeys.loading), findsNothing);
      expect(_fieldText(tester), 'Ada Lovelace');
      expect(find.byKey(ProfilePageKeys.setup), findsNothing);
      expect(harness.changes, hasLength(1));
      expect(harness.changes.single.profile!.displayName, 'Ada Lovelace');
      expect(harness.changes.single.profile!.revision, 3);
    });

    testWidgets('loads the avatar bytes for the preview', (
      WidgetTester tester,
    ) async {
      final Uint8List avatar = _avatarOne();
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: avatar,
      );

      await harness.pump(tester);

      expect(_previewBytes(tester), avatar);
      expect(harness.changes.single.avatarBytes, avatar);
    });

    testWidgets('offers a retry that loads again after a failure', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(profile: _profile())
        ..repository.findFailure = const ProfileFailure(
          ProfileFailureCode.unavailable,
        );

      await harness.pump(tester);

      expect(find.byKey(ProfilePageKeys.loadError), findsOneWidget);
      expect(find.text('The profile could not be loaded.'), findsOneWidget);
      expect(harness.changes, isEmpty);

      harness.repository.findFailure = null;
      await tester.tap(find.byKey(ProfilePageKeys.retry));
      await _settle(tester);

      expect(find.byKey(ProfilePageKeys.loadError), findsNothing);
      expect(_fieldText(tester), 'Ada Lovelace');
      expect(harness.changes, hasLength(1));
    });

    testWidgets('ignores a response that belongs to the previous binding', (
      WidgetTester tester,
    ) async {
      final _Harness first = _Harness(profile: _profile());
      first.repository.findGate = Completer<void>();

      await first.pump(tester);

      expect(find.byKey(ProfilePageKeys.loading), findsOneWidget);

      // A different account binding arrives while the first load is pending.
      final _Harness second = _Harness(profile: _profile(name: 'Bob Stone'));
      await second.pump(tester);

      expect(_fieldText(tester), 'Bob Stone');

      // The first load finally answers with the previous binding's profile.
      first.repository.findGate!.complete();
      await _settle(tester);

      expect(_fieldText(tester), 'Bob Stone');
      expect(first.changes, isEmpty);
      expect(second.changes.single.profile!.displayName, 'Bob Stone');
    });
  });

  group('missing profile', () {
    testWidgets('asks for an explicit setup before an avatar can be added', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness();

      await harness.pump(tester);

      expect(find.byKey(ProfilePageKeys.setup), findsOneWidget);
      expect(find.text('Set up your profile'), findsOneWidget);
      expect(find.text('Create profile'), findsOneWidget);
      expect(
        find.text('Save a display name before adding an avatar.'),
        findsOneWidget,
      );
      expect(_enabled(tester, ProfilePageKeys.pickAvatar), isFalse);
      expect(find.byKey(ProfilePageKeys.removeAvatar), findsNothing);
    });

    testWidgets('refuses a blank name locally and then creates the profile', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness();

      await harness.pump(tester);
      await tester.tap(find.byKey(ProfilePageKeys.saveName));
      await _settle(tester);

      expect(find.text('Display name must not be blank.'), findsOneWidget);
      expect(harness.repository.saved, isEmpty);
      // The successful load of a missing profile is reported once, as setup.
      expect(harness.changes.single.profile, isNull);

      await tester.enterText(find.byKey(ProfilePageKeys.nameField), 'New User');
      await tester.tap(find.byKey(ProfilePageKeys.saveName));
      await _settle(tester);

      expect(harness.repository.saved.single.displayName, 'New User');
      expect(harness.repository.saved.single.revision, 0);
      expect(find.byKey(ProfilePageKeys.setup), findsNothing);
      expect(_enabled(tester, ProfilePageKeys.pickAvatar), isTrue);
      expect(harness.changes, hasLength(2));
      expect(harness.changes.first.profile, isNull);
      expect(harness.changes.last.profile!.displayName, 'New User');
    });
  });

  group('name save', () {
    testWidgets('commits the trimmed name and keeps the loaded revision', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(profile: _profile(revision: 7));

      await harness.pump(tester);
      await tester.enterText(
        find.byKey(ProfilePageKeys.nameField),
        '  Grace Hopper  ',
      );
      await tester.tap(find.byKey(ProfilePageKeys.saveName));
      await _settle(tester);

      expect(harness.repository.saved.single.displayName, 'Grace Hopper');
      expect(harness.repository.saved.single.revision, 7);
      expect(_fieldText(tester), 'Grace Hopper');
      expect(find.byKey(ProfilePageKeys.saved), findsOneWidget);
      expect(harness.changes.last.profile!.displayName, 'Grace Hopper');
    });

    testWidgets('refuses a name past the code-point limit without writing', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(profile: _profile());

      await harness.pump(tester);
      await tester.enterText(
        find.byKey(ProfilePageKeys.nameField),
        'a' * (UserProfile.maxDisplayNameRunes + 1),
      );
      await _settle(tester);

      expect(
        find.text('Display name must be at most 100 characters.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ProfilePageKeys.saveName));
      await _settle(tester);

      expect(harness.repository.saved, isEmpty);
      expect(harness.changes, hasLength(1));
    });

    testWidgets('a refused save keeps the committed avatar and offers reload', (
      WidgetTester tester,
    ) async {
      final Uint8List avatar = _avatarOne();
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: avatar,
      );

      await harness.pump(tester);
      harness.repository.saveFailure = const ProfileFailure(
        ProfileFailureCode.conflict,
      );
      await tester.enterText(
        find.byKey(ProfilePageKeys.nameField),
        'Grace Hopper',
      );
      await tester.tap(find.byKey(ProfilePageKeys.saveName));
      await _settle(tester);

      expect(
        find.text(
          'The profile changed on another device. Reload and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reload'), findsOneWidget);
      expect(_previewBytes(tester), avatar);
      expect(harness.repository.saved, isEmpty);
      // Only the successful load was reported; the refused save was not.
      expect(harness.changes, hasLength(1));
      expect(harness.changes.single.profile!.displayName, 'Ada Lovelace');

      // Reloading clears the refusal and shows the newer canonical record.
      harness.repository.profile = _profile(
        name: 'Grace Hopper',
        revision: 8,
        avatarReference: 'avatar-1',
      );
      await tester.tap(find.text('Reload'));
      await _settle(tester);

      expect(find.text('Reload'), findsNothing);
      expect(_fieldText(tester), 'Grace Hopper');
      expect(harness.changes.last.profile!.displayName, 'Grace Hopper');
    });
  });

  group('avatar', () {
    testWidgets('uploads the prepared PNG under the loaded revision', (
      WidgetTester tester,
    ) async {
      final Uint8List replacement = _avatarTwo();
      final _Harness harness = _Harness(
        profile: _profile(revision: 7, avatarReference: 'avatar-1'),
        avatarBytes: _avatarOne(),
      );

      await harness.pump(tester);
      harness.pickAvatar = () async => replacement;
      harness.gateway.onUpload = () {
        harness.repository.profile = _profile(
          revision: 8,
          avatarReference: 'avatar-2',
        );
      };

      await tester.tap(find.byKey(ProfilePageKeys.pickAvatar));
      await _settle(tester);

      expect(harness.gateway.uploads.single.mime, ProfileAvatarRules.pngMime);
      expect(harness.gateway.uploads.single.expectedRevision, 7);
      expect(harness.gateway.uploads.single.userId, 'account-a');
      expect(harness.gateway.uploads.single.bytes, replacement);
      expect(_previewBytes(tester), replacement);
      expect(harness.changes.last.profile!.avatarReference, 'avatar-2');
    });

    testWidgets('a cancelled pick makes no request and shows no error', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: _avatarOne(),
      );

      await harness.pump(tester);
      harness.pickAvatar = () async => null;

      await tester.tap(find.byKey(ProfilePageKeys.pickAvatar));
      await _settle(tester);

      expect(harness.gateway.uploadCalls, 0);
      expect(find.byKey(ProfilePageKeys.actionError), findsNothing);
      expect(find.byKey(ProfilePageKeys.saving), findsNothing);
      expect(find.byKey(ProfilePageKeys.saved), findsNothing);
      expect(harness.changes, hasLength(1));
    });

    testWidgets('an invalid pick is reported and keeps the current avatar', (
      WidgetTester tester,
    ) async {
      final Uint8List current = _avatarOne();
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: current,
      );

      await harness.pump(tester);
      harness.pickAvatar = () async =>
          throw const ProfileFailure(ProfileFailureCode.invalid);

      await tester.tap(find.byKey(ProfilePageKeys.pickAvatar));
      await _settle(tester);

      expect(
        find.text(
          'Invalid image: PNG or JPEG only, up to 1 MiB and 2048 px per edge.',
        ),
        findsOneWidget,
      );
      expect(harness.gateway.uploadCalls, 0);
      expect(_previewBytes(tester), current);
    });

    testWidgets('a refused upload keeps the current avatar and shows why', (
      WidgetTester tester,
    ) async {
      final Uint8List current = _avatarOne();
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: current,
      );

      await harness.pump(tester);
      harness.pickAvatar = () async => _avatarTwo();
      harness.gateway.uploadFailure = const ProfileFailure(
        ProfileFailureCode.unavailable,
      );

      await tester.tap(find.byKey(ProfilePageKeys.pickAvatar));
      await _settle(tester);

      expect(
        find.text(
          'The profile service could not be reached. Please try again.',
        ),
        findsOneWidget,
      );
      expect(_previewBytes(tester), current);
      expect(harness.changes, hasLength(1));
    });

    testWidgets('removes the association and clears the preview', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: _avatarOne(),
      );

      await harness.pump(tester);
      expect(find.byKey(ProfilePageKeys.removeAvatar), findsOneWidget);

      await tester.tap(find.byKey(ProfilePageKeys.removeAvatar));
      await _settle(tester);

      expect(harness.repository.saved.single.avatarReference, isNull);
      expect(_previewBytes(tester), isNull);
      expect(harness.changes.last.profile!.avatarReference, isNull);
      expect(find.byKey(ProfilePageKeys.removeAvatar), findsNothing);
    });

    testWidgets('an avatar result never rewrites the committed name', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(
        profile: _profile(avatarReference: 'avatar-1'),
        avatarBytes: _avatarOne(),
      );

      await harness.pump(tester);
      await tester.enterText(
        find.byKey(ProfilePageKeys.nameField),
        'Grace Hopper',
      );
      await tester.tap(find.byKey(ProfilePageKeys.saveName));
      await _settle(tester);

      expect(_fieldText(tester), 'Grace Hopper');

      // The association answers with a record built before that rename.
      harness.pickAvatar = () async => _avatarTwo();
      harness.gateway.onUpload = () {
        harness.repository.profile = _profile(
          name: 'Ada Lovelace',
          revision: 4,
          avatarReference: 'avatar-2',
        );
      };

      await tester.tap(find.byKey(ProfilePageKeys.pickAvatar));
      await _settle(tester);

      expect(_fieldText(tester), 'Grace Hopper');
      expect(harness.changes.last.profile!.displayName, 'Ada Lovelace');
      expect(_previewBytes(tester), _avatarTwo());
    });
  });

  group('locale', () {
    testWidgets('renders the Vietnamese copy for a vi locale', (
      WidgetTester tester,
    ) async {
      final _Harness harness = _Harness(profile: _profile());

      await harness.pump(tester, locale: const Locale('vi'));

      expect(find.text('Hồ sơ'), findsOneWidget);
      expect(find.text('Ảnh đại diện'), findsOneWidget);
      expect(find.text('Lưu tên'), findsOneWidget);
      expect(find.text('Tối đa 100 ký tự.'), findsOneWidget);
    });
  });
}
