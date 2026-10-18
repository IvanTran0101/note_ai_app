import 'package:appflowy_editor/appflowy_editor.dart' as engine;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/editor/rich_editor_adapter.dart';
import 'package:note_ai_app/presentation/editor/rich_note_editor.dart';
import 'package:note_ai_app/presentation/editor/selection_toolbar_layout.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/workspace/workspace_shell.dart';

void main() {
  Future<void> window(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final size in [
    const Size(411, 914),
    const Size(914, 411),
    const Size(1200, 800),
  ]) {
    _phoneTest('phone classification uses full window $size', (tester) async {
      await window(tester, size);
      late bool phone, compact, short, narrowPane;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              phone = NoteFlowLayout.isNativePhone(context);
              compact = NoteFlowLayout.isCompact(context);
              short = NoteFlowLayout.isShortEditor(context);
              narrowPane = NoteFlowLayout.isCompact(
                context,
                availableWidth: 400,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(phone, !kIsWeb && size.shortestSide < 600);
      expect(compact, size.width < 600 || phone);
      expect(short, phone && size.height < 500);
      expect(narrowPane, isTrue);
    });
  }

  _phoneTest('unknown MediaQuery size respects actual pane constraints', (
    tester,
  ) async {
    late bool compact;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              compact = NoteFlowLayout.isCompact(context, availableWidth: 700);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(compact, isFalse);
  });

  _phoneTest('rotated phone keeps mobile navigation and draft', (tester) async {
    await window(tester, const Size(411, 914));
    final draft = TextEditingController(text: 'Keep local draft');
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceShell(
          dashboard: const SizedBox(),
          notes: TextField(controller: draft),
          initialDestination: WorkspaceDestination.notes,
          onOpenSearch: () {},
          onCreateNote: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(914, 411);
    await tester.pumpAndSettle();
    expect(
      find.byKey(WorkspaceShell.sidebarKey),
      kIsWeb ? findsOneWidget : findsNothing,
    );
    expect(
      find.byKey(WorkspaceShell.compactBottomNavigationKey),
      kIsWeb ? findsNothing : findsOneWidget,
    );
    expect(draft.text, 'Keep local draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  _phoneTest('short formatting row scrolls every existing control into reach', (
    tester,
  ) async {
    await window(tester, const Size(914, 411));
    var activated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectionToolbarLayout(
              children: [
                for (var i = 0; i < 20; i++)
                  IconButton(
                    tooltip: 'Format $i',
                    icon: const Icon(Icons.format_bold),
                    onPressed: () => activated = true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!kIsWeb) {
      expect(tester.getSize(find.byType(SelectionToolbarLayout)).height, 48);
      final scroll = find.byType(SingleChildScrollView);
      await tester.drag(scroll, const Offset(-800, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Format 19').hitTestable());
    await tester.pumpAndSettle();
    expect(activated, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final editable in [true, false]) {
    _phoneTest(
      'native rail follows content and permissions editable=$editable',
      (tester) async {
        await window(tester, const Size(411, 914));
        final focus = FocusNode();
        final adapter = RichEditorAdapter(
          document: null,
          legacyText: 'body',
          canEdit: () => editable,
          isLive: () => true,
          accessGeneration: () => 1,
          onChanged: () {},
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              engine.AppFlowyEditorLocalizations.delegate,
            ],
            home: Scaffold(
              body: RichNoteEditor(
                adapter: adapter,
                focusNode: focus,
                header: const SizedBox(height: 60, child: Text('Title')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final rail = find.byKey(const ValueKey('document-controls-rail'));
        expect(rail, editable && !kIsWeb ? findsOneWidget : findsNothing);
        if (editable && !kIsWeb) {
          expect(tester.getBottomLeft(rail).dy, 914);
          expect(tester.getTopLeft(rail).dy, 866);
          expect(
            tester.getTopLeft(find.byTooltip('Add block')).dy,
            greaterThan(800),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
        focus.dispose();
      },
    );
  }
}

void _phoneTest(String description, WidgetTesterCallback callback) =>
    testWidgets(
      description,
      callback,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
