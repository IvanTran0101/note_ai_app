import 'package:note_ai_app/infrastructure/security/encoded_account_store.dart';
import 'package:note_ai_app/infrastructure/security/paged_account_store.dart';

/// Atomic ciphertext test double; a failed CAS never mutates any component.
final class MemoryPagedStore implements EncodedAccountStore, PagedAccountStore {
  String? canonical;
  PagedEncodedView? view;
  final records = <String, String>{};
  int rejectedCommits = 0;
  int commits = 0;
  int lastUpserts = 0;
  void Function()? beforeRecord;
  @override
  bool get pageMode => view != null;
  @override
  Future<String?> readEncoded() async => canonical;
  @override
  Future<PagedEncodedView?> openPagedView() async => view;
  @override
  Future<bool> compareAndSet(String? expected, String encrypted) async {
    if (canonical != expected) return false;
    canonical = encrypted;
    view = null;
    records.clear();
    return true;
  }

  @override
  Future<bool> compareAndSetPaged(
    String? expected,
    String encrypted,
    PagedEncodedCommit pages,
  ) async {
    if (rejectedCommits > 0) {
      rejectedCommits--;
      return false;
    }
    if (canonical != expected) return false;
    final next = {...records, ...pages.upserts}
      ..removeWhere((key, _) => !pages.liveKeys.contains(key));
    canonical = encrypted;
    records
      ..clear()
      ..addAll(next);
    view = PagedEncodedView(pages.generation, pages.index);
    lastUpserts = pages.upserts.length;
    commits++;
    return true;
  }

  @override
  Future<void> requirePagedGeneration(String generation) async {
    if (view?.generation != generation) throw const StalePageRead();
  }

  @override
  Future<String> readPagedRecord(String generation, String key) async {
    final callback = beforeRecord;
    beforeRecord = null;
    callback?.call();
    await requirePagedGeneration(generation);
    final raw = records[key];
    if (raw == null) throw const CorruptPageRead();
    return raw;
  }

  @override
  Future<void> cleanLegacyStaging(
    String accountId,
    Future<String> Function(String) sealLegacy,
  ) async {}
}
