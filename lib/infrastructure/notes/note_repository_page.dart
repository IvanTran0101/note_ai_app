part of 'note_repository.dart';

extension _NoteRepositoryPage on NoteRepository {
  Future<NotePage> _queryPage(String actor, NotePageQuery query) =>
      _enqueue(() async {
        final fence = _captureWrite();
        if (actor != fence.account) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
        }
        final state = await _readStateFor(actor);
        _requireWrite(fence);
        final choices = <LabelSelection, String>{};
        final matches = <LocalNoteState>[];
        final keyword = query.keyword.trim().toLowerCase();
        final catalog = {
          for (final l in state.labels)
            if (!l.isDeleted) l.id: l.name,
        };
        for (final note in state.notes) {
          if (note.isDeleted) continue;
          final owned = note.ownerId == actor;
          if (owned != (query.scope == NotePageScope.owned)) continue;
          if (!owned &&
              (note.share?.isActive != true ||
                  note.share?.recipientId != actor)) {
            continue;
          }
          // Match existing safe list projection. Protected payloads are never
          // searched or used for label facets, even when a key is cached.
          final readable = note.contentAvailable && !note.protection.enabled;
          final labels = <LabelSelection, String>{};
          if (readable) {
            for (final id in note.labelIds) {
              final name = owned
                  ? catalog[id]
                  : note.labelProjections
                        .where((l) => l.id == id)
                        .firstOrNull
                        ?.name;
              if (name != null) labels[(ownerId: note.ownerId, id: id)] = name;
            }
            choices.addAll(labels);
          }
          if (!readable && (keyword.isNotEmpty || query.labels.isNotEmpty)) {
            continue;
          }
          if (keyword.isNotEmpty &&
              !note.title.toLowerCase().contains(keyword) &&
              !note.content.toLowerCase().contains(keyword)) {
            continue;
          }
          if (!query.labels.every(labels.containsKey)) continue;
          matches.add(note);
        }
        matches.sort(
          (a, b) => compareNotePageKeys(
            (
              pin: query.pinFirst ? a.pinnedAt : null,
              date: query.byCreatedAt ? a.createdAt : a.updatedAt,
              owner: a.ownerId,
              id: a.id,
            ),
            (
              pin: query.pinFirst ? b.pinnedAt : null,
              date: query.byCreatedAt ? b.createdAt : b.updatedAt,
              owner: b.ownerId,
              id: b.id,
            ),
          ),
        );
        final total = matches.length;
        final page = total == 0
            ? 0
            : query.page.clamp(0, (total - 1) ~/ query.size);
        // Only this slice is converted to aggregates/DTOs. The encrypted store
        // still decodes its whole account snapshot; this is not disk paging.
        final rows = matches
            .skip(page * query.size)
            .take(query.size)
            .map(
              (n) => NoteDto.fromDomain(
                _domainNoteFromLocal(n, metadataOnly: n.protection.enabled),
              ),
            );
        _requireWrite(fence);
        return NotePage(
          notes: rows,
          total: total,
          page: page,
          size: query.size,
          labelChoices: choices,
        );
      });
}
