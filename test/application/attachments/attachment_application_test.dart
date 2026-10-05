import 'dart:async';

import 'package:flutter/material.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/presentation/notes/attachment_editor_panel.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/attachments/attachment_application.dart';
import 'package:note_ai_app/application/attachments/attachment_binding.dart';
import 'package:note_ai_app/application/attachments/attachment_draft_store.dart';
import 'package:note_ai_app/application/attachments/attachment_input.dart';
import 'package:note_ai_app/application/attachments/attachment_media.dart';
import 'package:note_ai_app/application/attachments/local_attachment_draft.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/local_sync_state.dart';
import 'package:note_ai_app/domain/notes/attachment.dart';
import 'package:note_ai_app/domain/notes/note_identity.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';
import 'package:note_ai_app/infrastructure/notes/note_repository.dart';

import '../../infrastructure/notes/note_repository_test_support.dart';

final time = DateTime.utc(2026, 10, 4);
const draft = LocalAttachmentDraft(
  cacheId: 'attempt',
  fileName: 'hello.txt',
  mimeType: 'text/plain',
  sizeBytes: 5,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  chunkCount: 1,
);

Attachment verified({String? checksum}) => Attachment(
  id: draft.cacheId,
  noteId: 'note',
  fileName: draft.fileName,
  mimeType: draft.mimeType,
  sizeBytes: draft.sizeBytes,
  storageObjectId: 'object',
  objectVersion: 'v1',
  sha256: checksum ?? draft.sha256,
  addedAt: time,
);

final class _Drafts implements AttachmentDraftStore {
  bool queued = false, linked = false, failLink = false;
  @override
  Future<void> recoverIncomplete(AttachmentBinding binding) async {}
  @override
  Future<LocalAttachmentDraft> stage(
    AttachmentBinding binding,
    AttachmentInput input, {
    required Iterable<Attachment> existing,
  }) async {
    queued = true;
    return draft;
  }

  @override
  Future<List<String>> pendingIds(AttachmentBinding binding) async =>
      queued ? [draft.cacheId] : [];
  @override
  Future<LocalAttachmentDraft> load(
    AttachmentBinding binding,
    String id,
  ) async {
    if (id != draft.cacheId || (!queued && !linked)) {
      throw StateError('missing');
    }
    return draft;
  }

  @override
  Stream<List<int>> read(
    AttachmentBinding binding,
    LocalAttachmentDraft value, {
    int start = 0,
    int? end,
  }) => Stream.value([104, 101, 108, 108, 111]);
  @override
  Future<void> markLinked(AttachmentBinding binding, String id) async {
    if (failLink) throw StateError('disk failure');
    linked = true;
    queued = false;
  }

  @override
  Future<void> cancelLocal(AttachmentBinding binding, String id) async {
    queued = false;
  }
}

final class _MediaBridge implements AttachmentMediaBridge {
  AttachmentMediaRequest? request;
  final handle = _MediaHandle();
  Completer<void>? wait;
  @override
  Future<AttachmentMediaHandle> open(AttachmentMediaRequest value) async {
    request = value;
    if (wait != null) await wait!.future;
    return handle;
  }
}

final class _MediaHandle implements AttachmentMediaHandle {
  bool closed = false;
  @override
  Uri get uri => Uri.parse('http://127.0.0.1/transient');
  @override
  bool get exported => false;
  @override
  Future<void> close() async => closed = true;
}

final class _PanelAttachments implements AttachmentNotesController {
  _PanelAttachments(this.attachments);
  @override
  final AttachmentApplicationService attachments;
  @override
  Future<List<AttachmentInput>> pickAttachments(
    AttachmentSource source,
  ) async => [];
}

