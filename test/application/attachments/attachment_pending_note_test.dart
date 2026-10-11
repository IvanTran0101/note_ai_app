import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/attachment_transfer.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_panel.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/application/auth/current_user.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

const _draft = LocalAttachmentDraft(
  cacheId: 'offline-attempt',
  fileName: 'offline.txt',
  mimeType: 'text/plain',
  sizeBytes: 5,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  chunkCount: 1,
);

final class _PendingDrafts implements AttachmentDraftStore {
  @override
  Future<LocalAttachmentDraft> stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  }) async => throw ArgumentError('Invalid type/size.');
  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) async {}
  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async => [
    _draft.cacheId,
  ];
  @override
  Future<LocalAttachmentDraft> load(
    AttachmentBinding binding,
    String id,
  ) async => _draft;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Controller implements AttachmentNotesController {
  _Controller(this.attachments, {this.pick});
  final Future<List<AttachmentInput>> Function()? pick;
  @override
  final AttachmentApplicationService attachments;
  @override
  Future<List<AttachmentInput>> pickAttachments(
    AttachmentSource source,
  ) async => pick == null ? [] : await pick!();
}

final class _Security implements SecuredNotesController {
  final events = StreamController<void>.broadcast(sync: true);
  var epoch = 1;
  @override
  int get sessionGeneration => epoch;
  @override
  Stream<void> get securityChanges => events.stream;
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      const NoteAccessCapabilities(canRead: true, canManage: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeLocalSyncStore store;
  late NoteRepository repository;
  late AttachmentApplicationService service;
  late _Security security;
  var uploads = 0, syncs = 0;
  setUp(() {
    uploads = syncs = 0;
    security = _Security();
    final time = DateTime.utc(2026, 10, 6);
    store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        notes: [
          LocalNoteState(
            id: 'note',
            ownerId: 'owner',
            title: 'Offline note',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            serverRevision: 0,
          ),
        ],
      ),
    );
    repository = NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'unused',
      now: () => time,
    );
    service = AttachmentApplicationService(
      notes: repository,
      drafts: _PendingDrafts(),
      captureBinding: (id) async => AttachmentBinding(
        actorId: 'owner',
        note: NoteIdentity('owner', id),
        protection: const NoteProtection.unprotected(),
        accessRevision: 0,
        sessionGeneration: 1,
        contentRevision: 0,
      ),
      requireAccess: (_, _) {},
      upload: (_, _, _) async {
        uploads++;
        throw StateError('Must not upload before create ACK.');
      },
      now: () => time,
      requestSync: (_) => syncs++,
    );
  });
  tearDown(() => security.events.close());

  NoteApplicationServiceController detailController(
    Future<List<AttachmentInput>> Function(AttachmentSource) pick,
  ) => NoteApplicationServiceController(
    NoteApplicationService(
      noteRepository: repository,
      currentUser: StaticCurrentUser(
        identity: AuthIdentity(
          userId: 'owner',
          email: 'owner@example.test',
          isEmailVerified: true,
        ),
      ),
      generateId: () => 'created',
      now: () => DateTime.utc(2026, 10, 7),
      summarizeContent: (_) async => throw UnimplementedError(),
    ),
    attachmentsForCurrentAccount: () => service,
    attachmentPicker: pick,
  );

  Future<void> flushPicker(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
  }

  testWidgets(
    'attachment tray stays out of writing until opened and fits the keyboard',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = detailController((_) async => []);
      final note = await tester.runAsync(() => repository.findById('note'));
      await tester.pumpWidget(
        MaterialApp(
          home: NoteDetailPage(
            notesController: controller,
            note: NoteDto.fromDomain(note!),
          ),
        ),
      );
      await flushPicker(tester);
      expect(find.text('offline.txt'), findsNothing);
      await tester.tap(find.byTooltip('Attachments'));
      await tester.pumpAndSettle();
      expect(find.text('offline.txt'), findsOneWidget);
      expect(find.textContaining('Images 10 MiB'), findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close attachments'));
      await tester.pumpAndSettle();
      expect(find.text('offline.txt'), findsNothing);
      expect(uploads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'toolbar saves new draft before picker and cancellation preserves the note',
    (tester) async {
      var calls = 0;
      final controller = detailController((source) async {
        calls++;
        expect(source, AttachmentSource.files);
        final saved = store.state.notes.singleWhere(
          (note) => note.id == 'created',
        );
        expect(saved.title, 'Draft title');
        expect(saved.content, 'Draft body');
        return [];
      });
      await tester.pumpWidget(
        MaterialApp(home: NoteDetailPage(notesController: controller)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(NoteDetailPage.titleFieldKey),
        'Draft title',
      );
      await tester.enterText(
        find.byKey(NoteDetailPage.contentFieldKey),
        'Draft body',
      );
      await tester.tap(find.byTooltip('Add attachment'));
      // The focused editor caret keeps scheduling frames while the menu opens.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Choose files'));
      await flushPicker(tester);
      expect(calls, 1);
      expect(
        store.state.notes
            .singleWhere((note) => note.id == 'created')
            .attachments,
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(NoteDetailPage.contentFieldKey))
            .controller!
            .text,
        'Draft body',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final entry in const {
    AttachmentSource.files: 'Choose files',
    AttachmentSource.gallery: 'Photos & videos',
    AttachmentSource.cameraPhoto: 'Take photo',
    AttachmentSource.cameraVideo: 'Record video',
  }.entries) {
    testWidgets('empty tray offers ${entry.value} and saves before picking', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 844)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var calls = 0;
      final controller = detailController((source) async {
        calls++;
        expect(source, entry.key);
        expect(
          store.state.notes.singleWhere((note) => note.id == 'created').content,
          'Draft body',
        );
        return [];
      });
      await tester.pumpWidget(
        MaterialApp(home: NoteDetailPage(notesController: controller)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(NoteDetailPage.titleFieldKey), 'Draft');
      await tester.enterText(
        find.byKey(NoteDetailPage.contentFieldKey),
        'Draft body',
      );
      await tester.tap(find.byTooltip('Attachments'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No attachments'), findsOneWidget);
      expect(find.text('Add attachment'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('note-attachment-tray-add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final label in [
        'Choose files',
        'Photos & videos',
        'Take photo',
        'Record video',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(entry.value));
      await flushPicker(tester);
      expect(calls, 1);
      expect(find.byTooltip('Close attachments'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('toolbar blocks invalid draft before opening attachment picker', (
    tester,
  ) async {
    var calls = 0;
    final controller = detailController((_) async {
      calls++;
      return [];
    });
    await tester.pumpWidget(
      MaterialApp(home: NoteDetailPage(notesController: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add attachment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose files'));
    await flushPicker(tester);
    expect(calls, 0);
    expect(store.state.notes, hasLength(1));
    expect(find.byKey(const ValueKey('note-detail-error')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'attachment toolbar is disabled during picker and reenabled after cancellation',
    (tester) async {
      final pending = Completer<List<AttachmentInput>>();
      final controller = detailController((_) => pending.future);
      final domainNote = await tester.runAsync(
        () => repository.findById('note'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NoteDetailPage(
            notesController: controller,
            note: NoteDto.fromDomain(domainNote!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose files'));
      await flushPicker(tester);
      Iterable<PopupMenuButton<AttachmentSource>> buttons() =>
          tester.widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget is PopupMenuButton<AttachmentSource> &&
                  widget.tooltip == 'Add attachment',
            ),
          );
      expect(buttons(), hasLength(2));
      expect(buttons().every((button) => !button.enabled), isTrue);
      pending.complete([]);
      await flushPicker(tester);
      expect(buttons().every((button) => button.enabled), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'Create ACK waiting retains draft and never calls upload or Note writer',
    () async {
      final before = store.state;
      await expectLater(
        service.retry('note', _draft.cacheId),
        throwsA(isA<AttachmentAwaitingNoteSync>()),
      );
      expect(uploads, 0);
      expect(syncs, 1);
      expect(store.state, same(before));
      expect(await service.pending('note'), [_draft]);
    },
  );

  testWidgets('Offline Pending displays sync notice without false file error', (
    tester,
  ) async {
    final domainNote = await tester.runAsync(() => repository.findById('note'));
    final note = NoteDto.fromDomain(domainNote!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentEditorPanel(
            note: note,
            controller: _Controller(service),
            security: security,
            enabled: true,
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
    await tester.pump();
    expect(find.text('offline.txt'), findsOneWidget);
    expect(find.textContaining('Saved on this device.'), findsOneWidget);
    expect(find.textContaining('Attachment operation failed'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(uploads, 0);
    await tester.tap(find.byTooltip('Retry upload'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Attachment operation failed'), findsNothing);
    expect(store.state.notes.single.attachments, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in ['invalid', 'denied', 'cancelled', 'new-session']) {
    testWidgets('Picker lifecycle $mode feedback keeps authority fences', (
      tester,
    ) async {
      final selected = Completer<List<AttachmentInput>>();
      final note = await tester.runAsync(() => repository.findById('note'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentEditorPanel(
              note: NoteDto.fromDomain(note!),
              controller: _Controller(service, pick: () => selected.future),
              security: security,
              enabled: true,
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
        }
      }

      await settle();
      await tester.tap(find.byTooltip('Add attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose files'));
      await tester.pump();
      if (mode == 'new-session') security.epoch++;
      security.events.add(null); // Platform picker pauses/resumes the Activity.
      if (mode == 'denied') {
        selected.completeError(
          const AttachmentSelectionFailure(
            AttachmentSelectionFailureCode.denied,
          ),
        );
      } else {
        selected.complete(
          mode == 'cancelled'
              ? []
              : [
                  AttachmentInput(
                    fileName: 'invalid.txt',
                    mimeType: 'text/plain',
                    sizeBytes: 22020096,
                    openRead: ([a, b]) => const Stream.empty(),
                  ),
                ],
        );
      }
      await settle();
      final expected = mode == 'denied'
          ? 'File or camera access was denied'
          : 'Attachment operation failed';
      if (mode == 'invalid' || mode == 'denied') {
        expect(find.textContaining(expected), findsOneWidget);
        // Background retries must not erase an explicit picker failure.
        await tester.pump(const Duration(seconds: 4));
        await settle();
        expect(find.textContaining(expected), findsOneWidget);
      } else {
        expect(
          find.textContaining('Attachment operation failed'),
          findsNothing,
        );
        expect(
          find.textContaining('File or camera access was denied'),
          findsNothing,
        );
      }
      expect(uploads, 0);
      expect(store.state.notes.single.attachments, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
