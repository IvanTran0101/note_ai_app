import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'trace.dart';

typedef EvidenceHandler = Future<Map<String, Object?>> Function(
  String,
  Map<String, Object?>,
);

class EvidenceServer {
  EvidenceServer(this.server);
  final HttpServer server;
  Future<void> close() => server.close(force: true);
}

Future<EvidenceServer> startEvidenceServer(EvidenceHandler handler) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    8765,
  );
  server.listen((HttpRequest request) async {
    try {
      if (request.contentLength > 1048576) {
        request.response.statusCode = 413;
      } else if (request.method != 'POST' &&
          !(request.method == 'GET' && request.uri.path == '/status')) {
        request.response.statusCode = 405;
      } else {
        final String body = await utf8.decoder.bind(request).join();
        final Map<String, Object?> data = body.isEmpty
            ? <String, Object?>{}
            : (jsonDecode(body) as Map<String, dynamic>)
                  .cast<String, Object?>();
        final Map<String, Object?> result = await handler(
          request.uri.path,
          data,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      }
    } on Object catch (error) {
      request.response.statusCode = 500;
      request.response.write(
        jsonEncode(<String, Object?>{'error': error.toString()}),
      );
    } finally {
      await request.response.close();
    }
  });
  evidenceTrace('evidence_server_ready', <String, Object?>{
    'address': '127.0.0.1',
    'port': 8765,
  });
  return EvidenceServer(server);
}
