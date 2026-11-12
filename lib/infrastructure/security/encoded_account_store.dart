/// The platform performs only bounded reads and atomic ciphertext CAS commits.
/// Cryptography never awaits inside an active IndexedDB transaction.
abstract interface class EncodedAccountStore {
  Future<String?> readEncoded();
  Future<bool> compareAndSet(String? expected, String encrypted);
  Future<void> cleanLegacyStaging(
    String accountId,
    Future<String> Function(String) sealLegacy,
  );
}
