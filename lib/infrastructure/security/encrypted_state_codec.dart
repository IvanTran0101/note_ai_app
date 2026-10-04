import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../application/notes/note_access.dart';
import '../../application/attachments/attachment_binding.dart';
import '../../application/notes/note_dto.dart';
import '../../application/sync/local_sync_state.dart';
import '../../application/sync/local_note_state.dart';
import '../../domain/notes/note_protection.dart';
import '../../domain/notes/note_role.dart';
import '../sync/local_sync_state_codec.dart';
import '../sync/local_sync_store_account_namespace.dart';
import 'device_envelope_keys.dart';
import 'note_bundle_projection.dart';
import 'note_crypto.dart';

part 'encrypted_state_keys.dart';
part 'encrypted_shared_drafts.dart';
part 'encrypted_legacy_bindings.dart';
part 'encrypted_attachment_keys.dart';

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
  Map<String, Object?> _binaryKeys = {};
  final Map<String, SecretKey> _binaryOpened = {};
  final Map<String, ({SecretKey key, int epoch})> _opened = {};
  int generation = 0;
  bool migrationRequired = false;
  bool _disposed = false;

  /// Borrowed M05 key: callers must not retain or destroy it. Lock/logout owns
  /// destruction; binary operations must check live authority around each await.
  Future<SecretKey> attachmentRootKey(AttachmentBinding binding) async {
    if (_disposed || binding.actorId != namespace.accountUserId) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    if (binding.protection.enabled) {
      final opened = _opened[binding.note.referenceFor(binding.actorId)];
      if (opened == null || opened.epoch != binding.protection.revision) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
      }
      return opened.key;
    }
    final start = generation;
    await _ensureDeviceKey();
    if (start != generation || _disposed) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.sessionChanged);
    }
    return _deviceKey!;
  }

  String get _accountAad => 'NoteFlow/M05/v3/${namespace.hash}';
  String _noteAad(String id, int epoch) =>
      '$_accountAad/note/${jsonEncode((_records[id] as Map?)?["binding"] ?? id)}/$epoch';
  String _legacyAad(String id) =>
      '$_accountAad/quarantine/${jsonEncode((_quarantine[id] as Map?)?["binding"] ?? id)}';

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
    if (document['schemaVersion'] == 2 ||
        (document['schemaVersion'] == 3 &&
            !document.containsKey('algorithm'))) {
      return _migrate(document);
    }
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
    if (inner.length != 4 &&
        !(inner.length == 5 && inner['binaryKeys'] is Map)) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    _records = Map<String, Object?>.from(inner['protected'] as Map);
    _quarantine = Map<String, Object?>.from(inner['quarantine'] as Map);
    _retained = Map<String, Object?>.from(inner['retained'] as Map);
    final binaryKeys = Map<String, Object?>.from(
      (inner['binaryKeys'] as Map?) ?? {},
    );
    for (final reference in _binaryOpened.keys.toList()) {
      if (jsonEncode(binaryKeys[reference]) !=
          jsonEncode(_binaryKeys[reference])) {
        _binaryOpened.remove(reference)?.destroy();
      }
    }
    _binaryKeys = binaryKeys;
    final state = Map<String, Object?>.from(inner['state'] as Map);
    _normalizeLegacyBindings(state);
    for (final note in NoteBundleProjection.notes(state)) {
      final noteId = NoteBundleProjection.reference(state, note);
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
            requireCurrentRevision: true,
          );
        }
      }
    }
    final decoded = LocalSyncStateCodec.decode(state);
    namespace.requireOwned(decoded);
    return decoded;
  }

  Future<LocalSyncState> _migrate(Map<String, Object?> old) async {
    final decoded = LocalSyncStateCodec.decode(
      NoteBundleProjection.migrateV2(old),
    );
    namespace.requireOwned(decoded);
    // Redaction adds current manifest fields; normalize before quarantining so
    // subsequent decoding does not mistake them for an invalid legacy record.
    final state = LocalSyncStateCodec.encode(decoded);
    if (decoded.notes.length > 10000 ||
        decoded.outbox.length > 10000 ||
        decoded.conflicts.length > 10000) {
      throw const NoteSecurityFailure(NoteSecurityFailureCode.storage);
    }
    await _ensureDeviceKey();
    _records = {};
    _quarantine = {};
    _retained = {};
    _binaryKeys = {};
    for (final note in decoded.notes) {
      _quarantine[note.referenceFor(namespace.accountUserId)] = await crypto
          .encryptJson(
            NoteBundleProjection.bundle(
              state,
              note.referenceFor(namespace.accountUserId),
            ),
            _deviceKey!,
            _legacyAad(note.referenceFor(namespace.accountUserId)),
          );
      NoteBundleProjection.redact(
        state,
        note.referenceFor(namespace.accountUserId),
      );
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
      if (!note.protection.enabled &&
          !_quarantine.containsKey(
            note.referenceFor(namespace.accountUserId),
          )) {
        continue;
      }
      final opened = _opened[note.referenceFor(namespace.accountUserId)];
      final prior =
          _records[note.referenceFor(namespace.accountUserId)] as Map?;
      if (note.protection.enabled &&
          opened?.epoch == note.protection.revision &&
          (note.contentAvailable || prior?['box'] == null)) {
        final r = Map<String, Object?>.from(
          _records[note.referenceFor(namespace.accountUserId)] as Map,
        );
        r['box'] = await crypto.encryptJson(
          NoteBundleProjection.bundle(
            data,
            note.referenceFor(namespace.accountUserId),
          ),
          opened!.key,
          _noteAad(note.referenceFor(namespace.accountUserId), opened.epoch),
        );
        r['pendingIds'] = state.outbox
            .where(
              (m) =>
                  !m.isLabel &&
                  m.mutation.identityFor(namespace.accountUserId) ==
                      note.identity,
            )
            .map((m) => m.mutationId)
            .toList();
        _records[note.referenceFor(namespace.accountUserId)] = r;
      } else if (note.contentAvailable &&
          !_quarantine.containsKey(
            note.referenceFor(namespace.accountUserId),
          )) {
        throw const NoteSecurityFailure(NoteSecurityFailureCode.locked);
      }
      NoteBundleProjection.redact(
        data,
        note.referenceFor(namespace.accountUserId),
      );
    }
    final packet = await crypto.encryptJson(
      {
        'state': data,
        'protected': _records,
        'quarantine': _quarantine,
        'retained': _retained,
        if (_binaryKeys.isNotEmpty) 'binaryKeys': _binaryKeys,
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
    _binaryKeys.clear();
  }

  void lock(String? id) {
    generation++;
    if (id == null) {
      for (final key in _binaryOpened.values) {
        key.destroy();
      }
      _binaryOpened.clear();
    } else {
      _binaryOpened.remove(id)?.destroy();
    }
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
          .where((n) => NoteBundleProjection.reference(data, n) == id)
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
      _quarantinePacket(id),
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
          (n) => NoteBundleProjection.reference(data, n) == id
              ? {...n, 'protected': p.enabled, 'protectionRevision': p.revision}
              : n,
        )
        .toList();
    return LocalSyncStateCodec.decode(data);
  }
}
