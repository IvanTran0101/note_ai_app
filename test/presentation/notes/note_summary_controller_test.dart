import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/presentation/notes/note_summary_availability.dart';
import 'package:note_ai_app/presentation/notes/note_summary_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

part 'note_summary_controller_test_support.dart';
part 'note_summary_controller_regressions.dart';

void main() {
  summaryWorkflowRegressions();
  group('NoteSummaryController consent binding', () {
    test('declining grants nothing and dispatches nothing', () async {
      final _Rig rig = _Rig(cloudConsent: true);
      rig.decision = Completer<bool>();
      final NoteSummaryController controller = rig.build();

      final Future<void> run = controller.run();
      await pumpEventQueue();
      expect(rig.store.generation, 0);

      rig.decision!.complete(false);
      await run;

      expect(rig.store.generation, 0);
      expect(rig.notes.summarizeCalls, 0);
      expect(rig.notes.lastSnapshot, isNull);
      expect(controller.isBusy, isFalse);
      expect(controller.summary, isNull);
      expect(controller.hasFailure, isFalse);
    });

    test(
      'accepting grants once and dispatches the captured revision',
      () async {
        final _Rig rig = _Rig(cloudConsent: true);
        final NoteSummaryController controller = rig.build();

        await controller.run();

        expect(rig.store.generation, greaterThan(0));
        expect(rig.notes.summarizeCalls, 1);
        expect(rig.notes.lastSnapshot, same(rig.note));
        expect(controller.summary, 'Summary of Saved synthetic body');
        expect(controller.acceptedResultCount, 1);
        expect(controller.hasFailure, isFalse);
        expect(controller.isBusy, isFalse);
      },
    );

    test('a cached grant summarizes again without another dialog', () async {
      final _Rig rig = _Rig(cloudConsent: true);
      final NoteSummaryController controller = rig.build();

      await controller.run();
      await controller.run();

      expect(rig.dialogs, 1);
      expect(rig.notes.summarizeCalls, 2);
    });

    for (final String stale in <String>[
      'note',
      'controller',
      'editor',
      'conflict',
    ]) {
      test(
        'a $stale change while the dialog is open blocks grant and call',
        () async {
          final _Rig rig = _Rig(cloudConsent: true);
          rig.decision = Completer<bool>();
          final NoteSummaryController controller = rig.build();

          final Future<void> run = controller.run();
          await pumpEventQueue();
          if (stale == 'note') {
            rig.note = _note(content: 'Changed while consent was open');
          } else if (stale == 'controller') {
            rig.replacement = _FakeNotesController();
          } else if (stale == 'editor') {
            rig.dirty = true;
          } else {
            rig.conflicted = true;
          }
          rig.decision!.complete(true);
          await run;

          expect(rig.notes.summarizeCalls, 0);
          expect(rig.store.generation, 0);
          expect(
            rig.store
                .capture(
                  accountUserId: 'account-a',
                  sessionGeneration: rig.session.sessionGeneration,
                )
                .isGranted,
            isFalse,
          );
          expect(controller.isBusy, isFalse);
        },
      );
    }

    test(
      'an edit that reverts while the dialog is open cancels the scope',
      () async {
        final _Rig rig = _Rig(cloudConsent: true);
        rig.decision = Completer<bool>();
        final NoteSummaryController controller = rig.build();

        final Future<void> run = controller.run();
        await pumpEventQueue();
        rig.dirty = true; // edit
        controller.cancelActive(reason: SummaryRunFailureCode.noteChanged);
        rig.dirty = false; // revert
        rig.decision!.complete(true);
        await run;

        expect(rig.notes.summarizeCalls, 0);
        expect(rig.store.generation, 0);
        expect(controller.hasFailure, isFalse);
      },
    );

    test(
      'a session change between accept and grant refuses to dispatch',
      () async {
        final _Rig rig = _Rig(cloudConsent: true);
        rig.decision = Completer<bool>();
        final NoteSummaryController controller = rig.build();

        final Future<void> run = controller.run();
        await pumpEventQueue();
        rig.session.clear();
        rig.decision!.complete(true);
        await run;

        expect(rig.notes.summarizeCalls, 0);
        expect(rig.store.generation, 0);
        expect(controller.failureCode, SummaryRunFailureCode.sessionChanged);
        expect(controller.isBusy, isFalse);
      },
    );
  });

  group('NoteSummaryController run races and failures', () {
    test(
      'cancel discards a late result and keeps the previous summary',
      () async {
        final _Rig rig = _Rig();
        final NoteSummaryController controller = rig.build();

        await controller.run();
        final String? accepted = controller.summary;

        final Completer<String> pending = Completer<String>();
        rig.notes.pending = pending;
        final Future<void> run = controller.run();
        await pumpEventQueue();
        expect(controller.isRunning, isTrue);

        controller.cancelActive();
        expect(controller.isRunning, isFalse);
        pending.complete('Late result');
        await run;

        expect(controller.summary, accepted);
        expect(controller.acceptedResultCount, 1);
        expect(controller.isRunning, isFalse);
      },
    );

    test('a late completion cannot clear the next run state', () async {
      final _Rig rig = _Rig();
      final NoteSummaryController controller = rig.build();

      final Completer<String> first = Completer<String>();
      rig.notes.pending = first;
      final Future<void> firstRun = controller.run();
      await pumpEventQueue();

      controller.cancelActive();
      final Completer<String> second = Completer<String>();
      rig.notes.pending = second;
      final Future<void> secondRun = controller.run();
      await pumpEventQueue();
      expect(controller.isRunning, isTrue);

      first.complete('Late result');
      await firstRun;
      expect(controller.isRunning, isTrue);
      expect(controller.isBusy, isTrue);

      second.complete('Second result');
      await secondRun;
      expect(controller.isRunning, isFalse);
      expect(controller.summary, 'Second result');
    });

    test('typed failures keep their code and the previous summary', () async {
      final _Rig rig = _Rig();
      final NoteSummaryController controller = rig.build();

      await controller.run();
      final String? previous = controller.summary;
      rig.notes.failure = const SummaryRunFailure(
        SummaryRunFailureCode.serviceUnavailable,
      );
      await controller.run();

      expect(controller.failureCode, SummaryRunFailureCode.serviceUnavailable);
      expect(controller.hasUntypedFailure, isFalse);
      expect(controller.summary, previous);
      expect(controller.isBusy, isFalse);

      rig.notes.failure = null;
      await controller.run();
      expect(controller.hasFailure, isFalse);
      expect(controller.summary, 'Summary of Saved synthetic body');
    });

    test('a cancelled run is not presented as a generation failure', () async {
      final _Rig rig = _Rig();
      final NoteSummaryController controller = rig.build();

      rig.notes.failure = const SummaryRunFailure(
        SummaryRunFailureCode.cancelled,
      );
      await controller.run();

      expect(controller.hasFailure, isFalse);
      expect(controller.isBusy, isFalse);
    });

    test('markStaleIfResult marks an existing result once', () async {
      final _Rig rig = _Rig();
      final NoteSummaryController controller = rig.build();

      int notifications = 0;
      controller.addListener(() => notifications++);
      controller.markStaleIfResult();
      expect(controller.isStale, isFalse);
      expect(notifications, 0);

      await controller.run();
      notifications = 0;
      controller.markStaleIfResult();
      controller.markStaleIfResult();
      expect(controller.isStale, isTrue);
      expect(notifications, 1);
    });

    testWidgets('a usable rate-limit hint disables attempts until it elapses', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final _Rig rig = _Rig();
      rig.notes.failure = const SummaryRunFailure(
        SummaryRunFailureCode.rateLimited,
        retryAfterSeconds: 2,
      );
      final NoteSummaryController controller = rig.build();

      await controller.run();
      expect(controller.failureCode, SummaryRunFailureCode.rateLimited);
      expect(controller.isCoolingDown, isTrue);
      expect(controller.canStart, isFalse);
      expect(controller.cooldownSeconds, 2);

      await controller.run();
      expect(rig.notes.summarizeCalls, 1);

      await tester.pump(const Duration(seconds: 1));
      expect(controller.cooldownSeconds, 1);
      expect(controller.canStart, isFalse);

      rig.notes.failure = null;
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isCoolingDown, isFalse);
      expect(controller.canStart, isTrue);

      await controller.run();
      expect(rig.notes.summarizeCalls, 2);
      expect(controller.hasFailure, isFalse);
    });
  });

  group('noteSummaryAvailability', () {
    test('editor facts win over consent state', () {
      final _Rig rig = _Rig(cloudConsent: true);

      NoteSummaryAvailability resolve({
        required bool hasSavedNote,
        required bool isDirty,
        required bool hasConflict,
      }) {
        return noteSummaryAvailability(
          consent: rig.notes.summaryConsent,
          hasSavedNote: hasSavedNote,
          isDirty: isDirty,
          hasConflict: hasConflict,
        );
      }

      expect(
        resolve(hasSavedNote: false, isDirty: false, hasConflict: false),
        NoteSummaryAvailability.draft,
      );
      expect(
        resolve(hasSavedNote: true, isDirty: true, hasConflict: false),
        NoteSummaryAvailability.dirty,
      );
      expect(
        resolve(hasSavedNote: true, isDirty: false, hasConflict: true),
        NoteSummaryAvailability.conflict,
      );
    });

    test('legacy seam and local runtime need no cloud dialog', () {
      final _Rig legacy = _Rig();
      final _Rig local = _Rig();
      final _Rig localUnavailable = _Rig();
      final SummaryConsentAppService localService = SummaryConsentAppService(
        currentUser: local.session,
        session: local.session,
        consent: local.store,
        isAvailable: () => true,
        cancelActiveRuns: () {},
        requiresCloudConsent: false,
      );
      final SummaryConsentAppService unavailableService =
          SummaryConsentAppService(
            currentUser: localUnavailable.session,
            session: localUnavailable.session,
            consent: localUnavailable.store,
            isAvailable: () => false,
            cancelActiveRuns: () {},
            requiresCloudConsent: false,
          );

      NoteSummaryAvailability resolve(SummaryConsentAppService? consent) {
        return noteSummaryAvailability(
          consent: consent,
          hasSavedNote: true,
          isDirty: false,
          hasConflict: false,
        );
      }

      expect(
        resolve(legacy.notes.summaryConsent),
        NoteSummaryAvailability.ready,
      );
      expect(resolve(localService), NoteSummaryAvailability.ready);
      expect(resolve(unavailableService), NoteSummaryAvailability.unavailable);
    });

    test('cloud state maps to consent, granted, unavailable, and sign-in', () {
      final _Rig rig = _Rig(cloudConsent: true);
      final SummaryConsentAppService consent = rig.notes.summaryConsent!;

      NoteSummaryAvailability resolve(SummaryConsentAppService service) {
        return noteSummaryAvailability(
          consent: service,
          hasSavedNote: true,
          isDirty: false,
          hasConflict: false,
        );
      }

      expect(resolve(consent), NoteSummaryAvailability.consentRequired);
      consent.grantConsent(consent.beginConsent());
      expect(resolve(consent), NoteSummaryAvailability.ready);

      final CurrentUserSession signedOut = CurrentUserSession();
      expect(
        resolve(
          SummaryConsentAppService(
            currentUser: signedOut,
            session: signedOut,
            consent: SummaryCloudConsent(session: signedOut),
            isAvailable: () => true,
            cancelActiveRuns: () {},
          ),
        ),
        NoteSummaryAvailability.signInRequired,
      );
    });

    test('an unavailable cloud runtime is not actionable', () {
      final _Rig rig = _Rig(cloudConsent: true, available: false);
      expect(
        noteSummaryAvailability(
          consent: rig.notes.summaryConsent,
          hasSavedNote: true,
          isDirty: false,
          hasConflict: false,
        ),
        NoteSummaryAvailability.unavailable,
      );
    });

    test('only ready and consentRequired may dispatch', () {
      for (final NoteSummaryAvailability value
          in NoteSummaryAvailability.values) {
        final bool expected =
            value == NoteSummaryAvailability.ready ||
            value == NoteSummaryAvailability.consentRequired;
        expect(value.canStart, expected, reason: value.name);
      }
    });
  });
}
