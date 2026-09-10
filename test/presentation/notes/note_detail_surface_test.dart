import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/notes/note_detail_action_bar.dart';
import 'package:note_ai_app/presentation/notes/note_detail_editor_form.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_surface.dart';

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
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final TextEditingController titleController = TextEditingController(
      text: 'First note',
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
                  hasSavedNote: true,
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

    // Wide layouts keep the editor centered and capped at 760 logical pixels.
    final Finder form = find.byType(NoteDetailEditorForm);
    expect(tester.getSize(form).width, 760);
    expect(tester.getCenter(form).dx, 512);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
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
