import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:note_ai_app/domain/notes/note_body.dart';
import 'package:note_ai_app/presentation/notes/note_rich_text.dart';

void main() {
  const bodyKey = ValueKey('test-body');
  Future<
    ({TextEditingController content, GlobalKey<NoteRichTextScopeState> key})
  >
  host(
    WidgetTester tester, {
    String text = 'First paragraph',
    bool readOnly = false,
    double width = 390,
    bool dark = false,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final content = TextEditingController(text: text);
    final focus = FocusNode();
    final key = GlobalKey<NoteRichTextScopeState>();
    addTearDown(content.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              disableAnimations: reduced,
            ),
            child: NoteRichTextScope(
              key: key,
              controller: content,
              focusNode: focus,
              readOnly: readOnly,
              child: Column(
                children: [
                  const NoteTextToolbar(),
                  Expanded(
                    child: SingleChildScrollView(
                      child: NoteRichBody(
                        fieldKey: bodyKey,
                        placeholder: 'Content',
                        style: const TextStyle(fontSize: 16),
                        plainEditor: TextField(
                          key: bodyKey,
                          controller: content,
                          focusNode: focus,
                          readOnly: readOnly,
                          maxLines: null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (content: content, key: key);
  }

  testWidgets(
    'selected text gets persistent emphasis and native rich editing',
    (tester) async {
      final fixture = await host(tester);
      fixture.content.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pumpAndSettle();
      expect(find.byType(quill.QuillEditor), findsOneWidget);
      expect(NoteBody.delta(fixture.content.text)?.first, {
        'insert': 'First',
        'attributes': {'bold': true},
      });
      expect(NoteBody.plainText(fixture.content.text), 'First paragraph');
      fixture.key.currentState!.editor.replaceText(
        5,
        0,
        ' note',
        const TextSelection.collapsed(offset: 10),
      );
      await tester.pump();
      expect(NoteBody.plainText(fixture.content.text), 'First note paragraph');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'heading, size, color survive reopen and empty edits stay empty',
    (tester) async {
      final fixture = await host(tester);
      fixture.content.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 15,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Text style'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('Heading 2'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Font size'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('24'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('note-text-toolbar')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Text color'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('Blue'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final saved = fixture.content.text;
      final operations = NoteBody.delta(saved)!;
      expect(
        operations.any((op) => (op['attributes'] as Map?)?['header'] == 2),
        isTrue,
      );
      expect(operations.first['attributes'], containsPair('size', '24'));
      expect(operations.first['attributes'], containsPair('color', '#1565C0'));
      await tester.pumpWidget(const SizedBox.shrink());
      final reopened = await host(tester, text: saved, dark: true);
      expect(reopened.key.currentState!.rich, isTrue);
      expect(
        reopened.key.currentState!.editor.document.toPlainText(),
        'First paragraph\n',
      );
      reopened.key.currentState!.editor.replaceText(
        0,
        15,
        '',
        const TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      expect(reopened.content.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plain undo/redo retains content and external snapshots replace rich document',
    (tester) async {
      final fixture = await host(tester);
      await tester.enterText(find.byKey(bodyKey), 'Changed');
      await tester.pump();
      fixture.key.currentState!.history(undo: true);
      await tester.pumpAndSettle();
      expect(fixture.content.text, 'First paragraph');
      fixture.key.currentState!.history(undo: false);
      await tester.pumpAndSettle();
      expect(fixture.content.text, 'Changed');
      fixture.content.text = NoteBody.encode([
        {
          'insert': 'Remote',
          'attributes': {'italic': true},
        },
        {'insert': '\n'},
      ]);
      await tester.pumpAndSettle();
      expect(
        fixture.key.currentState!.editor.document.toPlainText(),
        'Remote\n',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets(
      'toolbar adapts at $width with reduced motion and disabled editing',
      (tester) async {
        final fixture = await host(
          tester,
          width: width,
          readOnly: true,
          reduced: true,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == 'Bold',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<PopupMenuButton<int>>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is PopupMenuButton<int> &&
                      widget.tooltip == 'Text style',
                ),
              )
              .enabled,
          isFalse,
        );
        fixture.key.currentState!.format(quill.Attribute.bold);
        expect(fixture.content.text, 'First paragraph');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
