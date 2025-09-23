import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef OnMessage = void Function(Map<String, dynamic>);

class WsService {
  final String url;
  WebSocketChannel? _ch;

  WsService(this.url);

  void connect(OnMessage onMessage, {void Function()? onDone, void Function(Object e)? onError}) {
    _ch = WebSocketChannel.connect(Uri.parse(url));
    _ch!.stream.listen((event) {
      try {
        final map = json.decode(event) as Map<String, dynamic>;
        onMessage(map);
      } catch (_) {}
    }, onDone: onDone, onError: onError);
  }

  void send(String text) => _ch?.sink.add(text);

  void dispose() {
    _ch?.sink.close();
    _ch = null;
  }
}
