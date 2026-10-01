/// Serialized bundles are private to encrypted Infrastructure. Queue identities
/// and ordering stay in the root projection; content only lives in sealed bundles.
abstract final class NoteBundleProjection {
  static Map<String, Object?> bundle(Map<String, Object?> state, String id) => {
    'note': notes(state).firstWhere((n) => n['id'] == id),
    'outbox': entries(state, 'outbox').where((e) => e['noteId'] == id).toList(),
    'conflicts': entries(
      state,
      'conflicts',
    ).where((e) => e['noteId'] == id).toList(),
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
        .map((n) => n['id'] == id ? _private(n) : n)
        .toList();
    state['outbox'] = entries(
      state,
      'outbox',
    ).map((m) => m['noteId'] == id ? _pending(m) : m).toList();
    state['conflicts'] = entries(state, 'conflicts').map((c) {
      if (c['noteId'] != id) return c;
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
    final note = Map<String, Object?>.from(bundle['note'] as Map);
    final id = note['id'];
    final currentNote = notes(state).where((n) => n['id'] == id).firstOrNull;
    final hasPending = entries(state, 'outbox').any((m) => m['noteId'] == id);
    if (requireCurrentRevision &&
        !hasPending &&
        currentNote != null &&
        (currentNote['serverRevision'] as int) >
            (note['serverRevision'] as int)) {
      return;
    }
    state['notes'] = notes(state).map((n) => n['id'] == id ? note : n).toList();
    for (final field in ['outbox', 'conflicts']) {
      final originals = entries(bundle, field);
      final identity = field == 'outbox' ? 'mutationId' : 'noteId';
      state[field] = entries(state, field).map((current) {
        final matching = originals.where(
          (e) => e[identity] == current[identity],
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
          'remote':
              newRemote != null &&
                  (newRemote['revision'] as int) >
                      ((oldRemote?['revision'] as int?) ?? 0)
              ? newRemote
              : oldRemote,
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
