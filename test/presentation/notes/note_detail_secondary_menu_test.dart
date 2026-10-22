import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_more_actions.dart';

void main() {
  testWidgets(
    'wide More menu runs child action once and hides unauthorized delete',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var actionCount = 0;
      var deleteCount = 0;

      await tester.pumpWidget(
        _menuHost(
          allowDelete: false,
          onAction: () => actionCount++,
          onDelete: () async => deleteCount++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey<String>('open-more')));
      await tester.pumpAndSettle();

      expect(find.text('Undo test'), findsOneWidget);
      expect(find.text('Redo test'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('note-detail-more-delete')),
        findsNothing,
      );

      await tester.tap(find.text('Undo test'));
      await tester.pumpAndSettle();

      expect(actionCount, 1);
      expect(deleteCount, 0);
      expect(find.text('Undo test'), findsNothing);
    },
  );

  testWidgets('wide More delete runs only after the authorized selection', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var deleteCount = 0;

    await tester.pumpWidget(
      _menuHost(
        allowDelete: true,
        onAction: () {},
        onDelete: () async => deleteCount++,
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('open-more')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('note-detail-more-delete')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('note-detail-more-delete')),
    );
    await tester.pumpAndSettle();

    expect(deleteCount, 1);
  });
}

Widget _menuHost({
  required bool allowDelete,
  required VoidCallback onAction,
  required Future<void> Function() onDelete,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topRight,
      child: Builder(
        builder: (BuildContext pageContext) => SizedBox(
          width: 48,
          height: 48,
          child: Builder(
            builder: (BuildContext anchorContext) => IconButton(
              key: const ValueKey<String>('open-more'),
              tooltip: 'More',
              onPressed: () => unawaited(
                runNoteDetailMoreActions(
                  context: pageContext,
                  anchorContext: anchorContext,
                  copy: NoteDetailCopy.of(pageContext),
                  onDelete: onDelete,
                  allowDelete: allowDelete,
                  additionalActionsHeight: 96,
                  additionalActions: (BuildContext menuContext) => <Widget>[
                    NoteFlowMenuItem(
                      label: 'Undo test',
                      icon: Icons.undo,
                      onTap: () {
                        Navigator.of(menuContext).pop();
                        onAction();
                      },
                    ),
                    const NoteFlowMenuItem(
                      label: 'Redo test',
                      icon: Icons.redo,
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ),
      ),
    ),
  ),
);