final class _PanelSecurity implements SecuredNotesController {
  final events = StreamController<void>.broadcast(sync: true);
  bool allowed = true;
  @override
  NoteSecurityService? get noteSecurity => null;
  @override
  Stream<void> get securityChanges => events.stream;
  @override
  int get accessGeneration => allowed ? 0 : 1;
  @override
  int get sessionGeneration => 1;
  @override
  bool get securityServerAvailable => false;
  @override
  Future<NoteDto> readNote(String id) async => throw UnimplementedError();
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      NoteAccessCapabilities(
        canRead: allowed,
        canManage: allowed,
        canExport: allowed,
      );
  void invalidate() {
    allowed = false;
    events.add(null);
  }
}

void main() {
  late FakeLocalSyncStore store;
  late NoteRepository repository;
  late _Drafts drafts;
  late AttachmentApplicationService service;
  late _MediaBridge media;
  var readAborts = 0;
  var exportAllowed = true;
  var actor = 'owner', allowed = true, uploads = 0, syncs = 0;
  var leaseGeneration = 0, sessionEpoch = 1, contentEpoch = 1;
  late UploadAttachment transport;
  setUp(() {
    actor = 'owner';
    leaseGeneration = 0;
    sessionEpoch = 1;
    contentEpoch = 1;
    allowed = true;
    exportAllowed = true;
    readAborts = 0;
    media = _MediaBridge();
    uploads = 0;
    syncs = 0;
    store = FakeLocalSyncStore(
      accountUserId: 'owner',
      initial: LocalSyncState(
        accountUserId: 'owner',
        notes: [
          LocalNoteState(
            id: 'note',
            ownerId: 'owner',
            title: 'Title',
            content: 'Body',
            createdAt: time,
            updatedAt: time,
            pinnedAt: time,
            serverRevision: 1,
          ),
        ],
      ),
    );
    var mutation = 0;
    repository = NoteRepository(
      currentAccountUserId: () => 'owner',
      localSyncStoreFactory: ({required accountUserId}) => store,
      generateMutationId: () => 'mutation-${++mutation}',
      now: () => time,
    );
    drafts = _Drafts();
    transport = (binding, file, openRead) async {
      uploads++;
      expect(drafts.queued, isTrue);
      expect(await openRead().expand((bytes) => bytes).toList(), [
        104,
        101,
        108,
        108,
        111,
      ]);
      return verified();
    };
    service = AttachmentApplicationService(
      notes: repository,
      drafts: drafts,
      captureBinding: (id) async => AttachmentBinding(
        actorId: actor,
        note: NoteIdentity('owner', id),
        protection: const NoteProtection.unprotected(),
        accessRevision: 0,
        sessionGeneration: sessionEpoch,
        contentRevision: contentEpoch,
        accessGeneration: leaseGeneration,
      ),
      requireAccess: (binding, operation) {
        if (!allowed || binding.accessGeneration != leaseGeneration) {
          throw StateError('locked/session changed');
        }
        if (operation == NoteOperation.export && !exportAllowed) {
          throw const NoteSecurityFailure(NoteSecurityFailureCode.denied);
        }
      },
      upload: (binding, file, openRead) => transport(binding, file, openRead),
      now: () => time,
      requestSync: (_) => syncs++,
      mediaBridge: media,
      cancelRemoteRead: (_, _) => readAborts++,
      remoteRead: (_, _, {int start = 0, int? end}) =>
          Stream.value([1, 2, 3, 4, 5].sublist(start, end)),
      remoteExportRead: (_, _, {int start = 0, int? end}) =>
          Stream.value([1, 2, 3, 4, 5].sublist(start, end)),
    );
  });
  test(
    'Native picker cancellation after a lifecycle lock has no false error',
    () async {
      await service.pickAndStage('note', () async {
        allowed = false;
        leaseGeneration++;
        return [];
      });
      expect(drafts.queued, false);
      expect(store.state.outbox, isEmpty);
    },
  );

  Future<void> stage() async {
    await service.stage(
      'note',
      AttachmentInput(
        fileName: 'hello.txt',
        mimeType: 'text/plain',
        sizeBytes: 5,
        openRead: ([start, end]) => Stream.value([1]),
      ),
    );
  }

  test(
    'Pending media is scoped; closing aborts reads but retains local draft',
    () async {
      await stage();
      final handle = await service.openPendingMedia('note', draft);
      expect(await media.request!.read(0, 5).expand((b) => b).toList(), [
        104,
        101,
        108,
        108,
        111,
      ]);
      await handle.close();
      await expectLater(
        media.request!.authorize(),
        throwsA(isA<NoteSecurityFailure>()),
      );
      expect(media.handle.closed, true);
      expect(readAborts, 1);
      expect(drafts.queued, true);
      await handle.close();
      expect(readAborts, 1);
    },
  );

  test(
    'Cancel while bridge is opening closes eventual handle and retains bytes',
    () async {
      await stage();
      media.wait = Completer<void>();
      final work = service.openPendingMedia('note', draft);
      final assertion = expectLater(work, throwsA(isA<NoteSecurityFailure>()));
      while (media.request == null) {
        await Future<void>.delayed(Duration.zero);
      }
      service.cancelMedia('note', draft.cacheId);
      media.wait!.complete();
      await assertion;
      expect(media.handle.closed, true);
      expect(readAborts, 1);
      expect(drafts.queued, true);
    },
  );

  test('Media guards fresh manifest, lock and separate export scope', () async {
    await stage();
    await service.retry('note', draft.cacheId);
    exportAllowed = false;
    await expectLater(
      service.openExport('note', verified()),
      throwsA(isA<NoteSecurityFailure>()),
    );
    expect(media.request, null);
    final handle = await service.openMedia('note', verified());
    expect(media.request!.exportFile, false);
    await service.remove('note', draft.cacheId);
    await expectLater(
      media.request!.authorize(),
      throwsA(isA<NoteSecurityFailure>()),
    );
    await handle.close();
  });

  test(
    'An opened media capability cannot survive an access-generation change',
    () async {
      await stage();
      final handle = await service.openPendingMedia('note', draft);
      leaseGeneration++;
      await expectLater(media.request!.authorize(), throwsStateError);
      await handle.close();
      expect(readAborts, 1);
    },
  );

  test(
    'stage is local-first; upload uses the fresh M02 atomic writer',
    () async {
      await stage();
      expect(uploads, 0);
      expect(store.state.outbox, isEmpty);
      expect(await service.pending('note'), [draft]);
      await repository.updateById(
        noteId: 'note',
        ownerId: 'owner',
        canCommit: () => true,
        expectedAccountUserId: 'owner',
        change: (note) {
          note.replaceText('New text', 'New body', time);
          return note;
        },
      );
      final result = await service.retry('note', draft.cacheId);
      expect(result.title, 'New text');
      expect(result.content, 'New body');
      expect(result.pinnedAt, time);
      expect(result.attachments, [verified()]);
      expect(store.state.outbox.last.payload!.attachments, [verified()]);
      expect(syncs, 1);
      expect(drafts.linked, isTrue);
      expect(await service.pending('note'), isEmpty);
    },
  );

  test(
    'network failure preserves the queued draft and never changes the note',
    () async {
      await stage();
      transport = (_, _, _) async => throw StateError('offline');
      await expectLater(service.retry('note', draft.cacheId), throwsStateError);
      expect(drafts.queued, isTrue);
      expect(store.state.notes.single.attachments, isEmpty);
      expect(store.state.outbox, isEmpty);
    },
  );

  test('server descriptor mismatch cannot enter the aggregate', () async {
    await stage();
    transport = (_, _, _) async => verified(checksum: 'b' * 64);
    await expectLater(service.retry('note', draft.cacheId), throwsStateError);
    expect(store.state.notes.single.attachments, isEmpty);
    expect(drafts.queued, isTrue);
  });

  test('lock while upload is in flight prevents note commit', () async {
    await stage();
    transport = (_, _, _) async {
      allowed = false;
      return verified();
    };
    await expectLater(service.retry('note', draft.cacheId), throwsStateError);
    expect(store.state.notes.single.attachments, isEmpty);
    expect(drafts.queued, isTrue);
  });

  test(
    'retry recovers a committed note after cache checkpoint failure',
    () async {
      await stage();
      drafts.failLink = true;
      await expectLater(service.retry('note', draft.cacheId), throwsStateError);
      expect(store.state.notes.single.attachments, [verified()]);
      final count = store.state.outbox.length;
      drafts.failLink = false;
      await service.retry('note', draft.cacheId);
      expect(uploads, 1);
      expect(store.state.outbox.length, count);
      expect(drafts.linked, isTrue);
    },
  );

  test(
    'unprotected picker can reacquire only a stable session after pause',
    () async {
      await service.pickAndStage('note', () async {
        leaseGeneration++;
        return [
          AttachmentInput(
            fileName: 'hello.txt',
            mimeType: 'text/plain',
            sizeBytes: 5,
            openRead: ([start, end]) => Stream.value([1]),
          ),
        ];
      });
      expect(drafts.queued, isTrue);
      expect(store.state.outbox, isEmpty);
      expect(uploads, 0);
    },
  );
  for (final change in ['session', 'content', 'actor']) {
    test('picker cannot reacquire after $change changed', () async {
      await expectLater(
        service.pickAndStage('note', () async {
          leaseGeneration++;
          if (change == 'session') sessionEpoch++;
          if (change == 'content') contentEpoch++;
          if (change == 'actor') actor = 'other';
          return [
            AttachmentInput(
              fileName: 'hello.txt',
              mimeType: 'text/plain',
              sizeBytes: 5,
              openRead: ([start, end]) => Stream.value([1]),
            ),
          ];
        }),
        throwsStateError,
      );
      expect(drafts.queued, isFalse);
      expect(store.state.outbox, isEmpty);
    });
  }

  test('picker result is rejected after authority changes', () async {
    final selected = Completer<List<AttachmentInput>>();
    final started = Completer<void>();
    final work = service.pickAndStage('note', () {
      started.complete();
      return selected.future;
    });
    await started.future;
    allowed = false;
    selected.complete([
      AttachmentInput(
        fileName: 'hello.txt',
        mimeType: 'text/plain',
        sizeBytes: 5,
        openRead: ([start, end]) => Stream.value([104, 101, 108, 108, 111]),
      ),
    ]);
    await expectLater(work, throwsStateError);
    expect(drafts.queued, isFalse);
    expect(uploads, 0);
    expect(store.state.outbox, isEmpty);
  });

  test('cancelled picker creates no pending data or note mutation', () async {
    await service.pickAndStage('note', () async => []);
    expect(drafts.queued, isFalse);
    expect(store.state.outbox, isEmpty);
  });

  test(
    'selected provider copies release after stage and early denial',
    () async {
      var releases = 0;
      AttachmentInput input() => AttachmentInput(
        fileName: 'hello.txt',
        mimeType: 'text/plain',
        sizeBytes: 5,
        openRead: ([start, end]) => Stream.value([104, 101, 108, 108, 111]),
        release: () async {
          releases++;
        },
      );
      await service.stage('note', input());
      expect(releases, 1);
      allowed = false;
      await expectLater(service.stage('note', input()), throwsStateError);
      expect(releases, 2);
    },
  );

  test('changed picker actor releases every selected provider copy', () async {
    var releases = 0;
    AttachmentInput input() => AttachmentInput(
      fileName: 'hello.txt',
      mimeType: 'text/plain',
      sizeBytes: 5,
      openRead: ([start, end]) => Stream.value([104, 101, 108, 108, 111]),
      release: () async {
        releases++;
      },
    );
    await expectLater(
      service.pickAndStage('note', () async {
        actor = 'recipient';
        return [input(), input()];
      }),
      throwsStateError,
    );
    expect(releases, 2);
    expect(drafts.queued, false);
  });

  test('local reader rechecks authority at stream completion', () async {
    await stage();
    final work = service.readLocal('note', draft.cacheId).listen((chunk) {
      expect(chunk, [104, 101, 108, 108, 111]);
      allowed = false;
    }).asFuture<void>();
    await expectLater(work, throwsStateError);
    expect(uploads, 0);
    expect(store.state.outbox, isEmpty);
    expect(drafts.queued, isTrue);
  });

  testWidgets(
    'Pending editor retry retains draft; lock clears preview and names',
    (tester) async {
      Future<void> settlePanel() async {
        // The repository fake schedules a zero-delay timer for each read.
        // Flush those timers even while the idle panel has no scheduled frame.
        // The panel deliberately polls Pending/Ready every3s. pumpAndSettle
        // cannot prove idleness of a periodic browser UI; advance bounded steps
        // and assert that the actual transfer indicator has stopped instead.
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsNothing);
      }

      await tester.runAsync(stage);
      transport = (_, _, _) async =>
          throw const NoteSecurityFailure(NoteSecurityFailureCode.unavailable);
      final security = _PanelSecurity();
      addTearDown(security.events.close);
      final domainNote = await tester.runAsync(
        () => repository.findById('note'),
      );
      final note = NoteDto.fromDomain(domainNote!);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentEditorPanel(
              note: note,
              controller: _PanelAttachments(service),
              security: security,
              enabled: true,
            ),
          ),
        ),
      );
      await settlePanel();
      expect(
        find.text('hello.txt'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '),
      );
      expect(find.textContaining('Pending on this device'), findsOneWidget);
      await tester.tap(find.byTooltip('Retry upload'));
      await settlePanel();
      expect(
        find.textContaining('Cloud attachments are unavailable'),
        findsOneWidget,
      );
      expect(drafts.queued, isTrue);
      expect(store.state.outbox, isEmpty);
      await tester.tap(find.text('hello.txt'));
      await settlePanel();
      expect(find.text('hello'), findsOneWidget);
      allowed = false;
      security.invalidate();
      await settlePanel();
      expect(find.text('hello'), findsNothing);
      expect(find.text('hello.txt'), findsNothing);
      expect(drafts.queued, isTrue);
    },
  );

  test('duplicate concurrent retries share one upload', () async {
    await stage();
    final gate = Completer<Attachment>();
    final started = Completer<void>();
    transport = (_, _, _) {
      uploads++;
      started.complete();
      return gate.future;
    };
    final first = service.retry('note', draft.cacheId);
    await started.future;
    final second = service.retry('note', draft.cacheId);
    gate.complete(verified());
    final results = await Future.wait([first, second]);
    expect(results.first, results.last);
    expect(uploads, 1);
    expect(store.state.notes.single.attachments, hasLength(1));
  });

  test('cancellation during upload fences its eventual response', () async {
    await stage();
    final gate = Completer<Attachment>();
    final started = Completer<void>();
    transport = (_, _, _) {
      started.complete();
      return gate.future;
    };
    final work = service.retry('note', draft.cacheId);
    await started.future;
    await service.cancel('note', draft.cacheId);
    gate.complete(verified());
    await expectLater(work, throwsStateError);
    expect(store.state.notes.single.attachments, isEmpty);
    expect(drafts.queued, isFalse);
  });

  test(
    'viewer/editor cannot add/remove, and linked cancellation is rejected',
    () async {
      actor = 'recipient';
      await expectLater(stage(), throwsStateError);
      await expectLater(service.remove('note', 'anything'), throwsStateError);
      actor = 'owner';
      leaseGeneration = 0;
      sessionEpoch = 1;
      contentEpoch = 1;
      await stage();
      await service.retry('note', draft.cacheId);
      await expectLater(
        service.cancel('note', draft.cacheId),
        throwsStateError,
      );
      final result = await service.remove('note', draft.cacheId);
      expect(result.attachments, isEmpty);
      expect(result.title, 'Title');
      expect(result.pinnedAt, time);
      expect(store.state.outbox.last.payload!.attachments, isEmpty);
      expect(store.state.outbox.last.payload!.includesAttachments, isTrue);
    },
  );
}
