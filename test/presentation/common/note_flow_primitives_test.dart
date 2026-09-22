import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/common/note_flow_primitives.dart';
import 'package:note_ai_app/presentation/notes/notes_theme_tokens.dart';

Widget _wrap(Widget child, {ThemeMode themeMode = ThemeMode.light}) {
  return MaterialApp(
    theme: ThemeData.light().copyWith(
      extensions: <ThemeExtension<dynamic>>[
        NoteFlowUiTokens.light(),
        NoteFlowSemanticColors.fromColorScheme(
          ColorScheme.fromSeed(seedColor: const Color(0xFF5B4FA6)),
        ),
      ],
    ),
    darkTheme: ThemeData.dark().copyWith(
      extensions: <ThemeExtension<dynamic>>[
        NoteFlowUiTokens.dark(),
        NoteFlowSemanticColors.fromColorScheme(
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B4FA6),
            brightness: Brightness.dark,
          ),
        ),
      ],
    ),
    themeMode: themeMode,
    home: Scaffold(body: child),
  );
}

void main() {
  group('NoteFlowUiTokens', () {
    testWidgets('exposes registered light tokens', (tester) async {
      NoteFlowUiTokens? captured;
      Brightness? capturedBrightness;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (BuildContext context) {
              captured = Theme.of(context).extension<NoteFlowUiTokens>();
              capturedBrightness = Theme.of(context).brightness;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured, isNotNull);
      expect(capturedBrightness, Brightness.light);
      expect(captured!.pageSurface, NoteFlowUiTokens.light().pageSurface);
    });

    testWidgets('exposes registered dark tokens', (tester) async {
      NoteFlowUiTokens? captured;
      Brightness? capturedBrightness;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (BuildContext context) {
              captured = Theme.of(context).extension<NoteFlowUiTokens>();
              capturedBrightness = Theme.of(context).brightness;
              return const SizedBox();
            },
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      expect(capturedBrightness, Brightness.dark);
      expect(captured, isNotNull);
      expect(captured!.pageSurface, NoteFlowUiTokens.dark().pageSurface);
    });
  });

  group('NoteFlowSectionLabel', () {
    testWidgets('renders label as a header', (tester) async {
      await tester.pumpWidget(
        _wrap(const NoteFlowSectionLabel(label: 'Recents')),
      );
      expect(find.text('Recents'), findsOneWidget);
      expect(find.bySemanticsLabel('Recents'), findsOneWidget);
      final SemanticsData data = tester
          .getSemantics(find.byType(NoteFlowSectionLabel))
          .getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isHeader), isTrue);
    });
  });

  group('NoteFlowSidebarRow', () {
    testWidgets('reports selected state and fires onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrap(
          NoteFlowSidebarRow(
            label: 'Notes',
            icon: Icons.description_outlined,
            selected: true,
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.bySemanticsLabel('Notes'), findsOneWidget);
      await tester.tap(find.text('Notes'));
      expect(tapped, isTrue);
      final SemanticsData data = tester
          .getSemantics(find.byType(NoteFlowSidebarRow))
          .getSemanticsData();
      expect(data.hasFlag(SemanticsFlag.isSelected), isTrue);
    });

    testWidgets('disabled row does not fire callback', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const NoteFlowSidebarRow(label: 'Notes', icon: Icons.description),
        ),
      );
      await tester.tap(find.text('Notes'), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });
  });

  group('NoteFlowPageHeader', () {
    testWidgets('renders back affordance and breadcrumb', (tester) async {
      bool backed = false;
      await tester.pumpWidget(
        _wrap(
          NoteFlowPageHeader(
            breadcrumb: 'Workspace / Notes',
            onBack: () => backed = true,
            backTooltip: 'Back',
            backKey: const ValueKey<String>('back'),
            actions: const <Widget>[Icon(Icons.more_horiz)],
          ),
        ),
      );
      expect(find.text('Workspace / Notes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('back')));
      expect(backed, isTrue);
    });
  });

  group('NoteFlowMenuItem', () {
    testWidgets('renders label and fires onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        _wrap(
          NoteFlowMenuItem(
            label: 'Delete',
            icon: Icons.delete_outline,
            destructive: true,
            onTap: () => tapped = true,
          ),
        ),
      );
      await tester.tap(find.text('Delete'));
      expect(tapped, isTrue);
    });

    testWidgets('disabled item keeps its label', (tester) async {
      await tester.pumpWidget(
        _wrap(const NoteFlowMenuItem(label: 'Duplicate', icon: Icons.copy)),
      );
      expect(find.text('Duplicate'), findsOneWidget);
      await tester.tap(find.text('Duplicate'), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });
  });
}
