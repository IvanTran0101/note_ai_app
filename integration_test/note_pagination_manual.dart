import 'package:flutter/material.dart';
import 'package:note_ai_app/application/dashboard/get_dashboard_overview.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_controller.dart';
import 'package:note_ai_app/presentation/dashboard/dashboard_page.dart';
import 'package:note_ai_app/presentation/labels/label_catalog_scope.dart';
import 'package:note_ai_app/presentation/notes/notes_application_controller.dart';
import 'package:note_ai_app/presentation/notes/notes_workspace_page.dart';
import 'package:note_ai_app/infrastructure/security/encrypted_sync_store.dart';

import 'support/note_pagination_fixture.dart';

/// QA entrypoint only. No test binding: real browser/ADB input drives the UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = await createPaginationFixture();
  runApp(_PaginationManual(fixture));
}

class _PaginationManual extends StatefulWidget {
  const _PaginationManual(this.fixture);
  final PaginationFixture fixture;
  @override
  State<_PaginationManual> createState() => _PaginationManualState();
}

class _PaginationManualState extends State<_PaginationManual> {
  bool _home = false;
  late final _dashboard = DashboardController(
    query: GetDashboardOverview(
      noteRepository: widget.fixture.repository,
      currentUser: widget.fixture.app.currentUser,
    ),
  );
  @override
  void dispose() {
    _dashboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: LabelCatalogHost(
      application: widget.fixture.labels,
      securityChanges: const Stream.empty(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pagination QA'),
          actions: [
            Builder(
              builder: (buttonContext) => TextButton(
                onPressed: () {
                  final store = widget.fixture.store as EncryptedSyncStore;
                  showDialog<void>(
                    context: buttonContext,
                    builder: (dialogContext) => AlertDialog(
                      content: Text(
                        'Canonical decodes: ${store.codec.decodedAccountCount}\nPayload reads: ${store.pagePayloadReads}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('QA storage'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _home = false),
              child: const Text('QA Notes'),
            ),
            TextButton(
              onPressed: () => setState(() => _home = true),
              child: const Text('QA Home'),
            ),
          ],
        ),
        body: _home
            ? DashboardPage(
                dashboardController: _dashboard,
                notesController: NoteApplicationServiceController(
                  widget.fixture.app,
                ),
                onOpenNote: (_) async => null,
                onCreateNote: () async => null,
              )
            : NotesWorkspacePage(
                controller: NoteApplicationServiceController(
                  widget.fixture.app,
                ),
              ),
      ),
    ),
  );
}
