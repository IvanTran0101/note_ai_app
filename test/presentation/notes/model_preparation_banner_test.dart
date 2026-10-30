import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';
import 'package:note_ai_app/presentation/notes/model_preparation_banner.dart';

void main() {
  testWidgets('shows progress and cancel globally and hides when ready', (
    tester,
  ) async {
    final holder = ModelProvisioningStatusHolder();
    addTearDown(holder.close);
    var cancelled = false;
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ModelPreparationBanner(
                reader: holder,
                onCancel: () => cancelled = true,
                onRetry: () => retried = true,
              ),
              const Text('Other app content'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    holder.publish(
      ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        downloadedBytes: 25,
        totalBytes: 100,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );
    expect(find.text('Other app content'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    await tester.tap(find.text('Cancel download'));
    expect(cancelled, isTrue);
    holder.publish(
      ModelProvisioningState(
        phase: ModelProvisioningPhase.cancelled,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Retry setup'));
    expect(retried, isTrue);
    holder.publish(
      ModelProvisioningState(
        phase: ModelProvisioningPhase.ready,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows a useful failure message and retry', (tester) async {
    final holder = ModelProvisioningStatusHolder();
    addTearDown(holder.close);
    holder.publish(
      ModelProvisioningState(
        phase: ModelProvisioningPhase.failed,
        failure: const ModelProvisioningFailure(
          code: ModelProvisioningFailureCode.downloadFailed,
        ),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelPreparationBanner(
            reader: holder,
            onCancel: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(
      find.text(
        'The model download failed. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry setup'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
