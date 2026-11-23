import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';
import 'package:note_ai_app/presentation/notes/share_management_surface.dart';

void main() {
  testWidgets(
    'landscape 200 percent Share keeps the whole field above IME',
    (tester) async {
      tester.view
        ..physicalSize = const Size(914, 411)
        ..devicePixelRatio = 1
        ..viewInsets = const FakeViewPadding(bottom: 213);
      addTearDown(tester.view.reset);
      final email = TextEditingController();
      addTearDown(email.dispose);
      var closed = false;
      var acted = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [NoteFlowUiTokens.light()]),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ShareManagementSurface(
                title: 'Manage sharing',
                closeLabel: 'Close',
                onClose: () => closed = true,
                tokens: NoteFlowUiTokens.of(context),
                content: Column(
                  children: [
                    ShareInviteField(
                      controller: email,
                      enabled: true,
                      label: 'Verified account email',
                      compact: true,
                      tokens: NoteFlowUiTokens.of(context),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => acted = true,
                      child: const Text('Existing action'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('share-recipient-email'));
      await tester.tap(field);
      await tester.pumpAndSettle();
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final border = InputDecorator.containerOf(tester.element(editable))!;
      final borderRect = border.localToGlobal(Offset.zero) & border.size;
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      expect(borderRect.top, greaterThanOrEqualTo(viewport.top));
      expect(borderRect.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(borderRect.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);

      final action = find.text('Existing action');
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      expect(acted, isTrue);
      await tester.tap(find.text('Close'));
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
    skip: kIsWeb,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
