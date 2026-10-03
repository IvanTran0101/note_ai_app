import 'package:http/http.dart' as http;

import '../../application/sync/revision_source.dart';
import '../sync/http_remote_note_data_source.dart';

/// Optional composition collaborators. Default app wiring still uses Cognito.
final class NoteConnection {
  const NoteConnection({
    required this.baseUri,
    required this.tokenProvider,
    required this.client,
    required this.revisionSourceFor,
  });
  final Uri baseUri;
  final SyncAccessTokenProvider tokenProvider;

  /// Borrowed by adapters; the composition that supplies it owns disposal.
  final http.Client client;
  final IRevisionSource Function(String actor) revisionSourceFor;
}
