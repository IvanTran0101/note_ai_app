import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/labels/note_query.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/labels/label_membership.dart';
import 'package:note_ai_app/domain/labels/label_projection.dart';

final time = DateTime.utc(2026, 10, 4);
NoteDto note(
  String id, {
  String owner = 'owner',
  String title = 'Học tập',
  String body = 'Flutter Việt Nam',
  List<String> ids = const [],
  bool available = true,
  bool protected = false,
  List<LabelProjection> projections = const [],
}) => NoteDto(
  id: id,
  ownerId: owner,
  title: title,
  content: body,
  createdAt: time,
  updatedAt: time,
  contentAvailable: available,
  isProtected: protected,
  labelMembership: LabelMembership(ids),
  labelProjections: projections,
);
LocalLabelState label(
  String id, {
  String name = 'Label',
  bool deleted = false,
}) => LocalLabelState(
  id: id,
  ownerId: 'owner',
  name: name,
  createdAt: time,
  updatedAt: time,
  deletedAt: deleted ? time : null,
);

void main() {
  final catalog = [label('a'), label('b'), label('gone', deleted: true)];
  List<NoteDto> query(
    List<NoteDto> notes, {
    String keyword = '',
    Set<LabelSelection> selected = const {},
  }) => queryNotes(
    notes,
    keyword: keyword,
    selected: selected,
    readable: (n) => n.contentAvailable && !n.isProtected,
    labelsFor: (n) => visibleLabels(
      n,
      catalog,
      actor: 'owner',
      readable: n.contentAvailable && !n.isProtected,
    ),
  );

  test('live keyword title OR body, trim/case and Vietnamese without accent folding', () {
    final notes = [note('a'), note('b', title: 'Other', body: 'Different')];
    expect(query(notes, keyword: '  HỌC ').single.id, 'a');
    expect(query(notes, keyword: 'việt').single.id, 'a');
    expect(query(notes, keyword: 'viet'), isEmpty);
  });
  test(
    'ALL labels AND keyword; owner/id pair prevents cross-owner collisions',
    () {
      final notes = [
        note('both', ids: ['a', 'b']),
        note('one', ids: ['a']),
        note(
          'shared',
          owner: 'other',
          ids: ['a', 'b'],
          projections: [
            LabelProjection(id: 'a', name: 'Other'),
            LabelProjection(id: 'b', name: 'Other'),
          ],
        ),
      ];
      expect(
        query(
          notes,
          keyword: 'flutter',
          selected: {(ownerId: 'owner', id: 'a'), (ownerId: 'owner', id: 'b')},
        ).single.id,
        'both',
      );
      expect(
        query(
          notes,
          keyword: 'absent',
          selected: {(ownerId: 'owner', id: 'a')},
        ),
        isEmpty,
      );
    },
  );
  test(
    'locked/revoked metadata cannot affect keyword or selected-label results',
    () {
      final notes = [
        note('locked', protected: true, ids: ['a']),
        note('revoked', available: false, ids: ['a']),
      ];
      expect(query(notes, keyword: 'Flutter'), isEmpty);
      expect(query(notes, selected: {(ownerId: 'owner', id: 'a')}), isEmpty);
      expect(
        query(notes).length,
        2,
      ); // Metadata rows remain accessible for unlock.
    },
  );
  test('rename resolves current names; tombstone/unknown hide effective chips without rewriting IDs', () {
    final n = note('n', ids: ['a', 'gone', 'unknown']);
    expect(
      visibleLabels(
        n,
        [label('a', name: 'Renamed'), label('gone', deleted: true)],
        actor: 'owner',
        readable: true,
      ).single.name,
      'Renamed',
    );
    expect(n.labelIds, ['a', 'gone', 'unknown']);
    expect(query([n], selected: {(ownerId: 'owner', id: 'gone')}), isEmpty);
  });
  test(
    'recipient uses sanitized current-note projection, never foreign catalog',
    () {
      final n = note(
        's',
        owner: 'other',
        ids: ['a'],
        projections: [
          LabelProjection(id: 'a', name: 'Shared name'),
          LabelProjection(id: 'private', name: 'Unrelated'),
        ],
      );
      expect(
        visibleLabels(
          n,
          catalog,
          actor: 'recipient',
          readable: true,
        ).single.name,
        'Shared name',
      );
      expect(
        visibleLabels(n, catalog, actor: 'recipient', readable: false),
        isEmpty,
      );
    },
  );
}
