import '../../domain/notes/note_protection.dart';

/// Commits local keys, metadata and the existing sync outbox together.
abstract interface class ILocalFirstNoteVault {
  Future<NoteProtection> enableLocal(String id, String password);
  Future<NoteProtection> changeLocal(String id, String current, String next);
  Future<NoteProtection> disableLocal(String id, String current);
}
