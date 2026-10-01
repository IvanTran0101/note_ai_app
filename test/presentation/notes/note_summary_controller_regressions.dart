part of 'note_summary_controller_test.dart';

void summaryWorkflowRegressions() {
  test(
    'input rejection stays blocked after failed save/revert clears the notice',
    () async {
      final rig = _Rig();
      rig.notes.failure = const SummaryRunFailure(
        SummaryRunFailureCode.inputTooLong,
      );
      final controller = rig.build();
      await controller.run();
      expect(controller.canStart, isFalse);
      controller.clearFailure();
      rig.notes.failure = null;
      await controller.run();
      expect(rig.notes.summarizeCalls, 1);
      rig.note = _note(content: 'A genuinely new saved revision');
      rig.notes.notes[0] = rig.note!;
      expect(controller.canStart, isTrue);
      await controller.run();
      expect(rig.notes.summarizeCalls, 2);
    },
  );

  for (final phase in ['dialog', 'read']) {
    test(
      '$phase exceptions restore idle with a safe failure and no grant',
      () async {
        final rig = _Rig(cloudConsent: true);
        if (phase == 'dialog') {
          rig.dialogError = StateError('synthetic canary');
        } else {
          rig.notes.readError = StateError('synthetic canary');
        }
        final controller = rig.build();
        await controller.run();
        expect(controller.isBusy, isFalse);
        expect(controller.failureCode, SummaryRunFailureCode.unexpected);
        expect(rig.notes.summarizeCalls, 0);
        expect(rig.store.generation, 0);
      },
    );
  }

  test(
    'cancelling a hung revision read finishes without clearing a newer scope',
    () async {
      final rig = _Rig();
      final read = Completer<List<NoteDto>>();
      rig.notes.pendingRead = read;
      final controller = rig.build();
      final old = controller.run();
      await pumpEventQueue();
      controller.cancelActive();
      await old.timeout(const Duration(seconds: 1));
      rig.notes.pendingRead = null;
      final output = Completer<String>();
      rig.notes.pending = output;
      final fresh = controller.run();
      await pumpEventQueue();
      read.complete(rig.notes.notes);
      await pumpEventQueue();
      expect(controller.isRunning, isTrue);
      output.complete('Fresh result');
      await fresh;
      expect(controller.summary, 'Fresh result');
    },
  );

  for (final change in ['dirty', 'conflict', 'controller']) {
    test(
      '$change change without a cancellation callback rejects the late result',
      () async {
        final rig = _Rig();
        final output = Completer<String>();
        rig.notes.pending = output;
        final controller = rig.build();
        final run = controller.run();
        await pumpEventQueue();
        if (change == 'dirty') rig.dirty = true;
        if (change == 'conflict') rig.conflicted = true;
        if (change == 'controller') {
          rig.replacement = _FakeNotesController(notes: rig.notes.notes);
        }
        output.complete('Stale result');
        await run;
        expect(controller.summary, isNull);
        expect(controller.isBusy, isFalse);
      },
    );
  }
}
