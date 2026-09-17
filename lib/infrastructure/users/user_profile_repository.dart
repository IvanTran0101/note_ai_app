/// Public entrypoint for local NoteFlow-owned user-profile persistence.
///
/// The domain contract [IUserProfileRepository] is always available here. On
/// platforms with `dart:io` this library also resolves to the
/// path_provider-backed `FileUserProfileRepository`
/// (`user_profile_repository_io.dart`) and its repository-specific exception.
/// On the Web — where `dart:io` and `path_provider` are unavailable — it
/// resolves to `user_profile_repository_stub.dart`, whose
/// [createUserProfileRepository] returns a repository that throws
/// [UnsupportedError] on every call. Web never fakes stored profiles.
///
/// Profiles are NoteFlow-owned display data, separate from authentication
/// identity: this boundary never reads or writes credentials.
library;

export '../../domain/users/user_profile_repository.dart';

export 'user_profile_repository_stub.dart'
    if (dart.library.io) 'user_profile_repository_io.dart';
