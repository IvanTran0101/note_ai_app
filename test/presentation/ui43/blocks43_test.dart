import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/notes/note_document.dart';
import 'package:note_ai_app/presentation/editor/editor_renderers.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';

void main() {
  testWidgets(
    'headings, lists, task, and quote retain readable reference styling',
    (tester) async {
      final adapter = _adapter([
        for (var level = 1; level <= 4; level++)
          DocumentBlock(
            id: 'heading-$level',
            kind: DocumentBlockKind.heading,
            level: level,
            runs: [DocumentText('Heading level $level')],
          ),
        DocumentBlock(
          id: 'bullet',
          kind: DocumentBlockKind.bulletedList,
          runs: [DocumentText('Bullet item')],
        ),
        DocumentBlock(
          id: 'number',
          kind: DocumentBlockKind.numberedList,
          runs: [DocumentText('Numbered item')],
        ),
        DocumentBlock(
          id: 'task',
          kind: DocumentBlockKind.todo,
          checked: true,
          runs: [DocumentText('Checked task')],
        ),
        DocumentBlock(
          id: 'quote',
          kind: DocumentBlockKind.quote,
          runs: [DocumentText('Quote text')],
        ),
      ]);
      final focus = FocusNode();

      try {
        await _pumpEditor(tester, adapter, focus, scale: 2);

        for (var level = 1; level <= 4; level++) {
          final richText = _richTextFor(tester, 'Heading level $level');
          final styles = _spanStylesFor(richText, 'Heading level $level');
          expect(styles, isNotEmpty);
          expect(
            styles.every(
              (style) => style.fontSize == [30, 24, 20, 18][level - 1],
            ),
            isTrue,
            reason: 'Heading $level should keep its document hierarchy.',
          );
          expect(
            richText.textScaler.scale([30.0, 24.0, 20.0, 18.0][level - 1]),
            closeTo([60.0, 48.0, 40.0, 36.0][level - 1], .01),
            reason: 'Heading $level should honor the 2x text scale.',
          );
        }

        for (final text in [
          'Bullet item',
          'Numbered item',
          'Checked task',
          'Quote text',
        ]) {
          final richText = _richTextFor(tester, text);
          expect(
            richText.textScaler.scale(kIsWeb ? 16 : 17),
            closeTo(kIsWeb ? 32 : 34, .01),
          );
        }

        final task = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(task.value, isTrue);
        expect(task.semanticLabel, 'Task complete');
        final taskStyles = _spanStylesFor(
          _richTextFor(tester, 'Checked task'),
          'Checked task',
        );
        expect(taskStyles, isNotEmpty);
        expect(
          taskStyles.every(
            (style) =>
                style.decoration == TextDecoration.lineThrough &&
                style.color ==
                    Theme.of(tester.element(find.byType(Scaffold)))
                        .colorScheme
                        .onSurfaceVariant,
          ),
          isTrue,
        );
        final taskSize = kIsWeb ? 24.0 : 48.0;
        expect(
          find.ancestor(
            of: find.byType(Checkbox),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SizedBox &&
                  widget.width == taskSize &&
                  widget.height == taskSize,
            ),
          ),
          findsOneWidget,
          reason: 'Keep the established platform task target size.',
        );

        final quoteRule = find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == 3 &&
              (kIsWeb ? widget.height == 24 : widget.height == null),
        );
        expect(quoteRule, findsOneWidget);
        final ruleColor = tester.widget<ColoredBox>(
          find.descendant(of: quoteRule, matching: find.byType(ColoredBox)),
        );
        expect(
          ruleColor.color,
          Theme.of(tester.element(find.byType(Scaffold))).colorScheme.onSurface,
        );

        if (kIsWeb) {
          final marker = find.text('●');
          expect(marker, findsOneWidget);
          final markerScaler = tester.widget<Text>(marker).textScaler;
          expect(markerScaler, isNotNull);
          expect(markerScaler!.scale(16), closeTo(16, .01));
          expect(
            find.ancestor(
              of: marker,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.constraints?.minWidth == 64 &&
                    widget.constraints?.minHeight == 44,
              ),
            ),
            findsOneWidget,
            reason: 'The marker column should remain legible at 2x scale.',
          );
        }

        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        adapter.dispose();
        focus.dispose();
      }
    },
  );

  testWidgets(
    'heading and quote children remain visible and separately accessible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final adapter = _adapter([
        DocumentBlock(
          id: 'heading-parent',
          kind: DocumentBlockKind.heading,
          level: 2,
          runs: [DocumentText('Heading parent')],
          children: [
            DocumentBlock(
              id: 'heading-child',
              kind: DocumentBlockKind.paragraph,
              runs: [DocumentText('Heading child')],
            ),
          ],
        ),
        DocumentBlock(
          id: 'quote-parent',
          kind: DocumentBlockKind.quote,
          runs: [DocumentText('Quote parent')],
          children: [
            DocumentBlock(
              id: 'quote-child',
              kind: DocumentBlockKind.paragraph,
              runs: [DocumentText('Quote child')],
            ),
          ],
        ),
      ]);
      final focus = FocusNode();

      try {
        await _pumpEditor(tester, adapter, focus, scale: 2);

        expect(find.text('Heading child', findRichText: true), findsOneWidget);
        expect(find.text('Quote child', findRichText: true), findsOneWidget);
        for (final childText in ['Heading child', 'Quote child']) {
          expect(
            find.ancestor(
              of: find.text(childText, findRichText: true),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Padding &&
                    widget.padding ==
                        const EdgeInsetsDirectional.only(start: 24),
              ),
            ),
            findsOneWidget,
            reason: 'Nested text should keep its existing visual indent.',
          );
        }

        final semanticBlocks = tester
            .widgetList<Semantics>(find.byType(Semantics))
            .map((widget) => widget.properties)
            .toList();
        expect(
          semanticBlocks.any(
            (block) =>
                block.label == 'Heading 2' && block.value == 'Heading parent',
          ),
          isTrue,
        );
        expect(
          semanticBlocks.any(
            (block) =>
                block.label == 'Quote text' && block.value == 'Quote parent',
          ),
          isTrue,
        );
        for (final childText in ['Heading child', 'Quote child']) {
          expect(
            semanticBlocks.any(
              (block) =>
                  block.label == 'Text block' && block.value == childText,
            ),
            isTrue,
            reason: 'Nested content needs its own accessible text block.',
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        adapter.dispose();
        focus.dispose();
      }
    },
  );
}

