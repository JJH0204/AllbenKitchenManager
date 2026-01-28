import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'settings_page.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models/device_info.dart';

void main() => runApp(const AdminApp());

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'), // 폰트 설정 (필요시)
      home: const AdminServerPage(),
    );
  }
}

// 메뉴 데이터 모델
class MenuData {
  String id;
  String name;
  String cat;
  int time;
  String recipe;
  String image; // 파일명 또는 URL

  MenuData({
    required this.id,
    required this.name,
    this.cat = "분류 없음",
    this.time = 0,
    this.recipe = "",
    this.image = "",
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "cat": cat,
    "time": time,
    "recipe": recipe,
    "image": image,
  };

  factory MenuData.fromJson(Map<String, dynamic> json) => MenuData(
    id: json["id"] ?? "",
    name: json["name"] ?? "",
    cat: json["cat"] ?? "분류 없음",
    time: json["time"] ?? 0,
    recipe: json["recipe"] ?? "",
    image: json["image"] ?? "",
  );
}

class AdminServerPage extends StatefulWidget {
  const AdminServerPage({super.key});

  @override
  State<AdminServerPage> createState() => _AdminServerPageState();
}

class _AdminServerPageState extends State<AdminServerPage> {
  String activeTab = "menu";
  bool isServerOn = false;
  HttpServer? _server;
  String? statusMessage;
  int? currentPort;
  final List<String> _logs = [];

  // 실시간 연결 기기 및 펜딩 주문 관리
  final Map<String, DeviceInfo> _connectedClientsMap = {};
  final List<Map<String, dynamic>> _pendingOrders = [];
  final Set<WebSocketChannel> _wsChannels = {};

