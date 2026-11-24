import 'package:web_socket_channel/web_socket_channel.dart';

/// Transport seam for protocol fixtures on both browser and native platforms.
abstract interface class RealtimeSocket {
  Future<void> get ready;
  Stream<Object?> get messages;
  void send(String frame);
  Future<void> close();
}

typedef RealtimeSocketFactory = RealtimeSocket Function(
  Uri uri,
  List<String> protocols,
);

final class ChannelRealtimeSocket implements RealtimeSocket {
  ChannelRealtimeSocket(Uri uri, List<String> protocols)
    : _channel = WebSocketChannel.connect(uri, protocols: protocols);
  final WebSocketChannel _channel;
  @override
  Future<void> get ready => _channel.ready;
  @override
  Stream<Object?> get messages => _channel.stream;
  @override
  void send(String frame) => _channel.sink.add(frame);
  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}
