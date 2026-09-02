import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/infrastructure/notes/note_mapper.dart';
import 'package:note_ai_app/infrastructure/notes/note_record.dart';

void main() {
  final DateTime createdAt = DateTime.utc(2025, 1, 2, 3, 4, 5);
  final DateTime updatedAt = createdAt.add(const Duration(hours: 2));

  Note buildNote() {
    return Note.reconstitute(
      id: 'note-1',
      ownerId: 'user-42',
      title: 'Shopping list',
      content: 'Milk, eggs, bread',
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  group('NoteMapper', () {
    test('round-trips a Note without changing its fields', () {
      final Note original = buildNote();

      final NoteRecord record = NoteMapper.toRecord(original);
      final Note restored = NoteMapper.toDomain(record);

      expect(restored.id, original.id);
      expect(restored.ownerId, original.ownerId);
      expect(restored.title, original.title);
      expect(restored.content, original.content);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('preserves distinct createdAt and updatedAt values', () {
      final NoteRecord record = NoteMapper.toRecord(buildNote());

      expect(record.createdAt, createdAt);
      expect(record.updatedAt, updatedAt);
      expect(NoteMapper.toDomain(record).updatedAt, updatedAt);
    });
  });

  group('NoteRecord JSON', () {
    test('serializes timestamps as ISO-8601 strings and restores them', () {
      final NoteRecord record = NoteMapper.toRecord(buildNote());

      final Map<String, Object?> json = record.toJson();
      expect(json, <String, Object?>{
        'id': 'note-1',
        'ownerId': 'user-42',
        'title': 'Shopping list',
        'content': 'Milk, eggs, bread',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      });

      final NoteRecord restored = NoteRecord.fromJson(json);
      expect(restored.id, record.id);
      expect(restored.ownerId, record.ownerId);
      expect(restored.title, record.title);
      expect(restored.content, record.content);
      expect(restored.createdAt, createdAt);
      expect(restored.updatedAt, updatedAt);
    });
  });

  group('NoteRecord.fromJson validation', () {
    Map<String, Object?> validJson() {
      return <String, Object?>{
        'id': 'note-1',
        'ownerId': 'user-42',
        'title': 'Shopping list',
        'content': 'Milk, eggs, bread',
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
    }

    test('rejects a missing field with FormatException', () {
      final json = validJson()..remove('content');

      expect(() => NoteRecord.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('rejects a field with the wrong type', () {
      final json = validJson()..['title'] = 42;

      expect(() => NoteRecord.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('rejects an invalid timestamp', () {
      final json = validJson()..['updatedAt'] = 'not-a-timestamp';

      expect(() => NoteRecord.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('rejects an unknown field', () {
      final json = validJson()..['unexpected'] = true;

      expect(() => NoteRecord.fromJson(json), throwsA(isA<FormatException>()));
    });
  });
}
