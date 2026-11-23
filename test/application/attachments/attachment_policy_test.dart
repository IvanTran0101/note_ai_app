import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_policy.dart';

void main() {
  String validate(
    String name,
    String mime,
    int size, {
    int count = 0,
    int reserved = 0,
  }) => AttachmentPolicy.validate(
    fileName: name,
    mimeType: mime,
    sizeBytes: size,
    existing: const [],
    reservedCount: count,
    reservedBytes: reserved,
  );

  test('official per-type byte limits are inclusive', () {
    for (final e in AttachmentPolicy.types.entries) {
      expect(validate('a.${e.key}', e.value.mime, e.value.limit), e.value.mime);
      expect(
        () => validate('a.${e.key}', e.value.mime, e.value.limit + 1),
        throwsArgumentError,
      );
    }
  });
  test('reject empty, path, MIME mismatch and unsupported active formats', () {
    expect(() => validate('a.txt', 'text/plain', 0), throwsArgumentError);
    expect(() => validate('../a.jpg', 'image/jpeg', 12), throwsArgumentError);
    expect(() => validate('a.png', 'image/jpeg', 12), throwsArgumentError);
    expect(() => validate('a.svg', 'image/svg+xml', 12), throwsArgumentError);
  });
  test('queued reservations count towards note quotas', () {
    expect(
      () => validate('a.txt', 'text/plain', 1, count: 10),
      throwsArgumentError,
    );
    expect(validate('a.txt', 'text/plain', 1, count: 9), 'text/plain');
    expect(
      () => validate(
        'a.txt',
        'text/plain',
        2,
        reserved: AttachmentPolicy.maxNoteBytes - 1,
      ),
      throwsArgumentError,
    );
    expect(
      validate(
        'a.txt',
        'text/plain',
        1,
        reserved: AttachmentPolicy.maxNoteBytes - 1,
      ),
      'text/plain',
    );
    expect(AttachmentPolicy.maxCacheBytes, 250 * 1024 * 1024);
  });
}
