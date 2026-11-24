import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/presentation/notes/note_ordering.dart';

void main() {
  final DateTime time = DateTime.utc(2026, 10, 1);

  NoteDto note({
    required String id,
    String ownerId = 'owner',
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? pinnedAt,
  }) => NoteDto(
    id: id,
    ownerId: ownerId,
    title: id,
    content: id,
    createdAt: createdAt ?? time,
    updatedAt: updatedAt ?? time,
    pinnedAt: pinnedAt,
  );

  test('puts pins first; equal pin times use owner and id, not updatedAt', () {
    final DateTime pin = time.add(const Duration(days: 1));
    final List<NoteDto> input = <NoteDto>[
      note(id: 'unpinned', updatedAt: time.add(const Duration(days: 10))),
      note(id: 'z', ownerId: 'owner-b', pinnedAt: pin, updatedAt: time),
      note(
        id: 'b',
        ownerId: 'owner-a',
        pinnedAt: pin,
        updatedAt: time.add(const Duration(days: 5)),
      ),
      note(
        id: 'older-pin',
        pinnedAt: time,
        updatedAt: time.add(const Duration(days: 20)),
      ),
    ];

    expect(sortNotes(input).map((NoteDto item) => item.id), <String>[
      'b',
      'z',
      'older-pin',
      'unpinned',
    ]);
    expect(input.first.id, 'unpinned');
  });

  test('un-pinned notes use selected date then owner/id for ties', () {
    final List<NoteDto> notes = <NoteDto>[
      note(id: 'z', ownerId: 'owner-b'),
      note(id: 'b', ownerId: 'owner-a'),
      note(
        id: 'created-later',
        createdAt: time.add(const Duration(days: 1)),
        updatedAt: time.subtract(const Duration(days: 1)),
      ),
    ];

    expect(sortNotes(notes).map((NoteDto item) => item.id), <String>[
      'b',
      'z',
      'created-later',
    ]);
    expect(sortNotes(notes, byCreatedAt: true).first.id, 'created-later');
  });
}
