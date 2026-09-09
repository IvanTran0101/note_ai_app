import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';
import 'package:note_ai_app/presentation/notes/model_provisioning_status_panel.dart';
import 'package:note_ai_app/presentation/notes/notes_localizations.dart';

Widget _app({
  required ModelProvisioningStatusHolder holder,
  VoidCallback? onRetry,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      NotesCopy.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: ModelProvisioningStatusPanel(reader: holder, onRetry: onRetry),
    ),
  );
}

final DateTime _updatedAt = DateTime.utc(2026, 9, 9, 12);

void main() {
  testWidgets('hides idle state', (WidgetTester tester) async {
    final ModelProvisioningStatusHolder holder = ModelProvisioningStatusHolder(
      initial: ModelProvisioningState(updatedAt: _updatedAt),
    );
    addTearDown(holder.close);

    await tester.pumpWidget(_app(holder: holder));

    expect(
      find.byKey(const ValueKey<String>('model-provisioning-status')),
      findsNothing,
    );
  });

  testWidgets('shows determinate download progress and model identity', (
    WidgetTester tester,
  ) async {
    final ModelProvisioningStatusHolder holder = ModelProvisioningStatusHolder(
      initial: ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        modelId: 'gemma-3-1b-it',
        modelName: 'gemma-3-1b-it-Q4_K_M.gguf',
        downloadedBytes: 512,
        totalBytes: 1024,
        updatedAt: _updatedAt,
      ),
    );
    addTearDown(holder.close);

    await tester.pumpWidget(_app(holder: holder));

    final LinearProgressIndicator progress = tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey<String>('model-provisioning-progress')),
        );
    expect(progress.value, 0.5);
    expect(find.textContaining('gemma-3-1b-it-Q4_K_M.gguf'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('model-provisioning-bytes')),
      findsOneWidget,
    );
  });

  testWidgets('shows indeterminate progress for unknown total', (
    WidgetTester tester,
  ) async {
    final ModelProvisioningStatusHolder holder = ModelProvisioningStatusHolder(
      initial: ModelProvisioningState(
        phase: ModelProvisioningPhase.downloading,
        downloadedBytes: 4096,
        updatedAt: _updatedAt,
      ),
    );
    addTearDown(holder.close);

    await tester.pumpWidget(_app(holder: holder));

    final LinearProgressIndicator progress = tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey<String>('model-provisioning-progress')),
        );
    expect(progress.value, isNull);
  });

  testWidgets(
    'reflects a published state and offers retry for retryable errors',
    (WidgetTester tester) async {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder();
      addTearDown(holder.close);
      var retried = false;

      await tester.pumpWidget(
        _app(holder: holder, onRetry: () => retried = true),
      );
      expect(
        find.byKey(const ValueKey<String>('model-provisioning-status')),
        findsNothing,
      );

      holder.publish(
        ModelProvisioningState(
          phase: ModelProvisioningPhase.failed,
          failure: const ModelProvisioningFailure(
            code: ModelProvisioningFailureCode.downloadFailed,
          ),
          updatedAt: _updatedAt,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('model-provisioning-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('model-provisioning-retry')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('model-provisioning-retry')),
      );
      expect(retried, isTrue);
    },
  );

  testWidgets(
    'hides retry for non-retryable errors and localizes Vietnamese copy',
    (WidgetTester tester) async {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder(
            initial: ModelProvisioningState(
              phase: ModelProvisioningPhase.failed,
              failure: const ModelProvisioningFailure(
                code: ModelProvisioningFailureCode.noCompatibleModel,
              ),
              updatedAt: _updatedAt,
            ),
          );
      addTearDown(holder.close);

      await tester.pumpWidget(_app(holder: holder, locale: const Locale('vi')));

      expect(
        find.text('Thiết bị chưa có mô hình tương thích.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('model-provisioning-retry')),
        findsNothing,
      );
    },
  );
}
