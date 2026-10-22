typedef EvidenceHandler = Future<Map<String, Object?>> Function(
  String,
  Map<String, Object?>,
);

class EvidenceServer {
  Future<void> close() async {}
}

Future<EvidenceServer> startEvidenceServer(EvidenceHandler handler) async =>
    EvidenceServer();
