import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

void main() {
  testWidgets('bounded document capacity renders and scrolls to the end', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    final adapter = RichEditorAdapter(
      document: NoteDocument([
        for (var i = 0; i < 512; i++)
          DocumentBlock(
            id: 'block$i',
            kind: DocumentBlockKind.paragraph,
            runs: [
              DocumentText(
                'Block $i: ${List.filled(8, 'local text data ').join()}',
              ),
            ],
          ),
      ]),
      legacyText: '',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      focus.dispose();
    });
    try {
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            engine.AppFlowyEditorLocalizations.delegate,
          ],
          home: Scaffold(
            body: RichNoteEditor(
              adapter: adapter,
              focusNode: focus,
              header: const SizedBox(height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final buildMs = watch.elapsedMilliseconds;
      adapter.editor.service.scrollService!.jumpToBottom();
      await tester.pumpAndSettle();
      debugPrint(
        'M09_CAPACITY platform=${kIsWeb ? 'web' : 'vm'} blocks=512 '
        'projection=${adapter.plainText.length} build_ms=$buildMs '
        'scroll_ms=${watch.elapsedMilliseconds - buildMs}',
      );
      final last = adapter.editor.document.root.children.last;
      expect(last.key.currentContext, isNotNull);
      expect(last.rect.bottom, greaterThan(0));
      expect(last.rect.top, lessThan(900));
      expect(adapter.visibleDocument.blocks.length, 512);
      expect(adapter.revision, 0);
      watch.reset();
      await adapter.editor.apply(
        adapter.editor.transaction..insertText(last, last.delta!.length, 'Z'),
      );
      await tester.pumpAndSettle();
      debugPrint('M09_CAPACITY edit_ms=${watch.elapsedMilliseconds}');
      expect(adapter.visibleDocument.blocks.length, 512);
      expect(adapter.plainText.endsWith('Z'), isTrue);
      expect(adapter.revision, 1);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
