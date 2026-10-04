import '../../domain/notes/note_identity.dart';

/// Serialized bundles are private to encrypted Infrastructure. Queue identities
/// and ordering stay in the root projection; content only lives in sealed bundles.
abstract final class NoteBundleProjection {
  static String reference(
    Map<String, Object?> state,
    Map<String, Object?> record, {
    String idField = 'id',
  }) {
    final actor = state['accountUserId'] as String;
    if (record['entityType'] == 'label') {
      return 'label:$actor:${record[idField]}';
    }
    return NoteIdentity(
      (record['ownerId'] as String?) ?? actor,
      record[idField] as String,
    ).referenceFor(actor);
  }

  static Map<String, Object?> bundle(Map<String, Object?> state, String id) => {
    'note': notes(state).firstWhere((n) => reference(state, n) == id),
    'outbox': entries(
      state,
      'outbox',
    ).where((e) => reference(state, e, idField: 'noteId') == id).toList(),
    'conflicts': entries(state, 'conflicts')
        .where(
          (e) =>
              reference(state, Map<String, Object?>.from(e['local'] as Map)) ==
              id,
        )
        .toList(),
  };

  static List<Map<String, Object?>> entries(
    Map<String, Object?> state,
    String field,
  ) => (state[field] as List)
      .map((e) => Map<String, Object?>.from(e as Map))
      .toList();
  static List<Map<String, Object?>> notes(Map<String, Object?> state) =>
      entries(state, 'notes');

  static void redact(Map<String, Object?> state, String id) {
    state['notes'] = notes(state)
        .map((n) => reference(state, n) == id ? _private(n) : n)
        .toList();
    redactWork(state, id);
  }

  static void redactWork(Map<String, Object?> state, String id) {
    state['outbox'] = entries(state, 'outbox')
        .map(
          (m) => reference(state, m, idField: 'noteId') == id ? _pending(m) : m,
        )
        .toList();
    state['conflicts'] = entries(state, 'conflicts').map((c) {
      if (reference(state, Map<String, Object?>.from(c['local'] as Map)) !=
          id) {
        return c;
      }
      return {
        ...c,
        'local': _private(Map<String, Object?>.from(c['local'] as Map)),
        'remote': c['remote'] == null
            ? null
            : _private(Map<String, Object?>.from(c['remote'] as Map)),
        'pending': _pending(Map<String, Object?>.from(c['pending'] as Map)),
      };
    }).toList();
  }

  static Map<String, Object?> _private(Map<String, Object?> n) => {
    ...n,
    'title': '',
    'content': '',
    'attachments': <Object?>[],
    'labelIds': <Object?>[],
    'labelProjections': <Object?>[],
    'contentAvailable': false,
  };
  static Map<String, Object?> _pending(Map<String, Object?> m) => {
    ...m,
    'blocked': true,
    'payload': m['payload'] == null ? null : {'title': '', 'content': ''},
  };

  static void restore(
    Map<String, Object?> state,
    Map<String, Object?> bundle, {
    bool requireCurrentRevision = false,
  }) {
    final note = <String, Object?>{
      'pinnedAt': null,
      'attachments': <Object?>[],
      'labelIds': <Object?>[],
      'labelProjections': <Object?>[],
      ...Map<String, Object?>.from(bundle['note'] as Map),
    };
    final id = reference(state, note);
    final currentNote = notes(state)
        .where((n) => reference(state, n) == id)
        .firstOrNull;
    final access = currentNote?['share'] as Map?;
    if (access != null &&
        (access['status'] != 'active' ||
            access['accessRevision'] !=
                (note['share'] as Map?)?['accessRevision'])) {
      return;
    }
    final hasPending = entries(
      state,
      'outbox',
    ).any((m) => reference(state, m, idField: 'noteId') == id);
    if (requireCurrentRevision &&
        !hasPending &&
        currentNote != null &&
        (currentNote['serverRevision'] as int) >
            (note['serverRevision'] as int)) {
      return;
    }
    state['notes'] = notes(state)
        .map((n) => reference(state, n) == id ? note : n)
        .toList();
    for (final field in ['outbox', 'conflicts']) {
      final originals = entries(bundle, field);
      final identity = field == 'outbox' ? 'mutationId' : 'noteId';
      state[field] = entries(state, field).map((current) {
        final matching = originals.where(
          (e) =>
              e[identity] == current[identity] &&
              (field == 'outbox' ||
                  reference(
                        state,
                        Map<String, Object?>.from(e['local'] as Map),
                      ) ==
                      reference(
                        state,
                        Map<String, Object?>.from(current['local'] as Map),
                      )),
        );
        if (matching.isEmpty) return current;
        final original = matching.first;
        if (field == 'outbox') {
          return {
            ...original,
            'retryCount': current['retryCount'],
            'lastError': current['lastError'] ?? original['lastError'],
            'blocked':
                original['blocked'] == true ||
                current['lastError'] == 'forbidden',
          };
        }
        final oldRemote = original['remote'] as Map?;
        final newRemote = current['remote'] as Map?;
        return {
          ...original,
          'local': {
            'pinnedAt': null,
            'attachments': <Object?>[],
            ...Map<String, Object?>.from(original['local'] as Map),
          },
          'remote':
              newRemote != null &&
                  (newRemote['revision'] as int) >
                      ((oldRemote?['revision'] as int?) ?? 0)
              ? {'pinnedAt': null, 'attachments': <Object?>[], ...newRemote}
              : oldRemote == null
              ? null
              : {'pinnedAt': null, 'attachments': <Object?>[], ...oldRemote},
        };
      }).toList();
    }
  }

  /// Add only the new security fields to v2 records; unknown fields still fail
  /// the strict v3 codec. This is used exclusively by bounded migration.
  static Map<String, Object?> migrateV2(Map<String, Object?> old) {
    final migrated = {...old, 'schemaVersion': 3};
    Map<String, Object?> note(Map value) => {
      'protected': false,
      'protectionRevision': 0,
      'contentAvailable': true,
      ...Map<String, Object?>.from(value),
    };
    migrated['notes'] = (old['notes'] as List)
        .map((n) => note(n as Map))
        .toList();
    migrated['conflicts'] = (old['conflicts'] as List).map((e) {
      final c = Map<String, Object?>.from(e as Map);
      return {
        ...c,
        'local': note(c['local'] as Map),
        'remote': c['remote'] == null ? null : note(c['remote'] as Map),
      };
    }).toList();
    return migrated;
  }
}
