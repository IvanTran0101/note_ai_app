import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/domain/note_intelligence/rag_models.dart';
import 'package:note_ai_app/presentation/rag/rag_controller.dart';

import 'rag_widget_harness.dart';

void main() {
  test('reads the current snapshot before subscribing', () {
    final RagPresentationHarness harness = RagPresentationHarness();
    final RagController controller = RagController(harness.service);
    addTearDown(controller.dispose);

    expect(controller.state, same(harness.service.state));
    expect(controller.state.consent, isNull);
  });

  test('mirrors service state changes and ignores duplicates', () async {
    final RagPresentationHarness harness = RagPresentationHarness();
    final RagController controller = RagController(harness.service);
    addTearDown(controller.dispose);

    int notifications = 0;
    controller.addListener(() => notifications++);

    await harness.grant();
    await pumpEventQueue();
    expect(controller.state.consent?.accepted, isTrue);
    expect(notifications, greaterThan(0));
  });

  test('dispose cancels only its subscription and not the service', () async {
    final RagPresentationHarness harness = RagPresentationHarness();
    final RagController controller = RagController(harness.service);
    controller.dispose();

    await harness.grant();
    harness.gateway.queryScript.add(notEnoughContextResult());
    await harness.service.ask(
      question: 'after dispose',
      scope: const RagScope.account(),
    );

    expect(harness.service.state.result, isNotNull);
    expect(harness.gateway.closes, 0);
  });

  test('dispose never cancels an active question owned by the screen', () async {
    final RagPresentationHarness harness = RagPresentationHarness();
    await harness.grant();
    final Completer<RagResult> pending = Completer<RagResult>();
    harness.gateway.pendingQuery = pending;
    final RagController controller = RagController(harness.service);

    final Future<void> run = harness.service.ask(
      question: 'pending',
      scope: const RagScope.account(),
    );
    await pumpEventQueue();
    expect(harness.service.state.queryRunning, isTrue);

    controller.dispose();
    expect(harness.service.state.queryRunning, isTrue);

    pending.complete(notEnoughContextResult());
    await run;
    expect(harness.service.state.result, isNotNull);
  });
}
