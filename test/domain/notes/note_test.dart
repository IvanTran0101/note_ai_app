import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/notes/note.dart';

void main() {
  const id = 'note-1';
  const ownerId = 'user-42';
  const title = 'Shopping list';
  const content = 'Milk, eggs, bread';
  final createdAt = DateTime.utc(2025, 1, 2, 3, 4, 5);

  Note buildNote(DateTime now) {
    return Note.create(
      id: id,
      ownerId: ownerId,
      title: title,
      content: content,
      now: now,
    );
  }

  group('Note.create', () {
    test(
      'initializes id, ownerId, title, and content from the supplied values',
      () {
        final note = buildNote(createdAt);

        expect(note.id, id);
        expect(note.ownerId, ownerId);
        expect(note.title, title);
        expect(note.content, content);
      },
    );

    test('seeds createdAt and updatedAt from the supplied now', () {
      final note = buildNote(createdAt);

      expect(note.createdAt, createdAt);
      expect(note.updatedAt, createdAt);
    });

    test('rejects blank text and preserves surrounding formatting', () {
      expect(
        () => Note.create(
          id: id,
          ownerId: ownerId,
          title: '  ',
          content: content,
          now: createdAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => Note.create(
          id: id,
          ownerId: ownerId,
          title: title,
          content: '\n\t',
          now: createdAt,
        ),
        throwsArgumentError,
      );
      final Note formatted = Note.create(
        id: id,
        ownerId: ownerId,
        title: '  $title  ',
        content: '\n$content\n',
        now: createdAt,
      );
      expect(formatted.title, '  $title  ');
      expect(formatted.content, '\n$content\n');
    });
  });

  group('Note.reconstitute', () {
    test('restores every field from persistence data', () {
      final updatedAt = createdAt.add(const Duration(hours: 1));

      final note = Note.reconstitute(
        id: id,
        ownerId: ownerId,
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(note.id, id);
      expect(note.ownerId, ownerId);
      expect(note.title, title);
      expect(note.content, content);
      expect(note.createdAt, createdAt);
      expect(note.updatedAt, updatedAt);
    });

    test('preserves an updatedAt that differs from createdAt', () {
      final updatedAt = createdAt.add(const Duration(days: 2));

      final note = Note.reconstitute(
        id: id,
        ownerId: ownerId,
        title: title,
        content: content,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(note.createdAt, isNot(note.updatedAt));
      expect(note.updatedAt, updatedAt);
    });

    test('keeps legacy blank text readable', () {
      final Note note = Note.reconstitute(
        id: id,
        ownerId: ownerId,
        title: '',
        content: '  ',
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      expect(note.title, isEmpty);
      expect(note.content, '  ');
    });
  });

  group('Note.rename', () {
    test('replaces the title and records the supplied now as updatedAt', () {
      final note = buildNote(createdAt);
      final renamedAt = createdAt.add(const Duration(hours: 1));
      const renamedTitle = 'Updated shopping list';

      note.rename(renamedTitle, renamedAt);

      expect(note.title, renamedTitle);
      expect(note.updatedAt, renamedAt);
    });

    test('does not mutate id, ownerId, createdAt, or content', () {
      final note = buildNote(createdAt);
      final renamedAt = createdAt.add(const Duration(hours: 1));

      note.rename('Another title', renamedAt);

      expect(note.id, id);
      expect(note.ownerId, ownerId);
      expect(note.createdAt, createdAt);
      expect(note.content, content);
    });
  });

  group('Note.replaceContent', () {
    test('replaces the content and records the supplied now as updatedAt', () {
      final note = buildNote(createdAt);
      final replacedAt = createdAt.add(const Duration(hours: 2));
      const replacedContent = 'Butter, flour, sugar';

      note.replaceContent(replacedContent, replacedAt);

      expect(note.content, replacedContent);
      expect(note.updatedAt, replacedAt);
    });

    test('does not mutate id, ownerId, createdAt, or title', () {
      final note = buildNote(createdAt);
      final replacedAt = createdAt.add(const Duration(hours: 2));

      note.replaceContent('Brand new body', replacedAt);

      expect(note.id, id);
      expect(note.ownerId, ownerId);
      expect(note.createdAt, createdAt);
      expect(note.title, title);
    });

    test('rejects empty content', () {
      final Note note = buildNote(createdAt);
      expect(() => note.replaceContent('  ', createdAt), throwsArgumentError);
      expect(note.content, content);
    });
  });

  group('Note.pin', () {
    test('pin is idempotent and unpin followed by pin gets a new time', () {
      final Note note = buildNote(createdAt);
      final DateTime firstPin = createdAt.add(const Duration(hours: 1));
      final DateTime unpinned = firstPin.add(const Duration(hours: 1));
      final DateTime secondPin = unpinned.add(const Duration(hours: 1));

      note.pin(firstPin);
      note.pin(secondPin);
      expect(note.pinnedAt, firstPin);
      expect(note.updatedAt, firstPin);

      note.unpin(unpinned);
      expect(note.pinnedAt, isNull);
      expect(note.updatedAt, unpinned);
      note.pin(secondPin);
      expect(note.pinnedAt, secondPin);
    });
  });

  test('toString does not expose note text', () {
    final Note note = buildNote(createdAt);
    expect(note.toString(), isNot(contains(title)));
    expect(note.toString(), isNot(contains(content)));
  });

  group('timestamps', () {
    test(
      'updatedAt advances with each mutation while createdAt stays fixed',
      () {
        final note = buildNote(createdAt);
        final firstMutationAt = createdAt.add(const Duration(minutes: 5));
        final secondMutationAt = firstMutationAt.add(
          const Duration(minutes: 5),
        );

        note.rename('Renamed', firstMutationAt);
        expect(note.updatedAt, firstMutationAt);

        note.replaceContent('Updated body', secondMutationAt);
        expect(note.updatedAt, secondMutationAt);

        expect(note.createdAt, createdAt);
        expect(note.updatedAt.isAfter(note.createdAt), isTrue);
      },
    );
  });

  group('identity immutability', () {
    test('id, ownerId, and createdAt survive repeated mutations', () {
      final note = buildNote(createdAt);

      note.rename('First rename', createdAt.add(const Duration(minutes: 1)));
      note.replaceContent(
        'First replacement',
        createdAt.add(const Duration(minutes: 2)),
      );
      note.rename('Second rename', createdAt.add(const Duration(minutes: 3)));
      note.replaceContent(
        'Second replacement',
        createdAt.add(const Duration(minutes: 4)),
      );

      expect(note.id, id);
      expect(note.ownerId, ownerId);
      expect(note.createdAt, createdAt);
    });
  });
}