  // 서버 메모리용 Mock 데이터
  final Map<String, dynamic> mockData = {
    "categories": [],
    "menus": [],
    "orders": [],
  };

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      final timeStr =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      _logs.add("[$timeStr] $message");
      if (_logs.length > 100) _logs.removeAt(0); // 최대 100개 유지
    });
  }

  @override
  void initState() {
    super.initState();
    _loadMenusFromFile();
  }

  Future<void> startServer(int port) async {
    if (_server != null) return;

    final dataDir = await _dataDir;
    final imagesDir = Directory(p.join(dataDir.path, 'images'));

    // 정적 파일 핸들러 (이미지 서빙)
    final staticHandler = createStaticHandler(
      imagesDir.path,
      defaultDocument: 'index.html',
    );

    final apiHandler = (Request request) {
      if (request.url.path == 'api/kitchen_data') {
        final connInfo =
            request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        final clientIp = connInfo?.remoteAddress.address ?? "Unknown";

        // API 요청 시 온라인 상태 및 Last Seen 갱신
        if (clientIp != "Unknown" && clientIp != "127.0.0.1") {
          setState(() {
            if (_connectedClientsMap.containsKey(clientIp)) {
              _connectedClientsMap[clientIp] = _connectedClientsMap[clientIp]!
                  .copyWith(isOnline: true, lastSeen: DateTime.now());
            } else {
              _connectedClientsMap[clientIp] = DeviceInfo(
                id: "D-${clientIp.split('.').last}",
                name: "KDS-Remote",
                ip: clientIp,
                lastSeen: DateTime.now(),
                isOnline: true,
              );
            }
          });
        }

        _addLog("[API 호출] /api/kitchen_data ($clientIp)");

        // 요청 헤더의 host를 사용하여 클라이언트가 접근 가능한 Full URL 생성
        final host = request.headers['host'] ?? "localhost:8080";
        final baseUrl = "http://$host/images";

        final mappedMenus = menus.map((m) {
          final json = m.toJson();
          if (m.image.isNotEmpty && !m.image.startsWith('http')) {
            json['image'] = "$baseUrl/${m.image}";
          }
          return json;
        }).toList();

        final Set<String> categories = menus.map((e) => e.cat).toSet();

        final responseData = {
          "categories": categories.toList(),
          "menus": mappedMenus,
          "orders": mockData["orders"],
          "pendingOrders": _pendingOrders,
        };

        return Response.ok(
          jsonEncode(responseData),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
      return Response.notFound('Not Found');
    };

    // 웹소켓 핸들러 정의 (IP 매핑을 위해 함수화)
    Function(WebSocketChannel, String) handleWsConnection =
        (WebSocketChannel channel, String ip) {
          _wsChannels.add(channel);

          setState(() {
            if (_connectedClientsMap.containsKey(ip)) {
              _connectedClientsMap[ip] = _connectedClientsMap[ip]!.copyWith(
                isOnline: true,
                lastSeen: DateTime.now(),
              );
            } else {
              _connectedClientsMap[ip] = DeviceInfo(
                id: "D-${ip.split('.').last}",
                name: "KDS-Remote",
                ip: ip,
                lastSeen: DateTime.now(),
                isOnline: true,
              );
            }
          });

          _addLog("신규 웹소켓 연결: $ip (총: ${_wsChannels.length})");

          channel.stream.listen(
            (message) {
              try {
                final data = jsonDecode(message);
                if (data['type'] == 'DELETE_ORDER') {
                  final String orderId = data['orderId'];
                  _addLog("[WS 요청] 주문 삭제 요청 수신: $orderId");

                  // 1. 서버 메모리에서 제거
                  setState(() {
                    mockData["orders"].removeWhere(
                      (o) => o['orderId'] == orderId,
                    );
                    _pendingOrders.removeWhere((o) => o['orderId'] == orderId);
                  });

                  // 2. 다른 모든 클라이언트에 브로드캐스트
                  final broadcastMsg = jsonEncode({
                    "type": "DELETE_ORDER",
                    "orderId": orderId,
                  });
                  for (var otherChannel in _wsChannels) {
                    // 요청을 보낸 본인에게는 생략할 수 있지만, 정합성을 위해 전체 전송
                    try {
                      otherChannel.sink.add(broadcastMsg);
                    } catch (e) {
                      debugPrint("Broadcast error: $e");
                    }
                  }
                  _addLog("[WS 브로드캐스트] 주문 삭제 전파 완료: $orderId");
                }
              } catch (e) {
                _addLog("WS 메시지 처리 에러: $e");
              }
            },
            onDone: () {
              _wsChannels.remove(channel);
              setState(() {
                if (_connectedClientsMap.containsKey(ip)) {
                  _connectedClientsMap[ip] = _connectedClientsMap[ip]!.copyWith(
                    isOnline: false,
                    lastSeen: DateTime.now(),
                  );
                }
              });
              _addLog("웹소켓 해제: $ip (남은 클라이언트: ${_wsChannels.length})");
            },
            onError: (e) {
              _wsChannels.remove(channel);
              _addLog("웹소켓 에러 ($ip): $e");
            },
          );
        };

    final handler = const Pipeline()
        .addMiddleware((innerHandler) {
          return (Request request) async {
            final connInfo =
                request.context['shelf.io.connection_info']
                    as HttpConnectionInfo?;
            final clientIp = connInfo?.remoteAddress.address ?? "Unknown";

            // 기기 트래킹 업데이트 (미들웨어)
            if (clientIp != "Unknown" && clientIp != "127.0.0.1") {
              setState(() {
                if (_connectedClientsMap.containsKey(clientIp)) {
                  // 기존 정보 유지하며 시간만 업데이트
                  _connectedClientsMap[clientIp] =
                      _connectedClientsMap[clientIp]!.copyWith(
                        lastSeen: DateTime.now(),
                      );
                } else {
                  _connectedClientsMap[clientIp] = DeviceInfo(
                    id: "D-${clientIp.split('.').last}",
                    name: "KDS-Remote",
                    ip: clientIp,
                    lastSeen: DateTime.now(),
                    isOnline: false, // 미들웨어 단계에선 기본 오프라인 (WS/API에서 Online 전환)
                  );
                }
              });
            }

            _addLog(
              "접속 요청 수신: $clientIp | ${request.method} | ${request.url.path}",
            );
            return await innerHandler(request);
          };
        })
        .addHandler(
          Cascade()
              .add((Request request) {
                // 웹소켓 경로 처리
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
                // 이미지 경로 처리
                if (request.url.path.startsWith('images/')) {
                  final subRequest = request.change(path: 'images');
                  return staticHandler(subRequest);
                }
                return Response.notFound('Not Found');
              })
              .add(apiHandler)
              .handler,
        );

    try {
      _server = await shelf_io.serve(handler, '0.0.0.0', port);
      setState(() {
        isServerOn = true;
        currentPort = port;
        statusMessage = "서버 정상 동작 중 (Port: $port)";
      });
      print('Serving at http://${_server!.address.host}:${_server!.port}');
      _addLog("서버가 시작되었습니다. (Port: $port, Binding: 0.0.0.0)");
    } on SocketException catch (e) {
      _server = null;
      _showErrorDialog(
        "서버 실행 실패",
        "해당 포트($port)는 이미 사용 중이거나 권한이 없습니다.\n(상세: ${e.message})",
      );
    } catch (e) {
      _server = null;
      _showErrorDialog("알 수 없는 오류", "서버를 시작하는 중 오류가 발생했습니다: $e");
      _addLog("에러 발생: $e");
    }
  }

  Future<void> stopServer() async {
    if (_server == null) return;

    await _server?.close(force: true);
    setState(() {
      _server = null;
      isServerOn = false;
      currentPort = null;
      statusMessage = "서버가 중지되었습니다.";
    });
    _addLog("서버가 종료되었습니다.");
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  // 리액트의 useState 부분: 초기 데이터 세팅
  List<MenuData> menus = [];

  Future<Directory> get _dataDir async {
    final appDir = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(appDir.path, 'data'));
    if (!await dataDir.exists()) await dataDir.create();
    final imagesDir = Directory(p.join(dataDir.path, 'images'));
    if (!await imagesDir.exists()) await imagesDir.create();
    return dataDir;
  }

  Future<void> _loadMenusFromFile() async {
    try {
      final dir = await _dataDir;
      final file = File(p.join(dir.path, 'menus.json'));
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        setState(() {
          menus = jsonList.map((e) => MenuData.fromJson(e)).toList();
        });
        _addLog("파일에서 메뉴 ${menus.length}개를 로드했습니다.");
      } else {
        // 초기 더미 데이터 생성
        menus = [
          MenuData(
            id: "M001",
            name: "아메리카노",
            cat: "커피",
            time: 30,
            recipe: "1. 샷을 추출한다...",
          ),
          MenuData(
            id: "M002",
            name: "카페라떼",
            cat: "커피",
            time: 45,
            recipe: "1. 우유를 스팀한다...",
          ),
        ];
        await _saveMenusToFile();
        _addLog("기본 메뉴 데이터를 생성했습니다.");
      }
    } catch (e) {
      _addLog("데이터 로드 실패: $e");
    }
  }

  Future<void> _saveMenusToFile() async {
    try {
      final dir = await _dataDir;
      final file = File(p.join(dir.path, 'menus.json'));
      final content = jsonEncode(menus.map((e) => e.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      _addLog("데이터 저장 실패: $e");
    }
  }

  Future<void> _pickImage(MenuData menu) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      try {
        final dataDir = await _dataDir;
        final imagesDir = Directory(p.join(dataDir.path, 'images'));
        if (!await imagesDir.exists()) await imagesDir.create();

        final fileName = p.basename(image.path);
        final newImagePath = p.join(imagesDir.path, fileName);
        await File(image.path).copy(newImagePath);

        setState(() {
          menu.image = fileName;
        });
        await _saveMenusToFile();
        _addLog("메뉴 '${menu.name}'의 이미지를 '$fileName'으로 업데이트했습니다.");
      } catch (e) {
        _addLog("이미지 저장 실패: $e");
      }
    }
  }

  Future<void> _addMenu() async {
    final newId = "M${(menus.length + 1).toString().padLeft(3, '0')}";
    final newMenu = MenuData(
      id: newId,
      name: "새 메뉴",
      cat: "기타",
      time: 0,
      recipe: "",
      image: "",
    );

    _openEditModal(newMenu, isNew: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      body: Row(
        children: [
          // 1. AdminSidebar
          _buildSidebar(),

          // 2. Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 32),
                  Expanded(child: _buildActiveContent()),
                  _buildStatusBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 위젯 분리: 사이드바 ---
  Widget _buildSidebar() {
    return Container(
      width: 260,
      color: const Color(0xFF1A1F2E),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "ADMIN CONSOLE",
            style: TextStyle(
              color: Colors.blueAccent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            "SERVER V2.0",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 40),
          _sidebarButton("dashboard", "📊", "대시보드"),
          _sidebarButton("menu", "🍔", "메뉴 데이터 관리"),
          _sidebarButton("orders", "📜", "누적 주문 내역"),
          _sidebarButton("settings", "⚙️", "서버 설정"),
          const Spacer(),
          _buildServerStatusCard(),
        ],
      ),
    );
  }

  Widget _sidebarButton(String id, String icon, String label) {
    bool isActive = activeTab == id;
    return InkWell(
      onTap: () => setState(() => activeTab = id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(icon),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.blueGrey,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Server Status",
                style: TextStyle(color: Colors.grey, fontSize: 10),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isServerOn ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isServerOn ? "RUNNING: 8080" : "STOPPED",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // --- 위젯 분리: 헤더 ---
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activeTab == "dashboard" ? "SERVER DASHBOARD" : "DATA MANAGEMENT",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            Text(
              isServerOn
                  ? "Host: 0.0.0.0:$currentPort | Active"
                  : "Server Offline | Last Sync: 2026-01-28",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        ElevatedButton(
          onPressed: () async {
            if (isServerOn) {
              await stopServer();
            } else {
              final prefs = await SharedPreferences.getInstance();
              final portStr = prefs.getString('server_port') ?? "8080";
              final port = int.tryParse(portStr) ?? 8080;
              await startServer(port);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isServerOn ? Colors.red : Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            isServerOn ? "SERVER STOP" : "SERVER START",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  // --- 위젯 분리: 메뉴 테이블 ---
  Widget _buildMenuTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "메뉴 데이터베이스 편집",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _loadMenusFromFile,
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text("데이터 동기화"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade50,
                        foregroundColor: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _addMenu(),
                      child: const Text("+ 새 메뉴 추가"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                DataTable(
                  columns: const [
                    DataColumn(label: Text("Image")),
                    DataColumn(label: Text("메뉴명")),
                    DataColumn(label: Text("카테고리")),
                    DataColumn(label: Text("조리시간")),
                    DataColumn(label: Text("관리")),
                  ],
                  rows: menus
                      .map(
                        (m) => DataRow(
                          cells: [
                            DataCell(
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: m.image.isEmpty
                                    ? const Icon(
                                        Icons.image,
                                        color: Colors.grey,
                                        size: 20,
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          "http://localhost:${currentPort ?? 8080}/images/${m.image}",
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => const Icon(
                                            Icons.broken_image,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            DataCell(
                              Text(
                                m.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(Text(m.cat)),
                            DataCell(
                              Text(
                                "${m.time}s",
                                style: const TextStyle(
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () => _openEditModal(m),
                                    child: const Text("수정"),
                                  ),
                                  TextButton(
                                    onPressed: () {},
                                    child: const Text(
                                      "삭제",
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveContent() {
    switch (activeTab) {
      case "menu":
        return _buildMenuTable();
      case "orders":
        return _buildOrdersTable();
      case "settings":
        return SettingsPage(
          isServerOn: isServerOn,
          logs: _logs,
          connectedDevices: _connectedClientsMap.values.toList(),
          onToggleServer: (bool start, int port) async {
            if (start) {
              await startServer(port);
            } else {
              await stopServer();
            }
          },
        );
      default:
        return _buildDashboardPlaceholder();
    }
  }

  Widget _buildStatusBar() {
    if (statusMessage == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isServerOn
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isServerOn
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isServerOn ? Icons.check_circle : Icons.error_outline,
            color: isServerOn ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            statusMessage!,
            style: TextStyle(
              color: isServerOn ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTable() {
    final List<dynamic> orders = mockData["orders"];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "누적 주문 내역",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                ElevatedButton.icon(
                  onPressed: _generateRandomOrder,
                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                  label: const Text("테스트 주문 생성"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                  title: Text(
                    "ID: ${order['orderId']} | Table: ${order['table']}",
                  ),
                  subtitle: Text("Items: ${order['items'].join(', ')}"),
                  trailing: Text(
                    order['time'],
                    style: const TextStyle(color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _generateRandomOrder() {
    if (menus.isEmpty) {
      _addLog("주문을 생성할 메뉴가 없습니다.");
      return;
    }

    final random = DateTime.now().millisecond % menus.length;
    final selectedMenu = menus[random];
    final orderId =
        "ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    final newOrder = {
      "orderId": orderId,
      "table": (1 + (now.second % 10)).toString().padLeft(3, '0'),
      "items": [selectedMenu.name],
      "status": "cooking",
      "time": timeStr,
    };

    setState(() {
      // 누적 주문 리스트 업데이트
      mockData["orders"].insert(0, newOrder);
      // 안드로이드 폴링용 펜딩 리스트에 추가
      _pendingOrders.add(newOrder);
    });

    // 웹소켓 브로드캐스트 (실시간 전송)
    final orderJson = jsonEncode(newOrder);
    for (var channel in _wsChannels) {
      try {
        channel.sink.add(orderJson);
      } catch (e) {
        _addLog("브로드캐스트 실패: $e");
      }
    }

    _addLog("[테스트 주문] '${selectedMenu.name}' 주문 생성 및 클라이언트 브로드캐스트 완료");
  }

  Widget _buildDashboardPlaceholder() {
    return const Center(
      child: Text(
        "📊 대시보드 통계 데이터 로딩 중...",
        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
      ),
    );
  }

  // --- 이벤트: 수정 모달 열기 ---
  void _openEditModal(MenuData menu, {bool isNew = false}) async {
    final dir = await _dataDir;
    final imagesDir = Directory(p.join(dir.path, 'images'));

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => _MenuDetailEditor(
        menu: menu,
        imagesDirPath: imagesDir.path,
        currentPort: currentPort ?? 8080,
        onPickImage: () async {
          await _pickImage(menu);
          // Rebuild the dialog to show the new image
          (context as Element).markNeedsBuild();
        },
        onSave: (updated) {
          setState(() {
            if (isNew) {
              menus.add(updated);
            } else {
              int index = menus.indexWhere((element) => element.id == menu.id);
              if (index != -1) menus[index] = updated;
            }
          });
          _saveMenusToFile();
          Navigator.pop(context);
        },
      ),
    );
  }
}

// --- 별도 위젯: 메뉴 상세 편집기 (모달) ---
class _MenuDetailEditor extends StatefulWidget {
  final MenuData menu;
  final String imagesDirPath;
  final int currentPort;
  final VoidCallback onPickImage;
  final Function(MenuData) onSave;

  const _MenuDetailEditor({
    required this.menu,
    required this.imagesDirPath,
    required this.currentPort,
    required this.onPickImage,
    required this.onSave,
  });

  @override
  State<_MenuDetailEditor> createState() => _MenuDetailEditorState();
}

class _MenuDetailEditorState extends State<_MenuDetailEditor> {
  late TextEditingController nameController;
  late TextEditingController timeController;
  late TextEditingController recipeController;
  late String selectedCat;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.menu.name);
    timeController = TextEditingController(text: widget.menu.time.toString());
    recipeController = TextEditingController(text: widget.menu.recipe);
    selectedCat = widget.menu.cat;
  }

  @override
  void dispose() {
    nameController.dispose();
    timeController.dispose();
    recipeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: 500,
        height: double.infinity,
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "메뉴 상세 편집",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: widget.menu.image.isEmpty
                                ? const Icon(
                                    Icons.image_outlined,
                                    size: 40,
                                    color: Colors.grey,
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(
                                      "http://localhost:${widget.currentPort}/images/${widget.menu.image}",
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(
                                                Icons.broken_image,
                                                color: Colors.red,
                                              ),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () async {
                              widget.onPickImage();
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text("이미지 선택/변경"),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildField("Menu Name", nameController),
                    const SizedBox(height: 20),
                    _buildField(
                      "Cook Time (Sec)",
                      timeController,
                      isNumber: true,
                    ),
                    const SizedBox(height: 20),
                    _buildField(
                      "Recipe Description",
                      recipeController,
                      isLong: true,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("취소"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onSave(
                        MenuData(
                          id: widget.menu.id,
                          name: nameController.text,
                          cat: selectedCat,
                          time: int.tryParse(timeController.text) ?? 0,
                          recipe: recipeController.text,
                          image: widget.menu.image,
                        ),
                      );
                    },
                    child: const Text("저장하기"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    bool isLong = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: isLong ? 6 : 1,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
