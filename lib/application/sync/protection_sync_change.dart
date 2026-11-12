import '../../domain/notes/note_protection.dart';

/// Durable intent; never contains a password or an unlock capability.
final class ProtectionSyncChange {
  ProtectionSyncChange({
    required this.before,
    required this.after,
    this.verifier,
  }) {
    if (after.revision <= before.revision ||
        after.enabled != (verifier != null) ||
        verifier != null &&
            (verifier!.trim().isEmpty || verifier!.length > 256)) {
      throw ArgumentError('Invalid protection sync change.');
    }
  }
  final NoteProtection before, after;
  final String? verifier;
  @override
  bool operator ==(Object other) =>
      other is ProtectionSyncChange &&
      other.before == before &&
      other.after == after &&
      other.verifier == verifier;
  @override
  int get hashCode => Object.hash(before, after, verifier);
  @override
  String toString() =>
      'ProtectionSyncChange(${before.revision} -> ${after.revision})';
}
