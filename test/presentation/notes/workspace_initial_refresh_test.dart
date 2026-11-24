import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_ai_app/application/notes/note_application.dart';
import 'package:note_ai_app/application/notes/note_access.dart';
import 'package:note_ai_app/application/notes/note_security_service.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_loading_view.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets('initial list superseded by security refresh, fail=$fail', (
      tester,
    ) async {
      final controller = _RefreshController();
      addTearDown(controller.events.close);
      await tester.pumpWidget(
        MaterialApp(home: NotesWorkspacePage(controller: controller)),
      );
      expect(controller.requests, hasLength(1));
      controller.events.add(null);
      await tester.pump();
      expect(controller.requests, hasLength(2));
      final date = DateTime.utc(2026);
      final fresh = NoteDto(
        id: 'fresh',
        ownerId: 'local-user',
        title: 'Fresh note',
        content: 'Retained local note',
        createdAt: date,
        updatedAt: date,
      );
      if (fail) {
        controller.requests[1].completeError(StateError('refresh unavailable'));
      } else {
        controller.requests[1].complete([fresh]);
      }
      controller.requests.first.complete([]);
      await tester.pumpAndSettle();
      expect(find.byType(NotesWorkspaceLoadingView), findsNothing);
      if (fail) {
        expect(find.text('Retry'), findsWidgets);
      } else {
        expect(find.text('Fresh note'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

/// Only list/access reads are expected; unexpected application calls fail.
class _RefreshController
    implements NotesApplicationController, SecuredNotesController {
  final events = StreamController<void>.broadcast(sync: true);
  final requests = <Completer<List<NoteDto>>>[];
  @override
  Future<List<NoteDto>> listNotes() {
    final request = Completer<List<NoteDto>>();
    requests.add(request);
    return request.future;
  }

  @override
  Stream<void> get securityChanges => events.stream;
  @override
  int get sessionGeneration => 0;
  @override
  int get accessGeneration => 0;
  @override
  bool get securityServerAvailable => false;
  @override
  NoteSecurityService? get noteSecurity => null;
  @override
  NoteAccessCapabilities capabilitiesFor(NoteDto note) =>
      const NoteAccessCapabilities(canRead: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
