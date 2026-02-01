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
import 'package:path/path.dart' as p;
import '../models/menu_model.dart';
import '../models/order_model.dart';

class ServerService {
  HttpServer? _server;
  Process? _snifferProcess;
  final Set<WebSocketChannel> _wsChannels = {};

  // 실행 파일 기준 경로 계산
  String get _executableDir => p.dirname(Platform.resolvedExecutable);

  String get _pythonPath {
    if (Platform.isWindows) {
      // Platform.resolvedExecutable (Release exe) 기준 python_assets/python/python.exe 사용
      final embedPath = p.join(
        _executableDir,
        'python_assets',
        'python',
        'python.exe',
      );
      if (File(embedPath).existsSync()) return p.normalize(embedPath);

      // 개발 환경에서의 Fallback (프로젝트 루트의 python_runtime 폴더)
      for (int i = 3; i <= 7; i++) {
        final segments = List.filled(i, '..');
        final devPath = p.normalize(
          p.joinAll([
            _executableDir,
            ...segments,
            'python_runtime',
            'python.exe',
          ]),
        );
        if (File(devPath).existsSync()) return devPath;
      }

      // 기본값
      return 'python_runtime\\python.exe';
    }
    return 'python3';
  }

  String get _scriptPath {
    if (Platform.isWindows) {
      // 1. 배포 환경 (python_assets/main.py)
      final deployPath = p.join(_executableDir, 'python_assets', 'main.py');
      if (File(deployPath).existsSync()) return deployPath;

      // 2. 개발 환경 (python_packetSnip/main.py)
      for (int i = 3; i <= 7; i++) {
        final segments = List.filled(i, '..');
        final devPath = p.normalize(
          p.joinAll([
            _executableDir,
            ...segments,
            'python_packetSnip',
            'main.py',
          ]),
        );
        if (File(devPath).existsSync()) return devPath;
      }

      return 'python_packetSnip\\main.py';
    }
    return 'main.py';
  }

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

        _log("INFO", "/api/kitchen_data 호출 수신 ($clientIp)");

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
      _log("DEBUG", "$ip에게 CONNECTION_ACK 송신 완료");

