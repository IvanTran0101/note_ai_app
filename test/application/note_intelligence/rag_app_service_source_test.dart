import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/notes/note_dto.dart';
import 'package:note_ai_app/application/sync/local_note_state.dart';
import 'package:note_ai_app/application/sync/note_sync_status.dart';
import 'package:note_ai_app/application/sync/pending_mutation.dart';
import 'package:note_ai_app/application/sync/sync_conflict.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/domain/notes/note_protection.dart';

import 'rag_test_support.dart';

void main() {
  group('validateSource', () {
    test('returns the verified note for a current owned source', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;

      final NoteDto dto = await displayed.harness.service.validateSource(
        displayed.sources.single,
      );

      expect(dto.id, note.id);
      expect(dto.ownerId, note.ownerId);
      expect(dto.content, note.content);
      expect(dto.contentRevision, note.serverRevision);
      expect(dto.isProtected, isFalse);
      expect(displayed.harness.readLocalStateCalls, 1);
    });

    test('accepts a half-open span around an emoji code point', () async {
      const String content = 'plan \u{1F600} then ship';
      final LocalNoteState note = ownedNote(content: content);
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);

      final NoteDto dto = await displayed.harness.service.validateSource(
        displayed.sources.single,
      );

      expect(dto.content, content);
    });

    test('refuses a citation the displayed answer does not carry', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      final RagSource foreign = RagSource(
        sourceId: 'source-9',
        noteId: note.id,
        revision: note.serverRevision,
        title: note.title,
        startOffset: 0,
        endOffset: 4,
        quote: 'Body',
      );
      displayed.harness.readLocalStateCalls = 0;

      await expectLater(
        displayed.harness.service.validateSource(foreign),
        throwsFailure(RagFailureCode.sourceChanged),
      );

      expect(displayed.harness.readLocalStateCalls, 0);
      expect(displayed.harness.service.state.result, isNotNull);
    });

    test('a revoked grant leaves no clickable source', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.gateway.writeScript.add(
        RagConsent(accepted: false, generation: 2),
      );

      await displayed.harness.service.setConsent(false);

      expect(displayed.harness.service.state.result, isNull);
      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('an unknown canonical grant refuses to open a source', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);

      displayed.harness.session.advance();

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.consentUnknown),
      );
    });

    test('rejects a missing, deleted, or unavailable note', () async {
      final DisplayedAnswer missing = await displayedAnswer(<LocalNoteState>[
        ownedNote(id: 'gone'),
      ]);
      missing.harness.local = localState();
      await expectLater(
        missing.harness.service.validateSource(missing.sources.single),
        throwsFailure(RagFailureCode.sourceUnavailable),
      );
      expect(missing.harness.service.state.result, isNull);

      final DisplayedAnswer deleted = await displayedAnswer(<LocalNoteState>[
        ownedNote(id: 'gone'),
      ]);
      deleted.harness.local = localState(
        notes: <LocalNoteState>[
          ownedNote(id: 'gone', deletedAt: DateTime.utc(2026, 1, 2)),
        ],
      );
      await expectLater(
        deleted.harness.service.validateSource(deleted.sources.single),
        throwsFailure(RagFailureCode.sourceUnavailable),
      );

      final DisplayedAnswer locked = await displayedAnswer(<LocalNoteState>[
        ownedNote(id: 'locked'),
      ]);
      locked.harness.local = localState(
        notes: <LocalNoteState>[
          ownedNote(id: 'locked', contentAvailable: false, title: '', content: ''),
        ],
      );
      await expectLater(
        locked.harness.service.validateSource(locked.sources.single),
        throwsFailure(RagFailureCode.sourceUnavailable),
      );
    });

    test('rejects a protected note even while it is unlocked', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[
          ownedNote(protection: NoteProtection(enabled: true, revision: 2)),
        ],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceUnavailable),
      );
    });

    test('rejects a note that became an incoming projection', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[incomingNote(id: note.id)],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceUnavailable),
      );
    });

    test('rejects a revision that is not the current synced one', () async {
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        ownedNote(serverRevision: 3),
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(serverRevision: 4)],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('rejects an unsynced note whose revision is still zero', () async {
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        ownedNote(serverRevision: 3),
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(serverRevision: 0)],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('rejects a note with a pending local change', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[note],
        outbox: <PendingMutation>[pendingUpdate(noteId: note.id)],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('rejects a note in conflict state or with a recorded conflict',
        () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer conflicted = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      conflicted.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(status: NoteSyncStatus.conflict)],
      );
      await expectLater(
        conflicted.harness.service.validateSource(conflicted.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );

      final DisplayedAnswer recorded = await displayedAnswer(<LocalNoteState>[
        ownedNote(id: 'note-2'),
      ]);
      recorded.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(id: 'note-2')],
        conflicts: <SyncConflict>[conflictFor(ownedNote(id: 'note-2'))],
      );
      await expectLater(
        recorded.harness.service.validateSource(recorded.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('rejects a quote that is not the exact current slice', () async {
      final LocalNoteState note = ownedNote(content: 'Alpha Beta Gamma');
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Alphb Beta Gamma')],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('rejects a source whose span runs past the note content', () async {
      final LocalNoteState note = ownedNote(content: 'Short body');
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Short')],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );
    });

    test('a source failure clears the displayed answer', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[ownedNote(content: 'Changed body')],
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );

      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.resultQuestion, isNull);
      expect(
        displayed.harness.service.state.failure?.code,
        RagFailureCode.sourceChanged,
      );
    });

    test('a session change while reading the local state rejects the open',
        () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);

      final Future<NoteDto> pending = displayed.harness.service.validateSource(
        displayed.sources.single,
      );
      displayed.harness.session.advance();

      await expectLater(pending, throwsFailure(RagFailureCode.sessionChanged));
    });

    test('an unauthenticated open is refused', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.currentUser.signOut();

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.unauthorized),
      );
    });

    test('an inactive app refuses to open a source', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.service.onInactive();

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.cancelled),
      );
    });

    test('a storage failure is reported as a safe local code', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.localStateError = StateError('storage offline');

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.localStateUnavailable),
      );

      // An unreadable store proves nothing about the citation.
      expect(displayed.harness.service.state.result, isNotNull);
    });

    test('a disposed service refuses to open a source', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.service.dispose();

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.cancelled),
      );
    });

    test('an unrelated local draft never blocks a current citation', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.local = localState(
        notes: <LocalNoteState>[
          note,
          ownedNote(
            id: 'draft-1',
            title: 'Draft',
            content: 'Unsynced draft',
            serverRevision: 0,
          ),
        ],
      );

      final NoteDto dto = await displayed.harness.service.validateSource(
        displayed.sources.single,
      );

      expect(dto.id, note.id);
    });
  });

  group('answer application', () {
    test('refuses a whole answer when one citation is stale', () async {
      final LocalNoteState first = ownedNote();
      final LocalNoteState second = ownedNote(id: 'note-2', content: 'Second body');
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[
            sourceFor(first, sourceId: 'source-1'),
            sourceFor(second, sourceId: 'source-2'),
          ]),
        ],
        local: localState(notes: <LocalNoteState>[first, second]),
      );
      await harness.grant();

      await harness.service.ask(
        question: 'Both?',
        scope: const RagScope.account(),
      );
      expect(harness.service.state.result, isNotNull);

      harness.local = localState(
        notes: <LocalNoteState>[
          first,
          ownedNote(id: 'note-2', content: 'Changed body'),
        ],
      );
      harness.readLocalStateCalls = 0;
      await harness.service.ask(
        question: 'Both again?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.failure?.code, RagFailureCode.sourceChanged);
      expect(harness.service.state.resultQuestion, 'Both?');
      expect(harness.service.state.result?.answer, 'Answer [S1]');
      expect(harness.readLocalStateCalls, 1);
    });

    test('applies an answer whose citations are all current', () async {
      final LocalNoteState first = ownedNote();
      final LocalNoteState second = ownedNote(id: 'note-2', content: 'Second body');
      final RagHarness harness = RagHarness(
        queryScript: <Object>[
          answeredResult(<RagSource>[
            sourceFor(first, sourceId: 'source-1'),
            sourceFor(second, sourceId: 'source-2'),
          ]),
        ],
        local: localState(notes: <LocalNoteState>[first, second]),
      );
      await harness.grant();

      await harness.service.ask(
        question: 'Both?',
        scope: const RagScope.account(),
      );

      expect(harness.service.state.result?.sources, hasLength(2));
      expect(harness.service.state.failure, isNull);
      expect(harness.readLocalStateCalls, 1);
    });
  });

  group('canonical grant revalidation', () {
    test('a remote revoke blocks the open with one fresh read and no note',
        () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;
      final int dispatched = displayed.harness.gateway.calls.length;
      // The same account, on another device, withdrew the grant.
      displayed.harness.gateway.consentScript.add(
        RagConsent(accepted: false, generation: 2),
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.consentRequired),
      );

      expect(displayed.harness.gateway.calls.length, dispatched + 1);
      expect(displayed.harness.gateway.calls.last, 'readConsent');
      // Nothing was navigated to: the local store was never consulted.
      expect(displayed.harness.readLocalStateCalls, 0);
      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.resultQuestion, isNull);
      expect(
        displayed.harness.service.state.consent,
        RagConsent(accepted: false, generation: 2),
      );
      expect(
        displayed.harness.service.state.failure?.code,
        RagFailureCode.consentRequired,
      );
    });

    test('a moved accepted grant and a revoke are distinguished when opening',
        () async {
      final LocalNoteState note = ownedNote();

      // The same account, on another device, re-granted at a new generation:
      // permission still stands, so only the answer it did not authorize is
      // stale.
      final DisplayedAnswer moved = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      moved.harness.readLocalStateCalls = 0;
      moved.harness.gateway.consentScript.add(
        RagConsent(accepted: true, generation: 2),
      );

      await expectLater(
        moved.harness.service.validateSource(moved.sources.single),
        throwsFailure(RagFailureCode.sourceChanged),
      );

      // Nothing was navigated to, the stale pair was cleared, and the moved
      // grant is still an accepted grant.
      expect(moved.harness.readLocalStateCalls, 0);
      expect(moved.harness.service.state.result, isNull);
      expect(moved.harness.service.state.resultQuestion, isNull);
      expect(moved.harness.service.state.consentAccepted, isTrue);
      expect(
        moved.harness.service.state.consent,
        RagConsent(accepted: true, generation: 2),
      );
      expect(
        moved.harness.service.state.failure?.code,
        RagFailureCode.sourceChanged,
      );

      // The permission itself was withdrawn: the open stays a consent problem.
      final DisplayedAnswer revoked = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      revoked.harness.readLocalStateCalls = 0;
      revoked.harness.gateway.consentScript.add(
        RagConsent(accepted: false, generation: 2),
      );

      await expectLater(
        revoked.harness.service.validateSource(revoked.sources.single),
        throwsFailure(RagFailureCode.consentRequired),
      );

      expect(revoked.harness.readLocalStateCalls, 0);
      expect(revoked.harness.service.state.result, isNull);
      expect(revoked.harness.service.state.resultQuestion, isNull);
      expect(revoked.harness.service.state.consentAccepted, isFalse);
      expect(
        revoked.harness.service.state.failure?.code,
        RagFailureCode.consentRequired,
      );
    });

    test('a failed canonical read forgets the grant and the answer', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;
      displayed.harness.gateway.consentScript.add(
        const RagFailure(RagFailureCode.providerUnavailable),
      );

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.providerUnavailable),
      );

      expect(displayed.harness.readLocalStateCalls, 0);
      expect(displayed.harness.service.state.consent, isNull);
      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.canAsk, isFalse);
    });

    test('a fresh matching grant opens with one read and one local read',
        () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;
      final int dispatched = displayed.harness.gateway.calls.length;

      final NoteDto dto = await displayed.harness.service.validateSource(
        displayed.sources.single,
      );

      expect(dto.id, note.id);
      expect(displayed.harness.gateway.calls.length, dispatched + 1);
      expect(displayed.harness.gateway.calls.last, 'readConsent');
      expect(displayed.harness.readLocalStateCalls, 1);
      expect(displayed.harness.service.state.result, isNotNull);
    });

    test('a pending canonical read blocks the open without a request', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.gateway.pendingConsentRead = Completer<RagConsent>();
      final Future<void> refresh = displayed.harness.service.refreshConsent();
      await pumpEventQueue();
      expect(displayed.harness.service.state.consentLoading, isTrue);
      final int dispatched = displayed.harness.gateway.calls.length;

      await expectLater(
        displayed.harness.service.validateSource(displayed.sources.single),
        throwsFailure(RagFailureCode.consentUnknown),
      );

      expect(displayed.harness.gateway.calls.length, dispatched);
      // The open is refused, but a read in flight proves nothing: the retained
      // pair stays until the grant is actually known.
      expect(displayed.harness.service.state.result, isNotNull);

      displayed.harness.gateway.pendingConsentRead!.complete(
        RagConsent(accepted: true, generation: 1),
      );
      await refresh;
      expect(displayed.harness.service.state.consentAccepted, isTrue);
    });

    test('logout during the canonical read never returns a note', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;
      displayed.harness.gateway.pendingConsentRead = Completer<RagConsent>();
      final Future<Object?> open = displayed.harness.service
          .validateSource(displayed.sources.single)
          .then<Object?>(
            (Object? value) => value,
            onError: (Object error) => error,
          );
      await pumpEventQueue();

      displayed.harness.service.invalidateSession();

      expect(
        await open,
        isA<RagFailure>().having(
          (RagFailure f) => f.code,
          'code',
          RagFailureCode.sessionChanged,
        ),
      );
      expect(displayed.harness.service.state.result, isNull);
      expect(displayed.harness.service.state.consent, isNull);
      expect(displayed.harness.readLocalStateCalls, 0);
    });

    test('a deadline during the canonical read never returns a note', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;
      displayed.harness.clock.step = const Duration(seconds: 30);
      displayed.harness.gateway.pendingConsentRead = Completer<RagConsent>();
      final Future<Object?> open = displayed.harness.service
          .validateSource(displayed.sources.single)
          .then<Object?>(
            (Object? value) => value,
            onError: (Object error) => error,
          );

      expect(
        await open,
        isA<RagFailure>().having(
          (RagFailure f) => f.code,
          'code',
          RagFailureCode.timeout,
        ),
      );
      expect(displayed.harness.readLocalStateCalls, 0);
    });

    test('the source guard performs no gateway read of its own', () async {
      final LocalNoteState note = ownedNote();
      final DisplayedAnswer displayed = await displayedAnswer(<LocalNoteState>[
        note,
      ]);
      displayed.harness.readLocalStateCalls = 0;
      await displayed.harness.service.validateSource(displayed.sources.single);
      final RagCallContext context = displayed.harness.gateway.contexts.last;
      final int dispatched = displayed.harness.gateway.calls.length;

      await context.beforeDispatch();

      expect(displayed.harness.gateway.calls.length, dispatched);
      expect(displayed.harness.readLocalStateCalls, 1);
    });
  });
}
