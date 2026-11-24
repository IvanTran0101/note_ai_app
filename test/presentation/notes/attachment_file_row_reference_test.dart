import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/notes/attachment_file_row.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    AttachmentFileRow row, {
    double scale = 1,
    Size viewport = const Size(412, 914),
    double rowWidth = 280,
    bool accessibleNavigation = false,
  }) async {
    tester.view
      ..physicalSize = viewport
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            accessibleNavigation: accessibleNavigation,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: rowWidth, child: row),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('desktop actions reveal on hover and keyboard focus', (
    tester,
  ) async {
    await pump(
      tester,
      AttachmentFileRow(
        name: 'quarterly-notes.pdf',
        mimeType: 'application/pdf',
        sizeLabel: '20 MiB',
        statusLabel: 'Ready',
        onOpen: () {},
        onRemove: () {},
      ),
      viewport: kIsWeb ? const Size(900, 914) : const Size(412, 914),
      rowWidth: kIsWeb ? 640 : 280,
    );

    final opacity = find.byKey(const ValueKey('attachment-actions-reveal'));
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, kIsWeb ? 0 : 1);

    if (kIsWeb) {
      final row = find.byKey(const ValueKey('attachment-file-row-open'));
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.moveTo(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      await pointer.moveTo(const Offset(1, 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);

      final focusScope = tester.widget<Focus>(
        find.byKey(const ValueKey('attachment-actions-focus-scope')),
      );
      expect(focusScope.canRequestFocus, isFalse);
      expect(focusScope.skipTraversal, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
      await pointer.removePointer();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('accessible navigation reveals desktop actions without hover', (
    tester,
  ) async {
    await pump(
      tester,
      AttachmentFileRow(
        name: 'quarterly-notes.pdf',
        mimeType: 'application/pdf',
        sizeLabel: '20 MiB',
        statusLabel: 'Ready',
        onOpen: () {},
        onRemove: () {},
      ),
      viewport: kIsWeb ? const Size(900, 914) : const Size(412, 914),
      rowWidth: kIsWeb ? 640 : 280,
      accessibleNavigation: true,
    );

    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('attachment-actions-reveal')),
          )
          .opacity,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending status sits below filename and size', (tester) async {
    await pump(
      tester,
      AttachmentFileRow(
        name: 'quarterly-notes.pdf',
        mimeType: 'application/pdf',
        sizeLabel: '20 MiB',
        statusLabel: 'Pending on this device',
        onOpen: () {},
        onRemove: () {},
      ),
    );

    final name = tester.getRect(find.text('quarterly-notes.pdf'));
    final size = tester.getRect(find.text('20 MiB'));
    final status = tester.getRect(find.text('Pending on this device'));
    expect(status.top, greaterThan(name.bottom - 1));
    expect(status.top, greaterThan(size.bottom - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready file row keeps the Notion-style name and size hierarchy', (
    tester,
  ) async {
    await pump(
      tester,
      AttachmentFileRow(
        name: 'quarterly-notes.pdf',
        mimeType: 'application/pdf',
        sizeLabel: '20 MiB',
        statusLabel: 'Ready',
        onOpen: () {},
        onRemove: () {},
      ),
      viewport: kIsWeb ? const Size(900, 914) : const Size(412, 914),
      rowWidth: kIsWeb ? 640 : 280,
    );

    expect(find.text('quarterly-notes.pdf'), findsOneWidget);
    expect(find.text('20 MiB'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    expect(find.byTooltip('Ready'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('attachment-file-row-open')))
          .height,
      kIsWeb ? 28 : 48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('file actions dispatch once without opening the preview', (
    tester,
  ) async {
    final events = <String>[];
    await pump(
      tester,
      AttachmentFileRow(
        name: 'm09-ui-sample.txt',
        mimeType: 'text/plain',
        sizeLabel: '67 B',
        statusLabel: 'Ready',
        onOpen: () => events.add('open'),
        onDownload: () => events.add('download'),
        onRemove: () => events.add('remove'),
      ),
    );
    await tester.tap(find.byTooltip('Attachment actions'));
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    await tester.tap(find.text('Download attachment'));
    await tester.pumpAndSettle();
    expect(events, ['download']);
    expect(find.text('Download attachment'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('attachment-file-row-open')));
    await tester.pumpAndSettle();
    expect(events, ['download', 'open']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'readable file with no supplied write actions has no action menu',
    (tester) async {
      var opened = 0;
      await pump(
        tester,
        AttachmentFileRow(
          name: 'readable.pdf',
          mimeType: 'application/pdf',
          sizeLabel: '20 KiB',
          statusLabel: 'Ready',
          onOpen: () => opened++,
        ),
      );
      expect(find.byTooltip('Attachment actions'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('attachment-file-row-open')));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('busy menu actions stay disabled and cancellation is inert', (
    tester,
  ) async {
    final events = <String>[];
    await pump(
      tester,
      AttachmentFileRow(
        name: 'pending.csv',
        mimeType: 'text/csv',
        sizeLabel: '200 B',
        statusLabel: 'Pending on this device',
        onOpen: () => events.add('open'),
        onRetry: () => events.add('retry'),
        retryEnabled: false,
        onRemove: () => events.add('remove'),
        removeEnabled: false,
      ),
    );
    await tester.tap(find.byTooltip('Attachment actions'));
    await tester.pumpAndSettle();
    final entries = tester.widgetList<PopupMenuItem<AttachmentFileRowAction>>(
      find.byType(PopupMenuItem<AttachmentFileRowAction>),
    );
    expect(entries.every((entry) => !entry.enabled), isTrue);
    await tester.tap(find.text('Retry upload'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    expect(find.text('Retry upload'), findsNothing);
  });

  testWidgets('long filename at text scale 2 retains a full touch target', (
    tester,
  ) async {
    await pump(
      tester,
      AttachmentFileRow(
        name: '${List.filled(8, 'Tài liệu ghi chú dài').join(' ')}.pdf',
        mimeType: 'application/pdf',
        sizeLabel: '123456.0 MiB',
        statusLabel: 'Ready',
        onOpen: () {},
        onRemove: () {},
      ),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('attachment-file-row-open')))
          .height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('123456.0 MiB'), findsOneWidget);
    await tester.tap(find.byTooltip('Attachment actions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Remove attachment'), findsOneWidget);
  });
}
