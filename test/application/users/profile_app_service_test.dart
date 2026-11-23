import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/users/profile_app_service.dart';
import 'package:note_ai_app/application/users/profile_snapshot.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/users/profile_avatar_gateway.dart';
import 'package:note_ai_app/domain/users/profile_failure.dart';
import 'package:note_ai_app/domain/users/user_profile.dart';
import 'package:note_ai_app/domain/users/user_profile_repository.dart';

/// Behavior coverage for the account-scoped profile use cases.
///
/// The fakes stand in for the cloud adapters, so the assertions are about what
/// Application decides: which revision an edit is conditional on, when a result
/// is discarded because the session changed, and that a stale snapshot is never
/// handed to the next account.

UserProfile _profile({
  String userId = 'user-a',
  String displayName = 'Ada Lovelace',
  String? avatarReference,
  int revision = 0,
}) {
  return UserProfile.reconstitute(
    userId: userId,
    displayName: displayName,
    avatarReference: avatarReference,
    revision: revision,
  );
}

CurrentUserSession _signedIn(String userId) {
  final CurrentUserSession session = CurrentUserSession();
  session.setIdentity(
    AuthIdentity(
      userId: userId,
      email: '$userId@example.com',
      isEmailVerified: true,
    ),
  );
  return session;
}

Matcher _unauthorized() => throwsA(
  isA<ProfileFailure>().having(
    (ProfileFailure failure) => failure.code,
    'code',
    ProfileFailureCode.unauthorized,
  ),
);

final class _FakeProfileRepository implements IUserProfileRepository {
  _FakeProfileRepository({this.profile, List<String>? events})
    : events = events ?? <String>[];

  UserProfile? profile;
  ProfileFailure? failure;
  final List<String> events;
  final List<UserProfile> saved = <UserProfile>[];
  final List<String> findCalls = <String>[];
  Completer<void>? gate;

  @override
  Future<UserProfile?> findByUserId(String userId) async {
    findCalls.add(userId);
    events.add('find:$userId');
    await _wait();
    if (failure != null) throw failure!;
    return profile;
  }

  @override
  Future<void> save(UserProfile profile) async {
    await _wait();
    if (failure != null) throw failure!;
    events.add('save:${profile.displayName}@${profile.revision}');
    saved.add(profile);
    // The server answers with the canonical profile: the write is applied and
    // the revision advances.
    this.profile = _profile(
      userId: profile.userId,
      displayName: profile.displayName,
      avatarReference: profile.avatarReference,
      revision: profile.revision + 1,
    );
  }

  Future<void> _wait() async {
    final Completer<void>? gate = this.gate;
    if (gate != null) await gate.future;
  }
}

typedef _Upload = ({
  String userId,
  int expectedRevision,
  int sizeBytes,
  String mime,
});

final class _FakeAvatarGateway implements IProfileAvatarGateway {
  _FakeAvatarGateway({this.avatarBytes, List<String>? events})
    : events = events ?? <String>[];

  Uint8List? avatarBytes;
  ProfileFailure? failure;
  final List<String> events;
  final List<String> getAvatarCalls = <String>[];
  final List<_Upload> uploads = <_Upload>[];
  Completer<void>? gate;

  @override
  Future<Uint8List?> getAvatar(String userId) async {
    getAvatarCalls.add(userId);
    events.add('getAvatar:$userId');
    final Completer<void>? gate = this.gate;
    if (gate != null) await gate.future;
    if (failure != null) throw failure!;
    return avatarBytes;
  }

  @override
  Future<void> uploadAvatar({
    required String userId,
    required int expectedRevision,
    required Uint8List bytes,
    required String mime,
  }) async {
    final Completer<void>? gate = this.gate;
    if (gate != null) await gate.future;
    if (failure != null) throw failure!;
    events.add('upload:$expectedRevision');
    uploads.add((
      userId: userId,
      expectedRevision: expectedRevision,
      sizeBytes: bytes.length,
      mime: mime,
    ));
  }
}

typedef _Fixture = ({
  ProfileAppService service,
  _FakeProfileRepository repository,
  _FakeAvatarGateway gateway,
  CurrentUserSession session,
  List<String> events,
});

_Fixture _fixture({
  UserProfile? profile,
  Uint8List? avatarBytes,
  String userId = 'user-a',
}) {
  final List<String> events = <String>[];
  final _FakeProfileRepository repository = _FakeProfileRepository(
    profile: profile,
    events: events,
  );
  final _FakeAvatarGateway gateway = _FakeAvatarGateway(
    avatarBytes: avatarBytes,
    events: events,
  );
  final CurrentUserSession session = _signedIn(userId);
  return (
    service: ProfileAppService(
      repository: repository,
      avatarGateway: gateway,
      session: session,
    ),
    repository: repository,
    gateway: gateway,
    session: session,
    events: events,
  );
}

