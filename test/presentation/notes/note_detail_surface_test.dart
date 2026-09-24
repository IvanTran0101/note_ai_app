import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
    bool hasSavedNote = true,
    String titleText = 'First note',
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final TextEditingController titleController = TextEditingController(
      text: titleText,
    );
    final TextEditingController contentController = TextEditingController(
      text: 'The first note body.',
    );
    final FocusNode contentFocusNode = FocusNode();
    addTearDown(titleController.dispose);
    addTearDown(contentController.dispose);
    addTearDown(contentFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: Material(
                child: NoteDetailSurface(
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
                  error: null,
                  statusMessage: null,
                  actionBusy: false,
                  provisioningReader: null,
                  onProvisioningRetry: null,
                  onProvisioningCancel: null,
                  summary: null,
                  summaryStale: false,
                  isSaving: false,
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
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('new note title hint uses compact page-title typography', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(390, 844), titleText: '');

    final Text titleHint = tester.widget<Text>(find.text('Title'));
    expect(titleHint.style?.fontSize, 40);
    expect(titleHint.style?.fontWeight, FontWeight.w700);
    expect(tester.widget<Text>(find.text('Content')).style?.fontSize, 16);
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

    // The title block matches Notion's 720px block; body text uses 708px.
    final Finder form = find.byType(NoteDetailEditorForm);
    expect(tester.getSize(form).width, 720);
    expect(tester.getCenter(form).dx, 512);
    expect(tester.getTopLeft(form).dy, 112);
    expect(tester.getSize(find.byKey(contentFieldKey)).width, 708);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anchors the compact editor column to the Notion page inset', (
    WidgetTester tester,
  ) async {
    await pumpSurface(tester, size: const Size(567, 694));

    final Finder form = find.byType(NoteDetailEditorForm);
    expect(tester.getSize(form).width, 360);
    expect(tester.getTopLeft(form).dx, 96);
    expect(tester.getTopLeft(form).dy, 56);
    expect(
      tester.widget<TextField>(find.byKey(titleFieldKey)).style?.fontSize,
      40,
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
    expect(tester.getTopLeft(form).dx, 96);
    expect(tester.getTopLeft(form).dy, 105);
    expect(tester.getSize(form).width, 278);
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
