import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/infrastructure/attachments/attachment_picker_cleanup_io.dart';

void main() {
  test(
    'cleanup deletes only selected private cache copy and preserves original',
    () async {
      final container = await Directory.systemTemp.createTemp(
        'noteflow-picker-qa-',
      );
      addTearDown(() async {
        final resolved = await container.resolveSymbolicLinks();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
          throw StateError('Invalid test cleanup path');
        }
        await container.delete(recursive: true);
      });
      final cache = await Directory('${container.path}/cache').create();
      final copy = await File('${cache.path}/selected.txt')
          .writeAsString('temporary');
      final original = await File('${container.path}/original.txt')
          .writeAsString('original');
      await removePickerOwnedCopy(original.path, cache);
      expect(await original.exists(), true);
      await removePickerOwnedCopy(copy.path, cache);
      expect(await copy.exists(), false);
      expect(await original.readAsString(), 'original');
      await removePickerOwnedCopy(copy.path, cache); // idempotent
    },
  );
}
