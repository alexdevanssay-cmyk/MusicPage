// lib/services/websocket_service.dart
// ─────────────────────────────────────
// Thin wrapper around web_socket_channel.
// Decodes incoming JSON text frames and exposes them as a broadcast stream.
// Binary send is used for raw PCM audio chunks.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

class WsService {
  WsService({required this.wsUrl});

  final String wsUrl;

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _channel != null;

  // ── Streams ───────────────────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get messages => _controller.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  Future<void> connect() async {
    final uri = Uri.parse(wsUrl);
    _channel = WebSocketChannel.connect(uri);

    // Wait for the handshake to complete
    await _channel!.ready.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('WebSocket connect timeout'),
    );

    _channel!.stream.listen(
      (data) {
        if (data is String) {
          try {
            final decoded = jsonDecode(data) as Map<String, dynamic>;
            _controller.add(decoded);
          } catch (_) {
            // Ignore malformed frames
          }
        }
        // Binary frames are responses to our audio – ignore (we don't expect them)
      },
      onError: (error) => _controller.addError(error),
      onDone: () {
        _channel = null;
      },
    );
  }

  void disconnect() {
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
  }

  // ── Sending ───────────────────────────────────────────────────────────────────

  Future<void> send(Map<String, dynamic> message) async {
    if (!isConnected) return;
    _channel!.sink.add(jsonEncode(message));
  }

  void sendBinary(Uint8List bytes) {
    if (!isConnected) return;
    _channel!.sink.add(bytes);
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
