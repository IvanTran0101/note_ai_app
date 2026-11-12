// Canonical consent grant and one compare-and-set write.
part of 'rag_models.dart';

/// One canonical RAG consent grant for an account.
///
/// The version is frozen: a grant that reports any other version is refused
/// instead of being adopted. `accepted` with generation 0 is impossible because
/// the first accepted grant is written as generation 1 by compare-and-set.
final class RagConsent {
  /// Creates a validated grant snapshot.
  RagConsent({
    required this.accepted,
    String version = currentVersion,
    required int generation,
  }) : version = _requireConsentVersion(version),
       generation = _requireGeneration(generation) {
    if (accepted && generation < 1) {
      throw _invalid('generation', 'must be at least 1 for an accepted grant');
    }
  }

  /// The only consent version this build understands.
  static const String currentVersion = 'rag-consent.v2';

  /// The default for an account with no stored row.
  static final RagConsent none = RagConsent(
    accepted: false,
    version: currentVersion,
    generation: 0,
  );

  /// Whether the account accepted RAG egress for this version.
  final bool accepted;

  /// The frozen consent version.
  final String version;

  /// Monotonic grant generation; 0 means "never written".
  final int generation;

  /// Whether this grant allows a query to be prepared.
  bool get allowsQuery => accepted;

  @override
  bool operator ==(Object other) =>
      other is RagConsent &&
      other.accepted == accepted &&
      other.version == version &&
      other.generation == generation;

  @override
  int get hashCode => Object.hash(accepted, version, generation);

  @override
  String toString() {
    return 'RagConsent(accepted: $accepted, version: $version, '
        'generation: $generation)';
  }
}

/// One compare-and-set consent write.
///
/// [expectedGeneration] is the generation the caller read; a stale value is
/// refused by the server with `SOURCE_CHANGED` (409) instead of overwriting a
/// concurrent decision.
final class RagConsentUpdate {
  /// Creates a validated consent write.
  RagConsentUpdate({
    required this.accepted,
    String version = RagConsent.currentVersion,
    required int expectedGeneration,
  }) : version = _requireConsentVersion(version),
       expectedGeneration = _requireGeneration(
         expectedGeneration,
         'expectedGeneration',
       );

  /// The decision to write.
  final bool accepted;

  /// The frozen consent version.
  final String version;

  /// The generation the caller read before writing.
  final int expectedGeneration;

  @override
  bool operator ==(Object other) =>
      other is RagConsentUpdate &&
      other.accepted == accepted &&
      other.version == version &&
      other.expectedGeneration == expectedGeneration;

  @override
  int get hashCode => Object.hash(accepted, version, expectedGeneration);

  @override
  String toString() {
    return 'RagConsentUpdate(accepted: $accepted, version: $version, '
        'expectedGeneration: $expectedGeneration)';
  }
}
