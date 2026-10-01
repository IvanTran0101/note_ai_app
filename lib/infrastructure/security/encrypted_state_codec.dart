import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../application/notes/note_access.dart';
import '../../application/sync/local_sync_state.dart';
import '../../domain/notes/note_protection.dart';
import '../sync/local_sync_state_codec.dart';
import '../sync/local_sync_store_account_namespace.dart';
import 'device_envelope_keys.dart';
import 'note_bundle_projection.dart';
import 'note_crypto.dart';

part 'encrypted_state_keys.dart';

/// Account encryption and per-note wrapping are separate boundaries. Migration
/// quarantines unknown legacy content until canonical online metadata is known.
final class EncryptedStateCodec {
  EncryptedStateCodec(this.namespace) : crypto = NoteCrypto() {
    deviceKeys = DeviceEnvelopeKeys(namespace.hash, crypto);
  }
  final LocalSyncAccountNamespace namespace;
  final NoteCrypto crypto;
  late final DeviceEnvelopeKeys deviceKeys;
  SecretKey? _deviceKey;
  String? _keyId;
  Map<String, Object?> _records = {};
  Map<String, Object?> _quarantine = {};
  Map<String, Object?> _retained = {};
  final Map<String, ({SecretKey key, int epoch})> _opened = {};
  int generation = 0;
  bool migrationRequired = false;
  bool _disposed = false;
  String get _accountAad => 'NoteFlow/M05/v3/${namespace.hash}';
  String _noteAad(String id, int epoch) =>
      '$_accountAad/note/${jsonEncode(id)}/$epoch';
  String _legacyAad(String id) => '$_accountAad/quarantine/${jsonEncode(id)}';

  Future<void> _ensureDeviceKey() async {
    if (_deviceKey != null) return;
    final start = generation;
    final created = await deviceKeys.create();
    if (_disposed || start != generation) {
      created.key.destroy();
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    _deviceKey = created.key;
    _keyId = created.id;
  }

  Future<LocalSyncState> decode(String? encoded) async {
    try {
      final start = generation;
      final state = await _decode(encoded);
      if (_disposed || start != generation) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
      }
      return state;
    } on NoteSecurityFailure {
      rethrow;
    } on Object {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
  }

  Future<LocalSyncState> _decode(String? encoded) async {
    if (_disposed) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    migrationRequired = false;
    if (encoded == null) {
      return LocalSyncState(accountUserId: namespace.accountUserId);
    }
    if (encoded.length > 32 * 1024 * 1024) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    final document = Map<String, Object?>.from(jsonDecode(encoded) as Map);
    if (document['schemaVersion'] == 2) return _migrate(document);
    if (document['schemaVersion'] != 3 ||
        document['algorithm'] != 'AES-256-GCM' ||
        document.length != 4) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    final id = document['keyId'] as String;
    if (_keyId != id) {
      _deviceKey?.destroy();
      final start = generation;
      final loaded = await deviceKeys.read(id);
      if (_disposed || start != generation) {
        loaded.destroy();
        throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
      }
      _deviceKey = loaded;
      _keyId = id;
    }
    final inner = await crypto.decryptJson(
      document['packet'],
      _deviceKey!,
      _accountAad,
    );
    if (inner.length != 4) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    _records = Map<String, Object?>.from(inner['protected'] as Map);
    _quarantine = Map<String, Object?>.from(inner['quarantine'] as Map);
    _retained = Map<String, Object?>.from(inner['retained'] as Map);
    final state = Map<String, Object?>.from(inner['state'] as Map);
    for (final note in NoteBundleProjection.notes(state)) {
      final noteId = note['id'] as String;
      final record = _records[noteId];
      final opened = _opened[noteId];
      if (record != null &&
          opened != null &&
          opened.epoch == note['protectionRevision']) {
        final r = Map<String, Object?>.from(record as Map);
        if (r['epoch'] == opened.epoch) {
          NoteBundleProjection.restore(
            state,
            await crypto.decryptJson(
              r['box'],
              opened.key,
              _noteAad(noteId, opened.epoch),
            ),
          );
        }
      }
    }
    final decoded = LocalSyncStateCodec.decode(state);
    namespace.requireOwned(decoded);
    return decoded;
  }

  Future<LocalSyncState> _migrate(Map<String, Object?> old) async {
    final state = NoteBundleProjection.migrateV2(old);
    final decoded = LocalSyncStateCodec.decode(state);
    namespace.requireOwned(decoded);
    if (decoded.notes.length > 10000 ||
        decoded.outbox.length > 10000 ||
        decoded.conflicts.length > 10000) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    await _ensureDeviceKey();
    _records = {};
    _quarantine = {};
    _retained = {};
    for (final note in decoded.notes) {
      _quarantine[note.id] = await crypto.encryptJson(
        NoteBundleProjection.bundle(state, note.id),
        _deviceKey!,
        _legacyAad(note.id),
      );
      NoteBundleProjection.redact(state, note.id);
    }
    migrationRequired = true;
    return LocalSyncStateCodec.decode(state);
  }

  Future<String> encode(LocalSyncState state) async {
    if (_disposed) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    namespace.requireOwned(state);
    final start = generation;
    await _ensureDeviceKey();
    final data = LocalSyncStateCodec.encode(state);
    for (final note in state.notes) {
      if (!note.protection.enabled && !_quarantine.containsKey(note.id)) {
        continue;
      }
      final opened = _opened[note.id];
      final prior = _records[note.id] as Map?;
      if (note.protection.enabled &&
          opened?.epoch == note.protection.revision &&
          (note.contentAvailable || prior?['box'] == null)) {
        final r = Map<String, Object?>.from(_records[note.id] as Map);
        r['box'] = await crypto.encryptJson(
          NoteBundleProjection.bundle(data, note.id),
          opened!.key,
          _noteAad(note.id, opened.epoch),
        );
        r['pendingIds'] = state.outbox
            .where((m) => m.noteId == note.id)
            .map((m) => m.mutationId)
            .toList();
        _records[note.id] = r;
      } else if (note.contentAvailable && !_quarantine.containsKey(note.id)) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
      }
      NoteBundleProjection.redact(data, note.id);
    }
    final packet = await crypto.encryptJson(
      {
        'state': data,
        'protected': _records,
        'quarantine': _quarantine,
        'retained': _retained,
      },
      _deviceKey!,
      _accountAad,
    );
    if (start != generation) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    final result = jsonEncode({
      'schemaVersion': 3,
      'algorithm': 'AES-256-GCM',
      'keyId': _keyId,
      'packet': packet,
    });
    if (result.length > 32 * 1024 * 1024) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    return result;
  }

