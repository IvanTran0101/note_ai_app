import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/auth/current_user_session.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_failure.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_state.dart';
import 'package:note_ai_app/application/note_intelligence/model_provisioning/model_provisioning_status_holder.dart';
import 'package:note_ai_app/application/note_intelligence/summary_cloud_consent.dart';
import 'package:note_ai_app/application/note_intelligence/summary_consent_app_service.dart';
import 'package:note_ai_app/application/note_intelligence/summary_run_context.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/domain/auth/auth_identity.dart';
import 'package:note_ai_app/domain/note_intelligence/summary.dart';
import 'package:note_ai_app/domain/notes/note.dart';
import 'package:note_ai_app/domain/notes/note_repository.dart';
import 'package:note_ai_app/presentation/notes/note_detail_localizations.dart';
import 'package:note_ai_app/presentation/notes/note_detail_page.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';

final DateTime _time = DateTime.utc(2026, 10, 1);

Note _note() => Note.reconstitute(
  id: 'note-a',
  ownerId: 'account-a',
  title: 'Selected note',
  content: 'Saved synthetic body',
  createdAt: _time,
  updatedAt: _time,
);

CurrentUserSession _session() => CurrentUserSession()
  ..setIdentity(
    AuthIdentity(
      userId: 'account-a',
      email: 'a@example.test',
      isEmailVerified: true,
    ),
  );

final class _Repository implements INoteRepository {
  final Note note = _note();

  @override
  Future<Note?> findById(String id) async => id == note.id ? note : null;

  @override
  Future<List<Note>> findByOwnerId(String ownerId) async =>
      ownerId == note.ownerId ? <Note>[note] : <Note>[];

  @override
  Future<void> save(Note note) async => throw StateError('must not write');

  @override
  Future<void> deleteById(String id) async =>
      throw StateError('must not delete');
}

NoteApplicationServiceController _controller(
  SummarizeNoteContent generate, {
  SummaryConsentAppService? consent,
  SummarizeNoteRun? run,
}) => NoteApplicationServiceController(
  NoteApplicationService(
    noteRepository: _Repository(),
    currentUser: _session(),
    generateId: () => 'unused',
    now: () => _time,
    summarizeContent: generate,
    summarizeRun: run,
  ),
  summaryConsent: consent,
);

void main() {
  test('controller exposes Application consent and revoke cancels a scope', () {
    final CurrentUserSession session = _session();
    final SummaryCloudConsent store = SummaryCloudConsent(session: session);
    final SummaryRunScope scope = SummaryRunScope();
    final SummaryConsentAppService consent = SummaryConsentAppService(
      currentUser: session,
      session: session,
      consent: store,
      isAvailable: () => true,
      cancelActiveRuns: () =>
          scope.cancel(reason: SummaryRunFailureCode.consentRequired),
    );
    final NotesApplicationController controller = _controller(
      (_) async => const Summary('unused'),
      consent: consent,
    );

    expect(controller.summaryConsent, same(consent));
    expect(consent.state, SummaryConsentStatus.consentRequired);
    controller.summaryConsent!.grantConsent(consent.beginConsent());
    expect(consent.state, SummaryConsentStatus.granted);
    controller.summaryConsent!.revokeConsent();
    expect(consent.state, SummaryConsentStatus.consentRequired);
    expect(scope.cancelReason, SummaryRunFailureCode.consentRequired);
  });

  test('legacy controller has no consent dependency', () {
    expect(
      _controller((_) async => const Summary('unused')).summaryConsent,
      isNull,
    );
  });

  test(
    'summary forwards the selected snapshot/scope and returns text',
    () async {
      final NoteDto selected = NoteDto.fromDomain(_note());
      final SummaryRunScope scope = SummaryRunScope();
      SummaryRunContext? captured;
      final Completer<Summary> generated = Completer<Summary>();
      final NoteApplicationServiceController controller = _controller(
        (_) async => throw StateError('local must not run'),
        run: (SummaryRunContext context) {
          captured = context;
          return generated.future;
        },
      );
      final Future<String> pending = controller.summarizeNote(
        selected.id,
        selectedSnapshot: selected,
        scope: scope,
      );
      await Future<void>.delayed(Duration.zero);
      expect(captured!.noteSnapshot, same(selected));
      expect(captured!.scope, same(scope));
      generated.complete(const Summary('Complete synthetic summary'));
      expect(await pending, 'Complete synthetic summary');
    },
  );

  test('typed failures preserve their code and bounded hint', () async {
    const SummaryRunFailure failure = SummaryRunFailure(
      SummaryRunFailureCode.rateLimited,
      retryAfterSeconds: 15,
    );
    final controller = _controller((_) async => throw failure);
    await expectLater(
      controller.summarizeNote('note-a'),
      throwsA(same(failure)),
    );
  });

  test('unclassified summary errors cannot leak through the UI seam', () async {
    const String canary = 'synthetic-private-payload';
    final controller = _controller((_) async => throw StateError(canary));
    await expectLater(
      controller.summarizeNote('note-a'),
      throwsA(
        isA<SummaryRunFailure>()
            .having((e) => e.code, 'code', SummaryRunFailureCode.unexpected)
            .having((e) => e.toString(), 'safe text', isNot(contains(canary))),
      ),
    );
  });

  for (final ModelProvisioningPhase phase in <ModelProvisioningPhase>[
    ModelProvisioningPhase.failed,
    ModelProvisioningPhase.cancelled,
  ]) {
    testWidgets('safe local failure preserves provisioning $phase notice', (
      WidgetTester tester,
    ) async {
      final ModelProvisioningStatusHolder holder =
          ModelProvisioningStatusHolder(
            initial: ModelProvisioningState(
              phase: phase,
              modelId: 'synthetic-model',
              failure: phase == ModelProvisioningPhase.failed
                  ? const ModelProvisioningFailure(
                      code: ModelProvisioningFailureCode.downloadFailed,
                    )
                  : null,
              updatedAt: _time,
            ),
          );
      addTearDown(holder.close);
      final controller = _controller(
        (_) async =>
            throw const SummaryRunFailure(SummaryRunFailureCode.unexpected),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [NoteDetailCopy.delegate],
          home: NoteDetailPage(
            notesController: controller,
            note: NoteDto.fromDomain(_note()),
            provisioningReader: holder,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('note-detail-summarize')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('model-provisioning-status')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('note-detail-error-retry')),
        findsNothing,
      );
      expect(find.byKey(NoteDetailPage.summaryKey), findsNothing);
      expect(
        (await controller.listNotes()).single.content,
        'Saved synthetic body',
      );
    });
  }
}