RichEditorAdapter _adapter(Iterable<DocumentBlock> blocks) => RichEditorAdapter(
  document: NoteDocument(blocks),
  legacyText: '',
  canEdit: () => false,
  isLive: () => true,
  accessGeneration: () => 1,
  onChanged: () {},
);

Future<void> _pumpEditor(
  WidgetTester tester,
  RichEditorAdapter adapter,
  FocusNode focus, {
  required double scale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        engine.AppFlowyEditorLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(1280, 720),
          textScaler: TextScaler.linear(scale),
        ),
        child: Builder(
          builder: (context) => Scaffold(
            body: SizedBox(
              width: 720,
              height: 520,
              child: engine.AppFlowyEditor(
                editorState: adapter.editor,
                focusNode: focus,
                editorStyle: documentEditorStyle(context),
                blockComponentBuilders: documentBlockBuilders(
                  context,
                  adapter,
                  focus,
                ),
                editable: false,
                shrinkWrap: true,
                disableKeyboardService: true,
                disableSelectionService: true,
                disableAutoScroll: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RichText _richTextFor(WidgetTester tester, String text) {
  final matches = tester.widgetList<RichText>(find.byType(RichText)).where((
    rich,
  ) {
    var contains = false;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) contains = true;
      return true;
    });
    return contains;
  });
  return matches.single;
}

List<TextStyle> _spanStylesFor(RichText richText, String text) {
  final styles = <TextStyle>[];
  richText.text.visitChildren((span) {
    if (span is TextSpan && span.text == text && span.style != null) {
      styles.add(span.style!);
    }
    return true;
  });
  return styles;
}
