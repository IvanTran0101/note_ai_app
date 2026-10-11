/// Provider-neutral port for private profile-avatar binary I/O.
///
/// The profile metadata (display name, avatar reference, revision) travels over
/// [IUserProfileRepository]. The avatar bytes are a separate capability: the
/// gateway stages bytes under the signed-in account, completes the association
/// against the profile [expectedRevision], and reads them back through an
/// authenticated route. No presigned/public read URL and no arbitrary storage
/// key ever crosses this boundary.
///
/// Implementations must fail closed: a request for any account other than the
/// verified signed-in identity is [ProfileFailureCode.unauthorized], never a
/// request that carries that account's data.
library;

import 'dart:typed_data';

import 'profile_failure.dart';

/// Reads the current account's avatar and stages replacements for it.
abstract interface class IProfileAvatarGateway {
  /// Returns the current avatar bytes for [userId], or `null` when the account
  /// has no avatar. A missing avatar is canonical, not an error.
  Future<Uint8List?> getAvatar(String userId);

  /// Uploads [bytes] as the avatar of [userId], conditional on
  /// [expectedRevision] so a concurrent profile edit is refused with
  /// [ProfileFailureCode.conflict] instead of being overwritten.
  ///
  /// Retrying the same payload reuses the same server-side intent, so a lost
  /// acknowledgement cannot create a second association.
  Future<void> uploadAvatar({
    required String userId,
    required int expectedRevision,
    required Uint8List bytes,
    required String mime,
  });
}

/// Shared bounds for avatar input validation.
///
/// Dart and the backend enforce the same semantics: PNG or JPEG, at most
/// [maxBytes]. The backend additionally verifies the actual type header/checksum
/// of the staged object.
abstract final class ProfileAvatarRules {
  /// Largest accepted avatar, in bytes (1 MiB).
  static const int maxBytes = 1024 * 1024;

  /// Accepted PNG media type.
  static const String pngMime = 'image/png';

  /// Accepted JPEG media type.
  static const String jpegMime = 'image/jpeg';

  /// Whether [mime] is an accepted avatar media type.
  static bool isSupportedMime(String mime) {
    final String normalized = mime.split(';').first.trim().toLowerCase();
    return normalized == pngMime || normalized == jpegMime;
  }

  /// Throws [ProfileFailureCode.invalid] unless [bytes]/[mime] are uploadable.
  ///
  /// Called before any network work so an oversized or unsupported pick never
  /// reaches the intent route.
  static void validateInput({required Uint8List bytes, required String mime}) {
    if (bytes.isEmpty || bytes.length > maxBytes || !isSupportedMime(mime)) {
      throw const ProfileFailure(ProfileFailureCode.invalid);
    }
  }
}
