part of 'note_repository.dart';

extension _NoteRepositoryPage on NoteRepository {
  Future<LocalNoteState?> _findPagedNote(String actor, String id) async {
    final store = _storeFor(actor);
    if (store is ILocalNotePageStore) {
      final result = await (store as ILocalNotePageStore)
          .withNotePageView<LocalNoteState?>((view) async {
            if (view.accountId != actor) {
              throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
            }
            final header = view.headers
                .where((n) => n.referenceFor(actor) == id)
                .firstOrNull;
            if (header == null || header.isDeleted) return null;
            return header.protection.enabled || !header.contentAvailable
                ? header
                : await view.readNote(header);
          });
      // Protected content remains exclusively in the existing password vault.
      if (result == null ||
          !result.protection.enabled ||
          !(accessGuard?.allows(
                ownerId: result.ownerId,
                noteId: result.id,
                protection: result.protection,
                operation: NoteOperation.read,
              ) ??
              false)) {
        return result;
      }
    }
    return NoteRepository._findNote(await _readStateFor(actor), id);
  }

  Future<NotePage> _queryPage(String actor, NotePageQuery query) =>
      _enqueue(() async {
        final fence = _captureWrite();
        if (actor != fence.account) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
        }
        final store = _storeFor(actor);
        if (store is ILocalNotePageStore) {
          final result = await (store as ILocalNotePageStore).withNotePageView((
            view,
          ) async {
            if (view.accountId != actor) {
              throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
            }
            final page = await _selectPage(
              actor,
              query,
              view.headers,
              view.labels,
              view.readNote,
            );
            await view.requireCurrent();
            _requireWrite(fence);
            return page;
          });
          _requireWrite(fence);
          return result;
        }
        final state = await _readStateFor(actor);
        final result = await _selectPage(
          actor,
          query,
          state.notes,
          state.labels,
          (n) async => n,
        );
        _requireWrite(fence);
        return result;
      });

  Future<NotePage> _selectPage(
    String actor,
    NotePageQuery query,
    List<LocalNoteState> headers,
    List<LocalLabelState> catalogRows,
    Future<LocalNoteState> Function(LocalNoteState) load,
  ) async {
    final choices = <LabelSelection, String>{};
    final matches = <LocalNoteState>[];
    final keyword = query.keyword.trim().toLowerCase();
    final catalog = {
      for (final l in catalogRows)
        if (!l.isDeleted) l.id: l.name,
    };
    for (final note in headers) {
      if (note.isDeleted) continue;
      final owned = note.ownerId == actor;
      if (owned != (query.scope == NotePageScope.owned)) continue;
      if (!owned &&
          (note.share?.isActive != true || note.share?.recipientId != actor)) {
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
      if (!query.labels.every(labels.containsKey)) continue;
      if (keyword.isNotEmpty) {
        final payload = await load(note);
        if (!payload.title.toLowerCase().contains(keyword) &&
            !payload.content.toLowerCase().contains(keyword)) {
          continue;
        }
      }
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
    final rows = <NoteDto>[];
    for (final header in matches.skip(page * query.size).take(query.size)) {
      final note = header.protection.enabled || !header.contentAvailable
          ? header
          : await load(header);
      rows.add(
        NoteDto.fromDomain(
          _domainNoteFromLocal(note, metadataOnly: note.protection.enabled),
        ),
      );
    }
    return NotePage(
      notes: rows,
      total: total,
      page: page,
      size: query.size,
      labelChoices: choices,
    );
  }
}