void main() {
  group('ProfileAppService.load', () {
    test('returns the canonical profile and its avatar bytes', () async {
      final _Fixture fixture = _fixture(
        profile: _profile(
          displayName: 'Ada Lovelace',
          avatarReference: 'avatar-1',
          revision: 3,
        ),
        avatarBytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      final ProfileSnapshot snapshot = await fixture.service.load();

      expect(snapshot.profile, isNotNull);
      expect(snapshot.profile!.userId, 'user-a');
      expect(snapshot.profile!.displayName, 'Ada Lovelace');
      expect(snapshot.profile!.revision, 3);
      expect(snapshot.avatarBytes, <int>[1, 2, 3]);
      expect(fixture.repository.findCalls, <String>['user-a']);
      expect(fixture.gateway.getAvatarCalls, <String>['user-a']);
      expect(fixture.service.current, isNotNull);
    });

    test('returns a null profile for an account with none stored', () async {
      final _Fixture fixture = _fixture();

      final ProfileSnapshot snapshot = await fixture.service.load();

      expect(snapshot.profile, isNull);
      expect(snapshot.avatarBytes, isNull);
      expect(fixture.gateway.getAvatarCalls, isEmpty);
    });

    test('does not read avatar bytes without an avatar reference', () async {
      final _Fixture fixture = _fixture(profile: _profile(revision: 2));

      final ProfileSnapshot snapshot = await fixture.service.load();

      expect(snapshot.profile!.displayName, 'Ada Lovelace');
      expect(snapshot.avatarBytes, isNull);
      expect(fixture.gateway.getAvatarCalls, isEmpty);
    });

    test('surfaces a repository failure', () async {
      final _Fixture fixture = _fixture();
      fixture.repository.failure = const ProfileFailure(
        ProfileFailureCode.unavailable,
      );

      await expectLater(
        fixture.service.load(),
        throwsA(
          isA<ProfileFailure>().having(
            (ProfileFailure failure) => failure.code,
            'code',
            ProfileFailureCode.unavailable,
          ),
        ),
      );
    });

    test('returns a detached profile', () async {
      final _Fixture fixture = _fixture(profile: _profile(revision: 2));
      final ProfileSnapshot snapshot = await fixture.service.load();

      snapshot.profile!.changeDisplayName('Mutated');

      expect(fixture.service.current!.profile!.displayName, 'Ada Lovelace');
    });
  });

  group('ProfileAppService.saveName', () {
    test(
      'keeps the loaded revision and returns the reloaded profile',
      () async {
        final _Fixture fixture = _fixture(
          profile: _profile(displayName: 'Ada', revision: 5),
        );
        await fixture.service.load();

        final ProfileSnapshot snapshot = await fixture.service.saveName(
          '  Ada Byron  ',
        );

        expect(fixture.repository.saved, hasLength(1));
        expect(fixture.repository.saved.single.revision, 5);
        expect(fixture.repository.saved.single.displayName, 'Ada Byron');
        expect(snapshot.profile!.displayName, 'Ada Byron');
        expect(snapshot.profile!.revision, 6);
        expect(fixture.service.current!.profile!.revision, 6);
      },
    );

    test(
      'creates an explicit revision-0 profile when none is stored',
      () async {
        final _Fixture fixture = _fixture();
        await fixture.service.load();

        await fixture.service.saveName('Grace Hopper');

        expect(fixture.repository.saved, hasLength(1));
        expect(fixture.repository.saved.single.revision, 0);
        expect(fixture.repository.saved.single.userId, 'user-a');
        expect(fixture.repository.saved.single.displayName, 'Grace Hopper');
      },
    );

    test('reads the canonical revision when nothing was loaded yet', () async {
      final _Fixture fixture = _fixture(profile: _profile(revision: 9));

      await fixture.service.saveName('Ada Byron');

      // The canonical read happens before the conditional write, so the write
      // cannot blindly overwrite a revision the service never observed.
      expect(
        fixture.events,
        containsAllInOrder(<String>['find:user-a', 'save:Ada Byron@9']),
      );
      expect(fixture.repository.saved.single.revision, 9);
    });

    test('rejects an invalid name before touching the repository', () async {
      final _Fixture fixture = _fixture(profile: _profile(revision: 9));

      await expectLater(
        fixture.service.saveName('a' * (UserProfile.maxDisplayNameRunes + 1)),
        throwsArgumentError,
      );
      await expectLater(fixture.service.saveName('   '), throwsArgumentError);

      expect(fixture.repository.findCalls, isEmpty);
      expect(fixture.repository.saved, isEmpty);
    });

    test(
      'lets a conflict reach the caller and keeps the loaded snapshot',
      () async {
        final _Fixture fixture = _fixture(
          profile: _profile(displayName: 'Ada', revision: 5),
        );
        await fixture.service.load();
        fixture.repository.failure = const ProfileFailure(
          ProfileFailureCode.conflict,
        );

        await expectLater(
          fixture.service.saveName('Ada Byron'),
          throwsA(
            isA<ProfileFailure>().having(
              (ProfileFailure failure) => failure.code,
              'code',
              ProfileFailureCode.conflict,
            ),
          ),
        );

        expect(fixture.repository.saved, isEmpty);
        expect(fixture.service.current!.profile!.displayName, 'Ada');
        expect(fixture.service.current!.profile!.revision, 5);
      },
    );
  });

  group('ProfileAppService.uploadAvatar', () {
    final Uint8List bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);

    test('sends the loaded revision and reloads canonical state', () async {
      final _Fixture fixture = _fixture(
        profile: _profile(avatarReference: 'avatar-1', revision: 4),
      );
      await fixture.service.load();

      final ProfileSnapshot snapshot = await fixture.service.uploadAvatar(
        bytes,
        ProfileAvatarRules.pngMime,
      );

      expect(fixture.gateway.uploads, hasLength(1));
      expect(fixture.gateway.uploads.single.userId, 'user-a');
      expect(fixture.gateway.uploads.single.expectedRevision, 4);
      expect(fixture.gateway.uploads.single.sizeBytes, 4);
      expect(fixture.gateway.uploads.single.mime, ProfileAvatarRules.pngMime);
      // The upload is followed by a canonical reload, never by a local guess.
      expect(
        fixture.events,
        containsAllInOrder(<String>['upload:4', 'find:user-a']),
      );
      expect(snapshot.profile!.avatarReference, 'avatar-1');
    });

    test('requires explicit name setup before uploading an avatar', () async {
      final _Fixture fixture = _fixture();
      await fixture.service.load();

      await expectLater(
        fixture.service.uploadAvatar(bytes, ProfileAvatarRules.jpegMime),
        throwsA(isA<ProfileFailure>()),
      );
      expect(fixture.gateway.uploads, isEmpty);
    });

    test('rejects invalid input before any request', () async {
      final _Fixture fixture = _fixture();

      await expectLater(
        fixture.service.uploadAvatar(Uint8List(0), ProfileAvatarRules.pngMime),
        throwsA(
          isA<ProfileFailure>().having(
            (ProfileFailure failure) => failure.code,
            'code',
            ProfileFailureCode.invalid,
          ),
        ),
      );
      await expectLater(
        fixture.service.uploadAvatar(
          Uint8List(ProfileAvatarRules.maxBytes + 1),
          ProfileAvatarRules.pngMime,
        ),
        throwsA(isA<ProfileFailure>()),
      );
      await expectLater(
        fixture.service.uploadAvatar(bytes, 'image/gif'),
        throwsA(isA<ProfileFailure>()),
      );

      expect(fixture.repository.findCalls, isEmpty);
      expect(fixture.gateway.uploads, isEmpty);
    });

    test('propagates a gateway conflict and keeps the old avatar', () async {
      final _Fixture fixture = _fixture(
        profile: _profile(avatarReference: 'avatar-1', revision: 4),
        avatarBytes: Uint8List.fromList(<int>[9]),
      );
      await fixture.service.load();
      fixture.gateway.failure = const ProfileFailure(
        ProfileFailureCode.conflict,
      );

      await expectLater(
        fixture.service.uploadAvatar(bytes, ProfileAvatarRules.pngMime),
        throwsA(isA<ProfileFailure>()),
      );

      expect(fixture.service.current!.profile!.avatarReference, 'avatar-1');
      expect(fixture.service.current!.avatarBytes, <int>[9]);
    });
  });

  group('ProfileAppService.removeAvatar', () {
    test('clears the reference at the loaded revision', () async {
      final _Fixture fixture = _fixture(
        profile: _profile(avatarReference: 'avatar-1', revision: 7),
      );
      await fixture.service.load();

      final ProfileSnapshot snapshot = await fixture.service.removeAvatar();

      expect(fixture.repository.saved.single.avatarReference, isNull);
      expect(fixture.repository.saved.single.revision, 7);
      expect(snapshot.profile!.avatarReference, isNull);
      expect(snapshot.avatarBytes, isNull);
      expect(fixture.gateway.getAvatarCalls, <String>['user-a']);
    });

    test('does nothing but reload when no profile is stored', () async {
      final _Fixture fixture = _fixture();
      await fixture.service.load();

      final ProfileSnapshot snapshot = await fixture.service.removeAvatar();

      expect(fixture.repository.saved, isEmpty);
      expect(snapshot.profile, isNull);
    });
  });

  group('ProfileAppService session binding', () {
    test('refuses every operation without an authenticated session', () async {
      final CurrentUserSession session = CurrentUserSession();
      final _FakeProfileRepository repository = _FakeProfileRepository();
      final _FakeAvatarGateway gateway = _FakeAvatarGateway();
      final ProfileAppService service = ProfileAppService(
        repository: repository,
        avatarGateway: gateway,
        session: session,
      );

      await expectLater(service.load(), _unauthorized());
      await expectLater(service.saveName('Ada'), _unauthorized());
      await expectLater(service.removeAvatar(), _unauthorized());
      await expectLater(
        service.uploadAvatar(
          Uint8List.fromList(<int>[1]),
          ProfileAvatarRules.pngMime,
        ),
        _unauthorized(),
      );

      expect(repository.findCalls, isEmpty);
      expect(repository.saved, isEmpty);
      expect(gateway.uploads, isEmpty);
      expect(service.current, isNull);
    });

    test('discards a load that finishes after a logout', () async {
      final _Fixture fixture = _fixture(profile: _profile());
      fixture.repository.gate = Completer<void>();

      final Future<ProfileSnapshot> pending = fixture.service.load();
      fixture.session.clear();
      fixture.repository.gate!.complete();

      await expectLater(pending, _unauthorized());
      expect(fixture.service.current, isNull);
    });

    test(
      'discards an avatar read that finishes after an account switch',
      () async {
        final _Fixture fixture = _fixture(
          profile: _profile(avatarReference: 'avatar-1'),
        );
        fixture.gateway.gate = Completer<void>();

        final Future<ProfileSnapshot> pending = fixture.service.load();
        fixture.session.setIdentity(
          AuthIdentity(
            userId: 'user-b',
            email: 'user-b@example.com',
            isEmailVerified: true,
          ),
        );
        fixture.gateway.gate!.complete();

        await expectLater(pending, _unauthorized());
        expect(fixture.service.current, isNull);
      },
    );

    test(
      'does not hand a previous snapshot to the same account returning',
      () async {
        final _Fixture fixture = _fixture(
          profile: _profile(displayName: 'Ada'),
        );
        await fixture.service.load();
        expect(fixture.service.current, isNotNull);

        fixture.session.clear();
        fixture.session.setIdentity(
          AuthIdentity(
            userId: 'user-a',
            email: 'user-a@example.com',
            isEmailVerified: true,
          ),
        );

        expect(fixture.service.current, isNull);

        final ProfileSnapshot snapshot = await fixture.service.load();
        expect(snapshot.profile!.displayName, 'Ada');
        expect(fixture.service.current, isNotNull);
      },
    );

    test('never applies one account state to the next account', () async {
      final _Fixture fixture = _fixture(
        profile: _profile(userId: 'user-a', displayName: 'Ada', revision: 4),
      );
      await fixture.service.load();

      fixture.session.setIdentity(
        AuthIdentity(
          userId: 'user-b',
          email: 'user-b@example.com',
          isEmailVerified: true,
        ),
      );
      fixture.repository.profile = _profile(
        userId: 'user-b',
        displayName: 'Grace',
        revision: 1,
      );

      expect(fixture.service.current, isNull);

      await fixture.service.saveName('Grace Hopper');

      expect(fixture.repository.findCalls.last, 'user-b');
      expect(fixture.repository.saved.single.userId, 'user-b');
      expect(fixture.repository.saved.single.revision, 1);
      expect(fixture.repository.saved.single.displayName, 'Grace Hopper');
    });

    test('snapshots the generation before each await', () async {
      final _Fixture fixture = _fixture(
        profile: _profile(displayName: 'Ada', revision: 2),
      );
      await fixture.service.load();

      fixture.repository.gate = Completer<void>();
      final Future<ProfileSnapshot> pending = fixture.service.saveName(
        'Ada Byron',
      );
      // The session changes while the write is in flight.
      fixture.session.clear();
      fixture.repository.gate!.complete();

      await expectLater(pending, _unauthorized());
    });
  });
}
