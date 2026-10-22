import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/presentation/notes/attachment_file_row.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    AttachmentFileRow row, {
    double scale = 1,
  }) async {
    tester.view
      ..physicalSize = const Size(412, 914)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(child: SizedBox(width: 280, child: row)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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
        sizeLabel: '20 MiB',
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
    await tester.tap(find.byTooltip('Attachment actions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Remove attachment'), findsOneWidget);
  });
}
