import 'dart:math';

String newPageGeneration() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((v) => v.toRadixString(16).padLeft(2, '0')).join();

/// Platform storage holds ciphertext only. Canonical/index/record publication
/// has one atomic generation; crypto awaits never occur in a database tx.
final class PagedEncodedView {
  const PagedEncodedView(this.generation, this.index);
  final String generation, index;
}

final class PagedEncodedCommit {
  PagedEncodedCommit({
    required this.generation,
    required this.index,
    required Map<String, String> upserts,
    required Set<String> liveKeys,
  }) : upserts = Map.unmodifiable(upserts),
       liveKeys = Set.unmodifiable(liveKeys);
  final String generation, index;
  final Map<String, String> upserts;
  final Set<String> liveKeys;
}

abstract interface class PagedAccountStore {
  bool get pageMode;
  Future<PagedEncodedView?> openPagedView();
  Future<String> readPagedRecord(String generation, String key);
  Future<void> requirePagedGeneration(String generation);
  Future<bool> compareAndSetPaged(
    String? expected,
    String encrypted,
    PagedEncodedCommit pages,
  );
}

final class StalePageRead implements Exception {
  const StalePageRead();
}

final class CorruptPageRead implements Exception {
  const CorruptPageRead();
}

bool validPageGeneration(String value) =>
    RegExp(r'^[a-f0-9]{32}$').hasMatch(value);
bool validPageRecordKey(String value) =>
    RegExp(r'^[a-f0-9]{64}-[a-f0-9]{64}$').hasMatch(value);
