import 'note_record.dart';

/// Resolves the app-private support directory used by local persistence.
///
/// The resolver is deliberately a plain Dart function so tests can provide a
/// temporary directory without invoking a platform plugin.
typedef ApplicationSupportPathResolver = Future<String> Function();

/// Platform-neutral persistence boundary for Note records.
///
/// The context owns storage and serialization concerns. It does not know
/// about the Note aggregate or domain repository semantics.
abstract interface class DatabaseContext {
  /// Reads all persisted records in their stored order.
  Future<List<NoteRecord>> readNotes();

  /// Replaces the persisted record collection in the supplied order.
  Future<void> writeNotes(Iterable<NoteRecord> notes);
}

/// A typed failure raised by the local notes persistence context.
final class DatabaseContextException implements Exception {
  const DatabaseContextException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final Object? error = cause;
    if (error == null) {
      return 'DatabaseContextException: $message';
    }
    return 'DatabaseContextException: $message (cause: $error)';
  }
}
