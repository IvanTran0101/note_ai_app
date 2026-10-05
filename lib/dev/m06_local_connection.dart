import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../infrastructure/configuration/note_connection.dart';
import '../infrastructure/sync/appsync_revision_source.dart';
import '../infrastructure/sync/realtime_socket.dart';

const devActors = {'owner': 'm06-dev-owner', 'recipient': 'm06-dev-recipient'};
const devEmails = {
  'owner': 'owner@example.invalid',
  'recipient': 'recipient@example.invalid',
};
final devLogicalApi = Uri.parse('https://m06-dev.invalid/');

String devToken(String actor, String use) {
  if (!kDebugMode || !devActors.values.contains(actor)) {
    throw StateError('Only the two local debug actors are supported.');
  }
  final claims = {
    'sub': actor,
    'token_use': use,
    'iss': 'm06-local-dev',
    'exp':
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000,
  };
  final encoded = base64Url
      .encode(utf8.encode(jsonEncode(claims)))
      .replaceAll('=', '');
  return 'e30.$encoded.local-dev';
}

/// This transport exists only in main_dev. Never accepts cloud URLs or tokens.
final class M06LoopbackClient extends http.BaseClient {
  M06LoopbackClient({http.Client? inner}) : _inner = inner ?? http.Client() {
    if (!kDebugMode) throw StateError('Local dev requires a debug build.');
  }
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    if (_anonymousStaging(request)) return _inner.send(request);
    if (uri.scheme != 'https' ||
        uri.host != devLogicalApi.host ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasPort) {
      throw http.ClientException('Local dev route required.');
    }
    final credential =
        request.headers['Authorization'] ?? request.headers['authorization'];
    if (credential == null || !credential.endsWith('.local-dev')) {
      throw http.ClientException('Local dev credential required.');
    }
    final localUri = uri.replace(scheme: 'http', host: '127.0.0.1', port: 8796);
    final local = request is http.AbortableRequest
        ? http.AbortableRequest(
            request.method,
            localUri,
            abortTrigger: request.abortTrigger,
          )
        : http.Request(request.method, localUri);
    local
      ..followRedirects = false
      ..maxRedirects = 0;
    local.headers.addAll(request.headers);
    local.bodyBytes = await request.finalize().toBytes();
    return _inner.send(local);
  }

  bool _anonymousStaging(http.BaseRequest request) {
    final uri = request.url;
    return request.method == 'PUT' &&
        uri.scheme == 'http' &&
        uri.host == '127.0.0.1' &&
        uri.port == 8796 &&
        uri.path == '/dev/attachment-put' &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        !request.followRedirects &&
        request.headers.keys.every(
          (name) => {
            'content-type',
            'x-amz-checksum-sha256',
            'content-length',
          }.contains(name.toLowerCase()),
        );
  }

  @override
  void close() => _inner.close();
}

NoteConnection devConnection(String actor, M06LoopbackClient client) =>
    NoteConnection(
      baseUri: devLogicalApi,
      tokenProvider: ({required forceRefresh}) async =>
          devToken(actor, 'access'),
      client: client,
      allowLocalAttachmentUploads: true,
      revisionSourceFor: (boundActor) {
        if (boundActor != actor) throw StateError('Local dev account changed.');
        return AppSyncRevisionSource(
          httpEndpoint: devLogicalApi.replace(path: '/event'),
          socketEndpoint: devLogicalApi.replace(
            scheme: 'wss',
            path: '/event/realtime',
          ),
          actorId: actor,
          tokenProvider: ({required forceRefresh}) async =>
              devToken(actor, 'id'),
          socketFactory: (_, protocols) => ChannelRealtimeSocket(
            Uri.parse('ws://127.0.0.1:8797/event/realtime'),
            protocols,
          ),
        );
      },
    );
