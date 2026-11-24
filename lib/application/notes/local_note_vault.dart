import '../../domain/notes/note_protection.dart';
import '../sync/sync_snapshot.dart';

/// Durable local protection boundary. Key material never crosses this port.
abstract interface class ILocalNoteVault {
  Future<void> seal(String noteId, String password, NoteProtection protection);
  Future<void> unlock(
    String noteId,
    String password,
    NoteProtection protection, {
    bool verifiedOnline = false,
  });
  Future<void> rewrap(
    String noteId,
    String currentPassword,
    String newPassword,
    NoteProtection protection,
  );
  Future<void> disable(
    String noteId,
    String password,
    NoteProtection protection,
  );
  Future<void> observeProtection(String noteId, NoteProtection protection);
  Future<void> hydrate(SyncNoteSnapshot snapshot);
  bool isLocallyUnlocked(String noteId, NoteProtection protection);
  bool hasRetainedCiphertext(String noteId);
  void lock(String? noteId);
  void dispose();
}