  bool isUnlocked(String id, NoteProtection p) =>
      _opened[id]?.epoch == p.revision;
  bool hasRetained(String id) => ((_retained[id] as List?) ?? []).any(
    (r) => ((r as Map)['pendingIds'] as List?)?.isNotEmpty ?? true,
  );
  Future<String> sealLegacyStaging(String encoded) async {
    if (_disposed || _deviceKey == null) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    final start = generation;
    final document = Map<String, Object?>.from(jsonDecode(encoded) as Map);
    if (document['schemaVersion'] != 2 ||
        document['accountUserId'] != namespace.accountUserId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    final packet = await crypto.encryptJson(
      document,
      _deviceKey!,
      '$_accountAad/legacy-staging',
    );
    if (start != generation) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    return jsonEncode({
      'schemaVersion': 3,
      'algorithm': 'AES-256-GCM',
      'keyId': _keyId,
      'kind': 'retainedLegacyStaging',
      'packet': packet,
    });
  }

  void dispose() {
    lock(null);
    _disposed = true;
    _deviceKey?.destroy();
    _deviceKey = null;
    _records.clear();
    _quarantine.clear();
    _retained.clear();
  }

  void lock(String? id) {
    generation++;
    if (id == null) {
      for (final opened in _opened.values) {
        opened.key.destroy();
      }
      _opened.clear();
      _deviceKey?.destroy();
      _deviceKey = null;
      _keyId = null;
    } else {
      _opened.remove(id)?.key.destroy();
    }
  }

  Future<LocalSyncState> observe(
    LocalSyncState state,
    String id,
    NoteProtection p,
  ) async {
    final data = LocalSyncStateCodec.encode(state);
    final oldRecord = _records[id] as Map?;
    if (oldRecord != null && oldRecord['epoch'] != p.revision) {
      _retained[id] = [...((_retained[id] as List?) ?? []), oldRecord];
      _records.remove(id);
      NoteBundleProjection.redact(data, id);
    }
    if (p.enabled) {
      final note = NoteBundleProjection.notes(data)
          .where((n) => n['id'] == id)
          .firstOrNull;
      if (note?['contentAvailable'] == true && !_records.containsKey(id)) {
        _quarantine[id] = await crypto.encryptJson(
          NoteBundleProjection.bundle(data, id),
          _deviceKey!,
          _legacyAad(id),
        );
      }
      NoteBundleProjection.redact(data, id);
      return LocalSyncStateCodec.decode(data);
    }
    if (!_quarantine.containsKey(id)) return LocalSyncStateCodec.decode(data);
    final bundle = await crypto.decryptJson(
      _quarantine[id],
      _deviceKey!,
      _legacyAad(id),
    );
    final note = Map<String, Object?>.from(bundle['note'] as Map);
    bundle['note'] = {
      ...note,
      'protected': false,
      'protectionRevision': p.revision,
      'contentAvailable': true,
    };
    NoteBundleProjection.restore(data, bundle);
    _quarantine.remove(id);
    return LocalSyncStateCodec.decode(data);
  }

  static LocalSyncState changeMetadata(
    LocalSyncState state,
    String id,
    NoteProtection p,
  ) {
    final data = LocalSyncStateCodec.encode(state);
    data['notes'] = NoteBundleProjection.notes(data)
        .map(
          (n) => n['id'] == id
              ? {...n, 'protected': p.enabled, 'protectionRevision': p.revision}
              : n,
        )
        .toList();
    return LocalSyncStateCodec.decode(data);
  }
}
