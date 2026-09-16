/// Web-safe unavailable implementation of [IUserProfileRepository].
///
/// `dart:io` and `path_provider` are unavailable on the Web, so this library
/// imports neither. [createUserProfileRepository] returns a
/// [FileUserProfileRepository] so Web builds compile and start, but every
/// [findByUserId] and [save] call throws [UnsupportedError]. There are
/// deliberately NO fake stored profiles on the Web.
///
/// The class name matches the native implementation so the conditional facade
/// can swap them by platform. Only the optional `File` parameter differs: the
/// Web has no `dart:io` `File` type, so the stub constructor and factory take
/// no arguments.
library;

import '../../domain/users/user_profile.dart';
import '../../domain/users/user_profile_repository.dart';

/// A repository that is never usable: the Web has no app-private native file
/// for NoteFlow-owned profiles.
final class FileUserProfileRepository implements IUserProfileRepository {
  /// Constructor signature matches the native implementation except for the
  /// `dart:io` `File` parameter, which cannot exist on the Web.
  FileUserProfileRepository();

  @override
  Future<UserProfile?> findByUserId(String userId) {
    throw UnsupportedError(
      'The local user profile repository is not available on this platform '
      '(Web). NoteFlow-owned profiles are not persisted on the Web.',
    );
  }

  @override
  Future<void> save(UserProfile profile) {
    throw UnsupportedError(
      'The local user profile repository is not available on this platform '
      '(Web). NoteFlow-owned profiles are not persisted on the Web.',
    );
  }
}

/// Returns an unavailable [FileUserProfileRepository] on platforms without a
/// native filesystem store (Web). The name and return type match the
/// `dart:io` factory.
IUserProfileRepository createUserProfileRepository() {
  return FileUserProfileRepository();
}
