import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/labels/label_application.dart';
import 'package:note_ai_app/application/labels/note_query.dart';
import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/domain/labels/label_membership.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/presentation/labels/label_catalog_scope.dart';
import 'package:note_ai_app/presentation/labels/label_filter_bar.dart';
import 'package:note_ai_app/presentation/labels/note_label_chips.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

void main() {
  late FakeLocalSyncStore store;
  late LabelApplication app;
  late NoteRepository notes;
  late String actor;
  late int epoch;
  late int sequence;
  final time = DateTime.utc(2026, 10, 26);

  void setup() {
    actor = 'owner';
    epoch = 1;
    sequence = 0;
    store = FakeLocalSyncStore(accountUserId: actor);
    notes = NoteRepository(
      labelsEnabled: true,
      currentAccountUserId: () => actor,
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'm${++sequence}',
      now: () => time,
      sessionGeneration: () => epoch,
    );
    app = LabelApplication(
      currentActor: () => actor,
      generation: () => epoch,
      storeFor: (_) => store,
      notes: notes,
      generateId: () => 'label${++sequence}',
      now: () => time,
      requestSync: (_) {},
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(320, 640),
    double textScale = 1,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, routeChild) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(size: size, textScaler: TextScaler.linear(textScale)),
          child: LabelCatalogHost(
            application: app,
            securityChanges: const Stream.empty(),
            child: routeChild!,
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: size.width, child: child),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  NoteDto noteWithLabel(String labelId) => NoteDto(
    id: 'note',
    ownerId: actor,
    title: 'A note',
    content: 'Body',
    createdAt: time,
    updatedAt: time,
    labelMembership: LabelMembership([labelId]),
  );

  testWidgets('note label remains readable at narrow width and large text', (
    tester,
  ) async {
    setup();
    const labelName = 'A longer label name that should remain accessible';
    final label = await app.create(labelName);
    final note = noteWithLabel(label.id);
    final semantics = tester.ensureSemantics();

    await pump(
      tester,
      NoteLabelChips(note: note, readable: true, showCaption: true),
      size: const Size(280, 640),
      textScale: 1.6,
    );

    expect(find.text(labelName), findsOneWidget);
    expect(
      tester.getSemantics(find.text(labelName)),
      isSemantics(label: labelName),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('dense filters keep touch targets and clear selection', (
    tester,
  ) async {
    setup();
    final label = await app.create('Study');
    final note = noteWithLabel(label.id);
    var selected = <LabelSelection>{};
    Set<LabelSelection>? lastChanged;
    final semantics = tester.ensureSemantics();

    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => LabelFilterBar(
          notes: [note],
          selected: selected,
          readable: (_) => true,
          allowManage: false,
          dense: true,
          onChanged: (next) {
            lastChanged = next;
            setState(() => selected = next);
          },
        ),
      ),
    );

    final chip = find.byType(FilterChip);
    expect(chip, findsOneWidget);
    expect(tester.getRect(chip).height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(chip), isSemantics(hasTapAction: true));

    await tester.tap(chip);
    await tester.pump();
    final selection = (ownerId: actor, id: label.id);
    expect(selected, contains(selection));
    expect(lastChanged, contains(selection));
    expect(
      tester.getSemantics(chip),
      kIsWeb
          ? isSemantics(hasCheckedState: true, isChecked: true)
          : isSemantics(isSelected: true),
    );

    final clearButton = find.byType(TextButton);
    expect(clearButton, findsOneWidget);
    expect(tester.getRect(clearButton).height, greaterThanOrEqualTo(48));
    await tester.tap(clearButton);
    await tester.pump();
    expect(selected, isEmpty);
    expect(lastChanged, isEmpty);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('filter chip is keyboard focusable and activates by keyboard', (
    tester,
  ) async {
    setup();
    final label = await app.create(
      'A long keyboard label with enough words to wrap',
    );
    final note = noteWithLabel(label.id);
    var selected = <LabelSelection>{};

    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => LabelFilterBar(
          notes: [note],
          selected: selected,
          readable: (_) => true,
          allowManage: false,
          onChanged: (next) => setState(() => selected = next),
        ),
      ),
      size: const Size(240, 640),
      textScale: 1.6,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.binding.focusManager.primaryFocus, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, contains((ownerId: actor, id: label.id)));
    expect(tester.takeException(), isNull);
  });
}
