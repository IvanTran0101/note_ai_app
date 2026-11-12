import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/labels/label.dart';
import 'package:note_ai_app/domain/notes/note.dart';

void main() {
  final now = DateTime.utc(2026, 10, 4), later = DateTime.utc(2026, 10, 5);
  Label label(String id, {String owner = 'owner', String name = 'Công việc'}) =>
      Label.create(id: id, ownerId: owner, name: name, now: now);
  Note note() => Note.create(
    id: 'n',
    ownerId: 'owner',
    title: 'T',
    content: 'C',
    now: now,
  );
  test('names allow duplicates with different immutable IDs', () {
    expect(label('a').name, label('b').name);
    expect(label('a').id, isNot(label('b').id));
  });
  test(
    'name limits count Unicode code points, trim and reject control text',
    () {
      expect(label('a', name: '😀' * 64).name.runes.length, 64);
      expect(() => label('a', name: '😀' * 65), throwsArgumentError);
      expect(() => label('a', name: 'a\nb'), throwsArgumentError);
      expect(label('a', name: '  Việt Nam  ').name, 'Việt Nam');
    },
  );
  test('rename and deletion no-op preserve timestamps and identity', () {
    final value = label('a');
    value.rename('Công việc', later);
    expect(value.updatedAt, now);
    value.rename('Học', later);
    expect(value.id, 'a');
    value.delete(later);
    value.delete(later.add(const Duration(days: 1)));
    expect(value.deletedAt, later);
    expect(() => value.rename('Other', later), throwsStateError);
  });
  test('membership is canonical, immutable and capped', () {
    expect(freezeLabelIds(['b', 'a', 'b']), ['a', 'b']);
    expect(
      () => freezeLabelIds(List.generate(33, (i) => '$i')),
      throwsArgumentError,
    );
    expect(() => freezeLabelIds(['a']).add('b'), throwsUnsupportedError);
  });
  test('attach detach no-op, tombstone does not destroy note', () {
    final n = note(), l = label('a');
    n.attachLabel(l, later);
    n.attachLabel(l, later.add(const Duration(days: 1)));
    expect(n.updatedAt, later);
    l.delete(later);
    expect(n.labelIds, ['a']);
    expect(n.title, 'T');
    n.detachLabel('a', later);
    n.detachLabel('a', later.add(const Duration(days: 1)));
    expect(n.labelIds, isEmpty);
    expect(n.updatedAt, later);
  });
  test('reject foreign or deleted attachment', () {
    expect(
      () => note().attachLabel(label('a', owner: 'foreign'), later),
      throwsArgumentError,
    );
    final l = label('a')..delete(later);
    expect(() => note().attachLabel(l, later), throwsArgumentError);
  });
  test(
    'new membership requires fresh liveness, unchanged tombstone survives',
    () {
      final l = label('a')..delete(later);
      expect(
        () => requireLabelAssociations(
          ownerId: 'owner',
          before: [],
          after: ['a'],
          catalog: [l],
        ),
        throwsStateError,
      );
      requireLabelAssociations(
        ownerId: 'owner',
        before: ['a'],
        after: ['a'],
        catalog: [l],
      );
      requireLabelAssociations(
        ownerId: 'owner',
        before: ['a'],
        after: [],
        catalog: [l],
      );
    },
  );
  test('locked Note cannot expose label membership', () {
    expect(
      () => Note.reconstitute(
        id: 'n',
        ownerId: 'owner',
        title: '',
        content: '',
        createdAt: now,
        updatedAt: now,
        contentAvailable: false,
        labelIds: ['a'],
      ),
      throwsArgumentError,
    );
  });
}
