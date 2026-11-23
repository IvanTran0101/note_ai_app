import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_role.dart';
import 'package:note_ai_app/domain/notes/note_share_grant.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_localizations.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_note_card.dart';
import 'package:note_ai_app/presentation/notes/animated_note_list.dart';
import 'package:note_ai_app/presentation/notes/notes_localizations.dart';

void main() {
  final now = DateTime.utc(2026, 11, 10);
  final shared = NoteDto(
    id: 'shared',
    ownerId: 'owner',
    title: 'Private title',
    content: 'Private content',
    createdAt: now,
    updatedAt: now,
    isProtected: true,
    share: NoteShareGrant(
      note: NoteIdentity('owner', 'shared'),
      recipientId: 'viewer',
      role: NoteRole.viewer,
      sharedAt: now,
      updatedAt: now,
      accessRevision: 1,
    ),
  );

  for (final layout in DashboardNoteCardLayout.values) {
    for (final showPreview in [false, true]) {
      testWidgets('Vietnamese shared indicator $layout preview=$showPreview', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('vi'),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              DashboardCopy.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: SizedBox(
                    width: 320,
                    child: DashboardNoteCard(
                      note: shared,
                      copy: DashboardCopy.of(context),
                      layout: layout,
                      showPreview: showPreview,
                      onTap: (_) => opened = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.people_outline), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Được chia sẻ')), findsWidgets);
        expect(find.text('Private title'), findsNothing);
        expect(find.text('Private content'), findsNothing);
        await tester.tap(find.byType(DashboardNoteCard));
        expect(opened, isTrue);
        handle.dispose();
      });
    }
  }

  testWidgets(
    'pinned indicator remains visible and accessible for a locked note',
    (tester) async {
      final handle = tester.ensureSemantics();
      var opened = false;
      final pinned = NoteDto(
        id: 'pinned',
        ownerId: 'owner',
        title: 'Private title',
        content: 'Private content',
        createdAt: now,
        updatedAt: now,
        isProtected: true,
        pinnedAt: now,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            NotesCopy.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: AnimatedNoteList(
              notes: [pinned],
              selectedNoteId: null,
              actionBusy: false,
              onSelectNote: (_) => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Đã ghim')), findsWidgets);
      expect(find.text('Private title'), findsNothing);
      expect(find.text('Private content'), findsNothing);
      await tester.tap(find.byType(ListTile));
      expect(opened, isTrue);
      handle.dispose();
    },
  );
}
