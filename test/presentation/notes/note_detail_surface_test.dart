import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';

import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/notes/note_detail_action_bar.dart';
import 'package:note_ai_app/presentation/notes/note_detail_editor_form.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_surface.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

void main() {
  const Key titleFieldKey = ValueKey<String>('note-detail-title-field');
  const Key contentFieldKey = ValueKey<String>('note-detail-content-field');
  const Key saveKey = ValueKey<String>('note-detail-save');
  const Key summarizeKey = ValueKey<String>('note-detail-summarize');

  /// Pumps the pure surface inside a bare [Material] host so that any
  /// [Scaffold] found in the tree could only come from the surface itself.
  Future<void> pumpSurface(
    WidgetTester tester, {
    required Size size,
    double textScale = 1.0,
    bool isDirty = false,
    bool showPageHeader = false,
    bool statusUnavailable = false,
    bool isSaving = false,
    String? error,
    bool hasSavedNote = true,
    String titleText = 'First note',
    String contentText = 'The first note body.',
    double keyboardHeight = 0,
    bool scaffoldHost = false,
    Widget Function(Widget, Widget)? richEditorBuilder,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0
      ..viewInsets = FakeViewPadding(bottom: keyboardHeight);
    addTearDown(tester.view.reset);

    final TextEditingController titleController = TextEditingController(
      text: titleText,
    );
    final TextEditingController contentController = TextEditingController(
      text: contentText,
    );
    final FocusNode contentFocusNode = FocusNode();
    addTearDown(titleController.dispose);
    addTearDown(contentController.dispose);
    addTearDown(contentFocusNode.dispose);

    Widget wrap(Widget child) => scaffoldHost ? Scaffold(body: child) : child;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          engine.AppFlowyEditorLocalizations.delegate,
        ],
        home: Builder(
          builder: (BuildContext context) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: wrap(
                Material(
                  child: NoteDetailSurface(
                    richEditorBuilder: richEditorBuilder,
                    titleController: titleController,
                    contentController: contentController,
                    contentFocusNode: contentFocusNode,
                    contentFieldContextKey: GlobalKey(),
                    copy: NoteDetailCopy.of(context),
                    pageTitle: titleText.isEmpty ? 'New note' : titleText,
                    showPageHeader: showPageHeader,
                    statusUnavailable: statusUnavailable,
                    hasSavedNote: hasSavedNote,
                    isDirty: isDirty,
                    error: error,
                    statusMessage: null,
                    actionBusy: false,
                    provisioningReader: null,
                    onProvisioningRetry: null,
                    onProvisioningCancel: null,
                    summary: null,
                    summaryStale: false,
                    isSaving: isSaving,
                    isSummarizing: false,
                    canSave: true,
                    canSummarize: true,
                    onSave: () {},
                    onSummarize: () {},
                    onMore: () {},
                    saveLabel: 'Save',
                    summarizeLabel: 'Summarize',
                    moreLabel: 'More',
                    savingLabel: 'Saving…',
                    summarizingLabel: 'Summarizing…',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (isSaving) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('IME header collapse retains the editor and its input service', (
    tester,
  ) async {
    final adapter = RichEditorAdapter(
      document: null,
      legacyText: 'body',
      canEdit: () => true,
      isLive: () => true,
      accessGeneration: () => 1,
      onChanged: () {},
    );
    final focus = FocusNode();
    await pumpSurface(
      tester,
      size: const Size(914, 411),
      showPageHeader: true,
      scaffoldHost: true,
      richEditorBuilder: (header, footer) => RichNoteEditor(
        adapter: adapter,
        focusNode: focus,
        header: header,
        footer: footer,
      ),
    );
    adapter.editor.selection = engine.Selection.collapsed(
      engine.Position(path: [0], offset: 4),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    final host = tester.state(find.byType(RichNoteEditor));
    final keyboard = adapter.editor.service.keyboardService;
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    await tester.pumpAndSettle();
    // Native caret scrolling is intentionally deferred while the keyboard
    // reports no height. Let that existing 250 ms settle delay complete before
    // asserting the caret's position in the resized editor viewport.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(RichNoteEditor)), same(host));
    expect(adapter.editor.service.keyboardService, same(keyboard));
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    final viewport = tester.getRect(find.byType(engine.AppFlowyEditor));
    final caret = adapter.editor.selectionRects().single;
    expect(caret.top, greaterThanOrEqualTo(viewport.top - 1));
    expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + 1));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'body_EDIT',
        selection: TextSelection.collapsed(offset: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.plainText, 'body_EDIT');
    await tester.pumpWidget(const SizedBox());
    adapter.dispose();
    focus.dispose();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'resized Scaffold retains physical IME knowledge inside its body',
    (tester) async {
      await pumpSurface(
        tester,
        size: const Size(914, 411),
        showPageHeader: true,
        keyboardHeight: 280,
        scaffoldHost: true,
      );
      expect(
        find.byType(NoteFlowPageHeader),
        kIsWeb ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await pumpSurface(
        tester,
        size: const Size(914, 411),
        showPageHeader: true,
        scaffoldHost: true,
      );
      expect(find.byType(NoteFlowPageHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'short native phone reclaims header only while keyboard is open',
    (tester) async {
      await pumpSurface(
        tester,
        size: const Size(914, 411),
        showPageHeader: true,
        keyboardHeight: 250,
      );
      expect(
        find.byType(NoteFlowPageHeader),
        kIsWeb ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NoteDetailActionBar),
        kIsWeb ? findsOneWidget : findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byKey(titleFieldKey)).style?.fontSize,
        kIsWeb ? 40 : 32,
      );
      await pumpSurface(
        tester,
        size: const Size(914, 411),
        showPageHeader: true,
      );
      expect(find.byType(NoteFlowPageHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('new note title hint uses compact page-title typography', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(390, 844), titleText: '');

    final Text titleHint = tester.widget<Text>(find.text('Title'));
    expect(titleHint.style?.fontSize, 32);
    expect(titleHint.style?.fontWeight, FontWeight.w700);
    expect(tester.widget<Text>(find.text('Content')).style?.fontSize, 16);
  });

  testWidgets('empty content starts as a compact multiline page block', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(390, 844), contentText: '');

    final Finder content = find.byKey(contentFieldKey);
    final TextField field = tester.widget<TextField>(content);
    expect(field.maxLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
    expect(tester.getSize(content).height, lessThan(80));
    expect(find.text('Content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long page titles wrap at compact widths without overflow', (
    WidgetTester tester,
  ) async {
    await pumpSurface(
      tester,
      size: const Size(390, 844),
      titleText:
          'A deliberately long page title that must wrap across several lines',
    );

    expect(tester.getSize(find.byKey(titleFieldKey)).height, greaterThan(72));
    expect(tester.takeException(), isNull);
  });

  testWidgets('composes editor fields and action bar at 390x844', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(390, 844));

    expect(find.byKey(titleFieldKey), findsOneWidget);
    expect(find.byKey(contentFieldKey), findsOneWidget);
    expect(find.byType(NoteDetailActionBar), findsOneWidget);
    expect(find.byKey(saveKey), findsOneWidget);
    expect(find.byKey(summarizeKey), findsOneWidget);
    expect(find.byKey(NoteDetailSurface.scrollKey), findsOneWidget);

    // The surface must not introduce its own Scaffold.
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composes editor fields and action bar at 1024x700', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(1024, 700));

    expect(find.byKey(titleFieldKey), findsOneWidget);
    expect(find.byKey(contentFieldKey), findsOneWidget);
    expect(find.byType(NoteDetailActionBar), findsOneWidget);
    expect(find.byKey(saveKey), findsOneWidget);
    expect(find.byKey(summarizeKey), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(titleFieldKey)).style?.fontSize,
      40,
    );

    // Reference pass:704px page column with a12px inset for body text.
    final Finder form = find.byType(NoteDetailEditorForm);
    expect(tester.getSize(form).width, 704);
    expect(tester.getCenter(form).dx, 512);
    expect(tester.getTopLeft(form).dy, 48);
    expect(tester.getSize(find.byKey(contentFieldKey)).width, 692);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchors the compact editor column to the Notion page inset', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(567, 694));

    final Finder form = find.byType(NoteDetailEditorForm);
    expect(tester.getSize(form).width, 360);
    expect(tester.getTopLeft(form).dx, 20);
    expect(tester.getTopLeft(form).dy, kIsWeb ? 36 : 24);
    expect(
      tester.widget<TextField>(find.byKey(titleFieldKey)).style?.fontSize,
      32,
    );
    expect(tester.takeException(), isNull);
  });

  test('Web compact editor adjustment follows Notion reference anchors', () {
    expect(
      NoteFlowLayout.compactWebEditorTopAdjustmentFor(390),
      NoteFlowLayout.compactWebEditorPhoneTitleGlyphAdjustment,
    );
    expect(
      NoteFlowLayout.compactWebEditorTopAdjustmentFor(567),
      NoteFlowLayout.compactWebEditorWideTitleGlyphAdjustment,
    );
    expect(NoteFlowLayout.compactWebEditorTopAdjustmentFor(478.5), 40);
    expect(NoteFlowLayout.compactWebEditorTopAdjustmentFor(320), 68);
    expect(NoteFlowLayout.compactWebEditorTopAdjustmentFor(840), 0);
    expect(NoteFlowLayout.compactWebEditorTitleLeadingInset, 8);
  });

  testWidgets('compact page header keeps the title at the mobile anchor', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(390, 844), showPageHeader: true);

    final Finder form = find.byType(NoteDetailEditorForm);
    expect(tester.getTopLeft(form).dx, 20);
    expect(tester.getTopLeft(form).dy, kIsWeb ? 148 : 80);
    expect(tester.getSize(form).width, 354);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide editor uses a Notion-like header with compact actions', (
    WidgetTester tester,
  ) async {
    await pumpSurface(
      tester,
      size: const Size(1024, 700),
      showPageHeader: true,
    );

    expect(find.byType(NoteFlowPageHeader), findsOneWidget);
    expect(find.byType(NoteDetailActionBar), findsOneWidget);
    expect(find.byKey(summarizeKey), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new-note autosave state lives in the page header', (
    WidgetTester tester,
  ) async {
    await pumpSurface(
      tester,
      size: const Size(1024, 700),
      titleText: '',
      showPageHeader: true,
      hasSavedNote: false,
    );

    expect(find.text('New note'), findsOneWidget);
    expect(find.text('Saves automatically as you type'), findsOneWidget);
    expect(
      find.text(
        'Your note is created automatically as you type. You can summarize it once it is created.',
      ),
      findsNothing,
    );
    expect(find.byKey(NoteFlowPageHeader.statusKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable note storage uses a warning icon and label', (
    WidgetTester tester,
  ) async {
    await pumpSurface(
      tester,
      size: const Size(1024, 700),
      titleText: '',
      showPageHeader: true,
      statusUnavailable: true,
      hasSavedNote: false,
    );

    final Icon unavailableIcon = tester.widget<Icon>(
      find.byIcon(Icons.cloud_off_outlined),
    );
    expect(unavailableIcon.color, NoteFlowUiTokens.light().textMuted);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    expect(find.text('Saving unavailable on Web'), findsOneWidget);
  });

  testWidgets('compact page status follows the autosave lifecycle', (
    WidgetTester tester,
  ) async {
    const Size size = Size(390, 844);

    await pumpSurface(
      tester,
      size: size,
      titleText: '',
      showPageHeader: true,
      hasSavedNote: false,
    );
    expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);

    await pumpSurface(tester, size: size, showPageHeader: true, isDirty: true);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);

    await pumpSurface(
      tester,
      size: size,
      showPageHeader: true,
      isDirty: true,
      error: 'Couldn’t save the note. Please try again.',
    );
    final Finder status = find.byKey(NoteFlowPageHeader.statusKey);
    final Icon errorIcon = tester.widget<Icon>(
      find.descendant(of: status, matching: find.byIcon(Icons.error_outline)),
    );
    expect(errorIcon.color, Theme.of(tester.element(status)).colorScheme.error);
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);

    await pumpSurface(tester, size: size, showPageHeader: true, isSaving: true);
    expect(
      find.descendant(
        of: find.byKey(NoteFlowPageHeader.statusKey),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);

    await pumpSurface(tester, size: size, showPageHeader: true);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  for (final Size size in <Size>[
    const Size(320, 568),
    const Size(360, 800),
    const Size(390, 844),
    const Size(568, 320),
  ]) {
    for (final double textScale in <double>[1.0, 1.3, 1.5, 2.0]) {
      testWidgets('renders without overflow at ${textScale}x text scale on '
          '${size.width.toInt()}x${size.height.toInt()}', (
        WidgetTester tester,
      ) async {
        await pumpSurface(
          tester,
          size: size,
          textScale: textScale,
          isDirty: true,
        );

        expect(find.byKey(titleFieldKey), findsOneWidget);
        expect(find.byKey(contentFieldKey), findsOneWidget);
        expect(find.byType(NoteDetailActionBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