      _wsChannels.add(channel);
      onClientStatusChanged?.call(ip, true);
      _log("INFO", "신규 웹소켓 연결 성공: $ip (총: ${_wsChannels.length})");

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
              _log("INFO", "주문 삭제 요청 수신: $orderId (From: $ip)");
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
            _log("ERROR", "WS 메시지 처리 에러 ($ip): $e");
          }
        },
        onDone: () {
          _wsChannels.remove(channel);
          onClientStatusChanged?.call(ip, false); // 해제 알림 전달
          final String reason = (channel.closeCode != null)
              ? "정상 종료 (Code: ${channel.closeCode})"
              : "비정상 종료 (Timeout/Network)";
          _log(
            "INFO",
            "웹소켓 해제: $ip | 사유: $reason | 잔여 기기: ${_wsChannels.length}",
          );
        },
        onError: (e) {
          _wsChannels.remove(channel);
          _log("ERROR", "웹소켓 통신 에러 ($ip): $e");
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

            _log(
              "DEBUG",
              "Request: ${request.method} ${request.url.path} (From: $clientIp)",
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
      // 수신된 Raw Body 전체를 [DEBUG] 레벨로 로깅하여 데이터 형식 검증
      onLog?.call("[DEBUG] Raw Sniffer Body Received: $body");

      final data = jsonDecode(body);
      onLog?.call("[INFO] Parsed Sniffer Data Type: ${data['type']}");

      return Response.ok(
        jsonEncode({"status": "success"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e, stack) {
      onLog?.call("[ERROR] 스ни퍼 데이터 처리 에러: $e\nStackTrace: $stack");
      return Response.internalServerError();
    }
  }

  // 내부 로그 헬퍼 추가
  void _log(String level, String message) {
    final timestamp = DateTime.now().toString().substring(0, 19);
    onLog?.call("[$timestamp] [$level] $message");
  }

  Future<void> _startSniffer() async {
    try {
      final adapterGuid = await _findLoopbackAdapter();
      final pythonPath = _pythonPath;
      final scriptPath = _scriptPath;

      // 1. 실행 파일 존재 여부 선제적 확인
      if (!await File(pythonPath).exists()) {
        throw "파이썬 엔진을 찾을 수 없습니다: $pythonPath";
      }

      _log("INFO", "MySQL 스니퍼 실행 시도...");

      // 2. 프로세스 실행 (runInShell: false 권장)
      _snifferProcess = await Process.start(
        pythonPath,
        ['-u', scriptPath, adapterGuid], // -u 옵션 유지
        runInShell: false, // 쉘을 거치지 않고 직접 실행
        workingDirectory: _executableDir, // 작업 디렉토리 명시
      );

      // 3. LineSplitter를 통한 안정적인 로그 수집
      _snifferProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log("STDOUT", line); // 이미 스니퍼에서 형식이 지정되어 있으므로 직접 출력
          });

      _snifferProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _log("STDERR", line); // 스니퍼의 에러 로그 직접 출력
          });

      // 4. 즉각적인 종료 감지
      _snifferProcess!.exitCode.then((code) {
        _log("INFO", "스니퍼 프로세스 종료됨 (Exit Code: $code)");
      });
    } catch (e) {
      _log("ERROR", "스니퍼 실행 실패: $e");
    }
  }

  Future<String> _findLoopbackAdapter() async {
    try {
      // Dart에서 직접 tshark를 호출하여 어댑터 목록을 가져올 수도 있지만,
      // 여기서는 Python venv를 활용해 GUID를 신속하게 확인하는 작은 헬퍼를 실행합니다.
      final pythonPath = _pythonPath;

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
      _log("ERROR", "어댑터 검색 에러: $e");
    }
    return r'\Device\NPF_Loopback'; // Default fallback
  }

  Future<void> stopServer() async {
    onLog?.call("서버 종료 시퀀스 시작...");
    try {
      await stopSniffer();
      await _server?.close(force: true);
      _server = null;
      _wsChannels.clear();
      onLog?.call("서버 및 모든 연결이 성공적으로 종료되었습니다.");
    } catch (e) {
      onLog?.call("서버 종료 중 예외 발생: $e");
    }
  }

  Future<void> stopSniffer() async {
    if (_snifferProcess == null) return;
    final pid = _snifferProcess?.pid;
    onLog?.call("스니퍼 프로세스 종료 시도 (PID: $pid)...");

    try {
      // 1. taskkill을 사용하여 트리 전체(/T)를 강제 종료(/F)
      if (Platform.isWindows && pid != null) {
        final result = await Process.run('taskkill', [
          '/PID',
          '$pid',
          '/T',
          '/F',
        ]);
        onLog?.call("taskkill 실행 완료: ${result.stdout.toString().trim()}");
      } else {
        _snifferProcess?.kill();
      }
    } catch (e) {
      onLog?.call("프로세스 종료 중 에러: $e");
      // 예외가 발생하더라도 강제로 객체를 비워줌
      _snifferProcess?.kill();
    } finally {
      _snifferProcess = null;
      // 2. 리소스 잔류 확인 (지연 후 실행)
      Future.delayed(const Duration(milliseconds: 500), () {
        _checkResidualProcesses();
      });
    }
  }

  Future<void> _checkResidualProcesses() async {
    if (!Platform.isWindows) return;
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq tshark.exe',
      ]);
      final output = result.stdout.toString();
      if (output.contains('tshark.exe')) {
        onLog?.call("[주의] tshark.exe가 아직 종료되지 않고 잔류 중입니다.");
      } else {
        onLog?.call("[검증] 모든 하위 프로세스(tshark.exe)가 정상 소멸되었습니다.");
      }

      final pyResult = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq python.exe',
      ]);
      final pyOutput = pyResult.stdout.toString();
      if (pyOutput.contains('python.exe')) {
        _log("WARNING", "python.exe가 아직 종료되지 않았습니다.");
      }
    } catch (e) {
      _log("ERROR", "리소스 모니터링 중 에러: $e");
    }
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
