import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/label_application.dart';
import 'package:note_ai_app/application/labels/local_label_state.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/presentation/labels/label_catalog_scope.dart';
import 'package:note_ai_app/presentation/labels/label_manager_dialog.dart';
import 'package:note_ai_app/presentation/labels/note_label_editor.dart';

const _actor = 'owner-1';
final _now = DateTime.utc(2026, 10, 26);

void main() {
  late LabelApplication app;

  setUp(() {
    app = LabelApplication(
      currentActor: () => _actor,
      generation: () => 1,
      storeFor: (_) => throw StateError('This layout test does not write.'),
      notes: _UnusedNoteRepository(),
      generateId: () => 'unused-id',
      now: () => _now,
      requestSync: (_) {},
    );
  });

  tearDown(() async {
    await app.dispose();
  });

  for (final rename in [false, true]) {
    testWidgets(
      '${rename ? 'rename' : 'add'} controller lives until the closing dialog unmounts',
      (tester) async {
        _setViewport(tester, const Size(1000, 800));
        await tester.pumpWidget(
          _shell(
            app: app,
            labels: [_label('first', 'Study')],
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLabelManager(context),
                child: const Text('Open manager'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open manager'));
        await tester.pumpAndSettle();
        await tester.tap(
          rename
              ? find.byTooltip('Rename label').first
              : find.text('Add label'),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        expect(controller.text, rename ? 'Study' : '');

        await tester.tap(find.text('Cancel').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(TextField), findsOneWidget);
        void listener() {}
        expect(() => controller.addListener(listener), returnsNormally);
        controller.removeListener(listener);
        expect(tester.takeException(), isNull);

        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(() => controller.addListener(listener), throwsFlutterError);
        expect(tester.takeException(), isNull);
        expect(find.text('Study'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'desktop chooser has bounded content without intrinsic viewport errors',
    (tester) async {
      _setViewport(tester, const Size(1280, 740));
      await tester.pumpWidget(
        _shell(
          app: app,
          labels: [_label('first', 'Study'), _label('second', 'Work')],
          child: NoteLabelEditor(
            note: NoteDto(
              id: 'desktop-note',
              ownerId: _actor,
              title: 'Synthetic note',
              content: '',
              createdAt: _now,
              updatedAt: _now,
            ),
            readable: true,
            canManage: true,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('Choose note labels'));
      await tester.pumpAndSettle();
      expect(find.text('Study'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      final surface = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getSize(surface).height, lessThan(350));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('manager stays usable with long names, IME, and large text', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 640));
    final longName = 'L' * 64;
    await tester.pumpWidget(
      _shell(
        app: app,
        labels: [
          _label('long', longName),
          _label('first', 'Same name'),
          _label('second', 'Same name'),
          _label('foreign', 'Foreign label', ownerId: 'other-owner'),
        ],
        textScale: 2,
        viewInsets: const EdgeInsets.only(bottom: 240),
        child: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-manager'),
            onPressed: () => showLabelManager(context),
            child: const Text('Open manager'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-manager')));
    await tester.pumpAndSettle();

    expect(find.text('Foreign label'), findsNothing);
    expect(find.byTooltip('Rename label').first, findsOneWidget);
    expect(find.byTooltip('Delete label').first, findsOneWidget);
    await tester.scrollUntilVisible(
      find.byTooltip(longName),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byTooltip(longName), findsOneWidget);
    expect(find.text('Add label'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final longNameText = find.text(longName);
    await tester.ensureVisible(longNameText);
    final renameLongLabel = find.byTooltip('Rename label').first;
    await tester.ensureVisible(renameLongLabel);
    await tester.tap(renameLongLabel);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      longName,
    );
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Delete label').first);
    await tester.pumpAndSettle();
    expect(find.text(longName).last, findsOneWidget);
    expect(find.text('Delete label'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _scrollListToEnd(tester);
    expect(find.text('Same name'), findsNWidgets(2));
    expect(find.byTooltip('Rename label').last, findsOneWidget);
    expect(find.byTooltip('Delete label').last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chooser keeps duplicate and long labels separately usable', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 640));
    final longName = List.filled(9, 'Label').join(' ');
    var changed = false;
    final note = NoteDto(
      id: 'note-1',
      ownerId: _actor,
      title: 'A note',
      content: '',
      createdAt: _now,
      updatedAt: _now,
    );

    await tester.pumpWidget(
      _shell(
        app: app,
        labels: [
          _label('long', longName),
          _label('first', 'Same name'),
          _label('second', 'Same name'),
        ],
        textScale: 1.8,
        viewInsets: const EdgeInsets.only(bottom: 220),
        child: NoteLabelEditor(
          note: note,
          readable: true,
          canManage: true,
          onChanged: (_) => changed = true,
        ),
      ),
    );

    await tester.tap(find.text('Choose note labels'));
    await tester.pumpAndSettle();

    final longNameText = find.text(longName);
    await tester.ensureVisible(longNameText);
    final longNameTile = find.widgetWithText(CheckboxListTile, longName);
    expect(longNameTile, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(longNameTile).onChanged, isNotNull);
    await tester.scrollUntilVisible(
      find.text(longName),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(longName), findsOneWidget);
    expect(find.text('Manage labels'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _scrollListToEnd(tester);
    expect(find.text('Same name'), findsNWidgets(2));
    final duplicateTiles = find.widgetWithText(CheckboxListTile, 'Same name');
    expect(duplicateTiles, findsNWidgets(2));
    expect(
      tester
          .widgetList<CheckboxListTile>(duplicateTiles)
          .every((tile) => tile.onChanged != null),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chooser management stays hidden without owner permission', (
    tester,
  ) async {
    _setViewport(tester, const Size(360, 640));
    final ownedNote = NoteDto(
      id: 'owned-note',
      ownerId: _actor,
      title: 'Owned note',
      content: '',
      createdAt: _now,
      updatedAt: _now,
    );
    await tester.pumpWidget(
      _shell(
        app: app,
        labels: [_label('first', 'Same name')],
        child: NoteLabelEditor(
          note: ownedNote,
          readable: true,
          canManage: false,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Choose note labels'), findsNothing);

    final sharedNote = NoteDto(
      id: 'shared-note',
      ownerId: 'another-owner',
      title: 'Shared note',
      content: '',
      createdAt: _now,
      updatedAt: _now,
    );
    await tester.pumpWidget(
      _shell(
        app: app,
        labels: [_label('first', 'Same name')],
        child: NoteLabelEditor(
          note: sharedNote,
          readable: true,
          canManage: true,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Choose note labels'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

LocalLabelState _label(String id, String name, {String ownerId = _actor}) =>
    LocalLabelState(
      id: id,
      ownerId: ownerId,
      name: name,
      createdAt: _now,
      updatedAt: _now,
      status: NoteSyncStatus.synced,
    );

Widget _shell({
  required LabelApplication app,
  required List<LocalLabelState> labels,
  required Widget child,
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) => LabelCatalogScope(
  application: app,
  actor: _actor,
  labels: labels,
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 24, bottom: 24),
        viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
        viewInsets: viewInsets,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(body: child),
  ),
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _scrollListToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).last, const Offset(0, -500));
  await tester.pumpAndSettle();
}

final class _UnusedNoteRepository implements INoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
