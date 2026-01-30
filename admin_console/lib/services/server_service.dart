/**
 * 작성의도: Shelf 라이브러리를 이용한 로컬 서버 및 웹소켓 통신을 담당하는 서비스 파일입니다.
 * 기능 원리: HTTP API 핸들러, 웹소켓 브로드캐스팅, 정적 파일(이미지) 서빙 로직을 포함하며 서버의 생명주기를 관리합니다.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/menu_model.dart';
import '../models/order_model.dart';

class ServerService {
  HttpServer? _server;
  Process? _snifferProcess;
  final Set<WebSocketChannel> _wsChannels = {};

  // 콜백 함수들
  void Function(String ip, bool isConnected)? onClientStatusChanged;
  void Function(String orderId)? onDeleteOrderRequested;
  void Function(String log)? onLog;

  Future<HttpServer> startServer({
    required int port,
    required String imagesPath,
    required List<MenuModel> Function() getMenus,
    required List<OrderModel> Function() getPendingOrders,
    required List<OrderModel> Function() getMockOrders,
  }) async {
    final staticHandler = createStaticHandler(
      imagesPath,
      defaultDocument: 'index.html',
    );

    FutureOr<Response> apiHandler(Request request) async {
      if (request.url.path == 'api/kitchen_data') {
        final connInfo =
            request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        final clientIp = connInfo?.remoteAddress.address ?? "Unknown";

        if (clientIp != "Unknown" && clientIp != "127.0.0.1") {
          onClientStatusChanged?.call(clientIp, true);
        }

        onLog?.call("[API 호출] /api/kitchen_data ($clientIp)");

        final host = request.headers['host'] ?? "localhost:$port";
        final baseUrl = "http://$host/images";

        final mappedMenus = getMenus().map((m) {
          final json = m.toJson();
          if (m.image.isNotEmpty && !m.image.startsWith('http')) {
            json['image'] = "$baseUrl/${m.image}";
          }
          return json;
        }).toList();

        final Set<String> categories = getMenus().map((e) => e.cat).toSet();

        final responseData = {
          "categories": categories.toList(),
          "menus": mappedMenus,
          "orders": getMockOrders().map((o) => o.toJson()).toList(),
          "pendingOrders": getPendingOrders().map((o) => o.toJson()).toList(),
        };

        return Response.ok(
          jsonEncode(responseData),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
      if (request.url.path == 'api/external_order') {
        return _handleSniffedData(request);
      }
      return Response.notFound('Not Found');
    }

    void handleWsConnection(WebSocketChannel channel, String ip) {
      // 1. 즉각적인 응답 (Handshake ACK) - 지연 방지를 위해 최상단에 배치
      final ack = {
        "type": "CONNECTION_ACK",
        "payload": {
          "status": "success",
          "message": "Welcome to Kitchen Server",
          "timestamp": DateTime.now().toIso8601String(),
        },
      };

      final ackJson = jsonEncode(ack);
      channel.sink.add(ackJson);
      onLog?.call("[WS 발송] $ip에게 CONNECTION_ACK 송신 완료");

      _wsChannels.add(channel);
      onClientStatusChanged?.call(ip, true);
      onLog?.call("신규 웹소켓 연결 성공: $ip (총: ${_wsChannels.length})");

      channel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['type'] == 'PONG') {
              // PONG 수신 시 Last Seen 갱신을 위해 콜백 호출
              onClientStatusChanged?.call(ip, true);
            }
            if (data['type'] == 'ORDER_DELETE' ||
                data['type'] == 'DELETE_ORDER') {
              final String orderId =
                  data['orderId'] ?? data['data'] ?? data['payload'];
              onLog?.call("[WS 요청] 주문 삭제 요청 수신: $orderId");
              onDeleteOrderRequested?.call(orderId);

              broadcast(
                jsonEncode({"type": "ORDER_DELETE", "payload": orderId}),
              );
            }
            if (data['type'] == 'GET_ORDERS') {
              // 서버가 보유한 대기 주문(Pending Orders)을 정규화된 패킷으로 응답
              final response = {
                "type": "ORDER_LIST", // 또는 기존에 약속한 타입
                "payload": getPendingOrders().map((o) => o.toJson()).toList(),
              };
              channel.sink.add(jsonEncode(response));
            }
          } catch (e) {
            onLog?.call("WS 메시지 처리 에러 ($ip): $e");
          }
        },
        onDone: () {
          _wsChannels.remove(channel);
          onClientStatusChanged?.call(ip, false); // 해제 알림 전달
          final String reason = (channel.closeCode != null)
              ? "정상 종료 (Code: ${channel.closeCode})"
              : "비정상 종료 (Timeout/Network)";
          onLog?.call(
            "웹소켓 해제: $ip | 사유: $reason | 잔여 기기: ${_wsChannels.length}",
          );
        },
        onError: (e) {
          _wsChannels.remove(channel);
          onLog?.call("웹소켓 통신 에러 ($ip): $e | 연결이 강제 종료됨");
        },
      );
    }

    final handler = const Pipeline()
        .addMiddleware((innerHandler) {
          return (Request request) async {
            final connInfo =
                request.context['shelf.io.connection_info']
                    as HttpConnectionInfo?;
            final clientIp = connInfo?.remoteAddress.address ?? "Unknown";

            if (clientIp != "Unknown" && clientIp != "127.0.0.1") {
              onClientStatusChanged?.call(clientIp, true);
            }

            onLog?.call(
              "접속 요청 수신: $clientIp | ${request.method} | ${request.url.path}",
            );
            return await innerHandler(request);
          };
        })
        .addHandler(
          Cascade()
              .add((Request request) {
                if (request.url.path == 'ws') {
                  final connInfo =
                      request.context['shelf.io.connection_info']
                          as HttpConnectionInfo?;
                  final clientIp = connInfo?.remoteAddress.address ?? "Unknown";
                  return webSocketHandler((
                    WebSocketChannel channel,
                    String? protocol,
                  ) {
                    handleWsConnection(channel, clientIp);
                  })(request);
                }
                if (request.url.path.startsWith('images/')) {
                  final subRequest = request.change(path: 'images');
                  return staticHandler(subRequest);
                }
                return Response.notFound('Not Found');
              })
              .add(apiHandler)
              .handler,
        );

    _server = await shelf_io.serve(handler, '0.0.0.0', port);

    // MySQL 스니퍼 자동 실행
    _startSniffer();

    return _server!;
  }

  Future<Response> _handleSniffedData(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);
      onLog?.call("[스니퍼 데이터 수신] ${data['type']}");

      // 여기서 추가적인 주문 처리 로직(DB 저장 등)을 수행할 수 있습니다.
      // 현재는 로그 출력으로 검증

      return Response.ok(
        jsonEncode({"status": "success"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      onLog?.call("스니퍼 데이터 처리 에러: $e");
      return Response.internalServerError();
    }
  }

  Future<void> _startSniffer() async {
    try {
      final adapterGuid = await _findLoopbackAdapter();
      final pythonPath = Platform.isWindows
          ? '..\\python_packetSnip\\venv\\Scripts\\python.exe'
          : 'python3';
      final scriptPath = '..\\python_packetSnip\\main.py';

      onLog?.call("MySQL 스니퍼 실행 시도: $adapterGuid");

      _snifferProcess = await Process.start(pythonPath, [
        scriptPath,
        adapterGuid,
      ], runInShell: true);

      _snifferProcess!.stdout.transform(utf8.decoder).listen((data) {
        onLog?.call("[Sniffer STDOUT] ${data.trim()}");
      });

      _snifferProcess!.stderr.transform(utf8.decoder).listen((data) {
        onLog?.call("[Sniffer STDERR] ${data.trim()}");
      });

      _snifferProcess!.exitCode.then((code) {
        onLog?.call("MySQL 스니퍼 프로세스 종료 (Exit Code: $code)");
        _snifferProcess = null;
      });
    } catch (e) {
      onLog?.call("MySQL 스니퍼 실행 실패: $e");
    }
  }

  Future<String> _findLoopbackAdapter() async {
    try {
      // Dart에서 직접 tshark를 호출하여 어댑터 목록을 가져올 수도 있지만,
      // 여기서는 Python venv를 활용해 GUID를 신속하게 확인하는 작은 헬퍼를 실행합니다.
      final pythonPath = Platform.isWindows
          ? '..\\python_packetSnip\\venv\\Scripts\\python.exe'
          : 'python3';

      final result = await Process.run(pythonPath, [
        '-c',
        'import pyshark; print(pyshark.tshark.tshark.get_tshark_interfaces())',
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        // 간단한 파싱: NPF_Loopback 우선, 없으면 첫 번째 리턴
        if (output.contains('NPF_Loopback')) return r'\Device\NPF_Loopback';

        final match = RegExp(
          r"(\\Device\\NPF_{[A-F0-9-]+})",
        ).firstMatch(output);
        if (match != null) return match.group(1)!;
      }
    } catch (e) {
      onLog?.call("어댑터 검색 에러: $e");
    }
    return r'\Device\NPF_Loopback'; // Default fallback
  }

  Future<void> stopServer() async {
    _snifferProcess?.kill();
    _snifferProcess = null;
    await _server?.close(force: true);
    _server = null;
    _wsChannels.clear();
  }

  void broadcast(String message) {
    for (var channel in _wsChannels) {
      try {
        channel.sink.add(message);
      } catch (e) {
        // ignore
      }
    }
  }

  bool get isRunning => _server != null;
  int? get port => _server?.port;
}
