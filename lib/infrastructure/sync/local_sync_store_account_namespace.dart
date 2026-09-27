/// The account namespace shared by the M2.1 native and Web local sync stores.
///
/// One store instance is bound to exactly one account. The backing store is
/// named after the SHA-256 digest of that account id, never after the raw
/// Cognito `userId`/`sub`: an account identifier must not appear in a file name,
/// a directory name, or an IndexedDB database name that another process, a
/// backup, or a browser profile listing can read.
///
/// Native state lives at
/// `<application support>/accounts/<sha256 of the account id>/local_sync_state.json`,
/// so account directories stay grouped under one `accounts` directory and the
/// digest is the only account-derived name in the path. Web state lives in the
/// account's own IndexedDB database, also named after the same digest, so both
/// platforms of one account share one namespace value.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../application/sync/local_sync_state.dart';
import 'local_sync_store_contract.dart';

/// The namespace facts derived from one account id.
final class LocalSyncAccountNamespace {
  /// Derives the namespace of [accountUserId].
  ///
  /// Throws [ArgumentError] when the id is blank, because a store that is bound
  /// to no account could not tell one account's state from another's.
  factory LocalSyncAccountNamespace(String accountUserId) {
    if (accountUserId.trim().isEmpty) {
      throw ArgumentError.value(
        accountUserId,
        'accountUserId',
        'must not be blank',
      );
    }
    return LocalSyncAccountNamespace._(
      accountUserId,
      _digestFor(accountUserId),
    );
  }

  LocalSyncAccountNamespace._(this.accountUserId, this.hash);

  /// The one directory under the native application-support directory that
  /// groups every account's local sync state.
  static const String accountsDirectoryName = 'accounts';

  /// The account this namespace belongs to, exactly as the caller supplied it.
  final String accountUserId;

  /// Lowercase hex SHA-256 of [accountUserId].
  ///
  /// Both platforms derive their backing-store names from this one value, so
  /// the native account directory and the Web database of an account always
  /// match. It is a digest of the raw account id and nothing else, so a caller
  /// can recompute the namespace of a known account without this library.
  final String hash;

  /// Web IndexedDB database that holds this account's local sync state.
  String get webDatabaseName => 'note_ai_app_local_sync_$hash';

  /// Rejects [state] when it belongs to a different account than this namespace.
  ///
  /// Called before any read result is returned and before any replacement is
  /// written, so one account can never observe or overwrite another account's
  /// state even if a caller mixes stores up.
  void requireOwned(LocalSyncState state) {
    if (state.accountUserId != accountUserId) {
      throw const LocalSyncStoreException(
        LocalSyncStoreFailure.foreignAccount,
        'the local sync state belongs to a different account',
      );
    }
  }

  static String _digestFor(String accountUserId) {
    return sha256.convert(utf8.encode(accountUserId)).toString();
  }
}
