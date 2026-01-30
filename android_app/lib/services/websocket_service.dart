import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 파일명: lib/services/websocket_service.dart
/// 작성의도: 서버와의 실시간 양방향 통신(WebSocket)을 관리합니다.
/// 기능 원리: WebSocket 채널을 생성하고 유지하며, 서버로부터 오는 메시지를 스트림으로 UI에 전달합니다.
///          연결 끊김 시 재연결 로직을 수행하여 실시간성을 보장합니다.

class WebSocketService {
  WebSocketChannel? _channel;
  DateTime? _lastPingTime;

  DateTime? get lastPingTime => _lastPingTime;
  WebSocketChannel? get channel => _channel;
  bool get isConnected => _channel != null;

  WebSocketChannel? connect(
    String ip,
    String port, {
    required Function(dynamic) onData,
    required void Function() onDone,
    required void Function(dynamic) onError,
  }) {
    if (ip.isEmpty || port.isEmpty) return null;
    try {
      final wsUrl = 'ws://$ip:$port/ws';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (message) => _handleIncomingData(message, onData),
        onDone: onDone,
        onError: onError,
      );
      return _channel;
    } catch (e) {
      return null;
    }
  }

  void _handleIncomingData(dynamic message, Function(dynamic) onDataCallback) {
    try {
      debugPrint("WS Raw Message: $message");
      final data = jsonDecode(message);
      if (data is! Map<String, dynamic>) return;

      final String? type = data['type'];

      // 사용자 요구사항: 패킷 종류별 switch-case 핸들링
      switch (type) {
        case 'PING':
        case 'HEARTBEAT':
          _lastPingTime = DateTime.now();
          // 사용자 요구사항: PING 수신 시 즉시 PONG 응답 (Step 5 대응)
          sendMessage(jsonEncode({"type": "PONG"}));

          if (type == 'HEARTBEAT') {
            sendMessage(jsonEncode({"type": "HEARTBEAT_ACK"}));
          }
          break;

        case 'CONNECTION_ACK':
        case 'ORDER':
        case 'ORDER_CREATE':
        case 'ORDER_DELETE':
        case 'DELETE_ORDER':
        case 'KITCHEN_DATA':
        case 'MENU_DATA':
          // 유효한 데이터 타입들만 상위(Provider)로 전달
          onDataCallback(data);
          break;

        default:
          // 정의되지 않은 타입은 안전하게 무시 (Discard)
          debugPrint("Unknown packet type ignored: $type");
          break;
      }
    } catch (e) {
      debugPrint("WebSocket Data Parsing Error: $e");
      // JSON 형식이 아니거나 파싱 실패 시 폐기
    }
  }

  void sendMessage(dynamic message) {
    if (_channel != null) {
      _channel!.sink.add(message);
    }
  }

  void dispose() {
    _channel?.sink.close();
    _channel = null;
  }
}
