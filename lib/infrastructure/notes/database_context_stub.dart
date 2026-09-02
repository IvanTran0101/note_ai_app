import 'database_context_contract.dart';
import 'note_record.dart';

/// Web-safe placeholder for the native file-backed context.
///
/// Web has no application-private native filesystem compatible with this
/// boundary. A future Web persistence adapter can implement [DatabaseContext]
/// separately without making the domain or native adapter conditional.
final class FileDatabaseContext implements DatabaseContext {
  FileDatabaseContext({
    ApplicationSupportPathResolver? applicationSupportPathResolver,
  });

  @override
  Future<List<NoteRecord>> readNotes() {
    throw UnsupportedError('FileDatabaseContext is not available on the Web.');
  }

  @override
  Future<void> writeNotes(Iterable<NoteRecord> notes) {
    throw UnsupportedError('FileDatabaseContext is not available on the Web.');
  }
}
