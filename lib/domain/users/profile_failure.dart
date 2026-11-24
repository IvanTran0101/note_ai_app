/// Provider-neutral failure contract for the cloud profile/avatar boundary.
///
/// This library owns the stable failure vocabulary of one profile operation as
/// observed from the Domain boundary. Infrastructure maps HTTP statuses and
/// wire codes onto [ProfileFailureCode]; Application decides what a code means
/// for a use case, and Presentation renders localized prose from the code
/// alone.
///
/// A failure carries only its [ProfileFailure.code] — never a response body,
/// URL, token, or provider message — so no server text or credential can leak
/// through logs or diagnostics.
library;

/// Stable codes for the failure classes of a profile/avatar operation.
enum ProfileFailureCode {
  /// The submitted name/avatar payload was rejected by the server, or the
  /// local avatar input itself is not a valid PNG/JPEG within the byte bound.
  invalid,

  /// The profile changed on another device since it was loaded, so the write
  /// was refused instead of overwriting the newer state. Reload and retry.
  conflict,

  /// The profile API could not be reached, answered outside the contract, or
  /// failed for a reason that did not map to a more specific code. Retrying
  /// may succeed.
  unavailable,

  /// The operation requires the signed-in identity that owns the profile, and
  /// that identity is missing, different, or no longer current.
  unauthorized,
}

/// Immutable, typed failure that ends one profile/avatar operation.
final class ProfileFailure implements Exception {
  /// Creates a failure carrying its stable [code].
  const ProfileFailure(this.code);

  /// The stable failure class of this operation.
  final ProfileFailureCode code;

  /// Names only the code so no server text or secret can leak.
  @override
  String toString() => 'ProfileFailure(${code.name})';
}
