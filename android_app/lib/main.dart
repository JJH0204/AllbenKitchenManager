import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const KitchenAndroidApp());

class KitchenAndroidApp extends StatelessWidget {
  const KitchenAndroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: const BaseLayout(),
    );
  }
}

// --- 한글 초성 추출 유틸리티 ---
String getChosung(String str) {
  const cho = [
    "ㄱ",
    "ㄲ",
    "ㄴ",
    "ㄷ",
    "ㄸ",
    "ㄹ",
    "ㅁ",
    "ㅂ",
    "ㅃ",
    "ㅅ",
    "ㅆ",
    "ㅇ",
    "ㅈ",
    "ㅉ",
    "ㅊ",
    "ㅋ",
    "ㅌ",
    "ㅍ",
    "ㅎ",
  ];
  String result = "";
  for (int i = 0; i < str.length; i++) {
    int code = str.codeUnitAt(i) - 44032;
    if (code >= 0 && code <= 11172) {
      result += cho[(code / 588).floor()];
    } else {
      result += str[i];
    }
  }
  return result;
}

// --- 데이터 모델 ---
class MenuInfo {
  final String name, cat, recipe, imageUrl;
  final int time;
  MenuInfo({
    required this.name,
    required this.cat,
    required this.time,
    required this.recipe,
    this.imageUrl = "",
  });
}

class OrderInfo {
  final String id, tableNo, time;
  final List<String> menus;
  OrderInfo({
    required this.id,
    required this.tableNo,
    required this.menus,
    required this.time,
  });
}

// --- 메인 레이아웃 ---
class BaseLayout extends StatefulWidget {
  const BaseLayout({super.key});

  @override
  State<BaseLayout> createState() => _BaseLayoutState();
}

class _BaseLayoutState extends State<BaseLayout> {
  String selectedCategory = "전체";
  String searchTerm = "";
  String filterMode = "CATEGORY"; // "CATEGORY" or "ORDER"
  List<String> activeOrderMenus = [];
  String activeTableNo = "";

  List<String> categories = [];
  List<MenuInfo> allMenus = [];
  List<OrderInfo> orders = [];
  bool isLoading = true;
  int unreadOrdersCount = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  // 서버 설정 관련 변수
  String serverIp = "";
  String serverPort = "";
  String? connectionStatus; // null, "testing", "success", "error"
  String? errorMessage;
  bool isSyncing = false;

  Future<File> _getLocalFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/kitchen_data_cache.json');
  }

  Future<void> _saveToLocal(String jsonString) async {
    final file = await _getLocalFile();
    await file.writeAsString(jsonString);
  }

  Future<bool> _loadFromLocal() async {
    try {
      final file = await _getLocalFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final data = jsonDecode(contents);
        _parseAndSetData(data);
        return true;
      }
    } catch (e) {
      debugPrint("Local load error: $e");
    }
    return false;
  }

  List<MenuInfo> get filteredMenus {
    Iterable<MenuInfo> temp = allMenus;
    if (searchTerm.isNotEmpty) {
      String lowerSearch = searchTerm.toLowerCase();
      String searchCho = getChosung(lowerSearch);
      temp = temp.where(
        (m) =>
            m.name.toLowerCase().contains(lowerSearch) ||
            getChosung(m.name).contains(searchCho),
      );
    }
    if (filterMode == "ORDER") {
      temp = temp.where((m) => activeOrderMenus.contains(m.name));
    } else if (selectedCategory != "전체") {
      temp = temp.where((m) => m.cat == selectedCategory);
    }
    return temp.toList();
  }

  Timer? _pollingTimer;
  WebSocketChannel? _wsChannel;
  bool _isWsConnecting = false;

  @override
  void initState() {
    super.initState();
    _initApp();

    // 30초마다 자동 새로고침 (숏폴링)
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (serverIp.isNotEmpty && serverPort.isNotEmpty && !isSyncing) {
        loadData();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initApp() async {
    await _loadStoredSettings();

    // 1. 로컬 캐시 먼저 시도 (즉시 표시)
    bool hasLocalData = await _loadFromLocal();

    // 2. 서버에서 최신 데이터 가져오기 (비동기)
    if (serverIp.isNotEmpty && serverPort.isNotEmpty) {
      await loadData();
    } else if (!hasLocalData) {
      // 3. 로컬도 서버도 없으면 기본 Mock
      await loadJsonData();
    }
  }

  Future<void> _loadStoredSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final oldIp = serverIp;
      serverIp = prefs.getString('server_ip') ?? "";
      serverPort = prefs.getString('server_port') ?? "";

      // IP 변경 시 캐시 초기화 고려 (전체 이미지 캐시 비우기)
      if (oldIp.isNotEmpty && oldIp != serverIp) {
        DefaultCacheManager().emptyCache();
        _connectWebSocket(); // IP 변경 시 웹소켓 재연결
      } else if (_wsChannel == null) {
        _connectWebSocket(); // 초기 연결
      }
    });
  }

  void _connectWebSocket() {
    if (serverIp.isEmpty || serverPort.isEmpty || _isWsConnecting) return;

    _isWsConnecting = true;
    final wsUrl = 'ws://$serverIp:$serverPort/ws';
    debugPrint("Connecting to WebSocket: $wsUrl");

    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen(
        (message) {
          debugPrint("WS Message Received: $message");
          _handleWsMessage(message);
        },
        onDone: () {
          debugPrint("WS Connection Closed. Reconnecting in 5s...");
          _wsChannel = null;
          _isWsConnecting = false;
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
        onError: (e) {
          debugPrint("WS Error: $e. Reconnecting in 5s...");
          _wsChannel = null;
          _isWsConnecting = false;
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      debugPrint("WS Connect Error: $e");
      _isWsConnecting = false;
    }
  }

  void _handleWsMessage(dynamic message) {
    try {
      final data = jsonDecode(message);

      // 삭제 명령 수신 처리
      if (data['type'] == 'DELETE_ORDER') {
        final deleteId = data['orderId'];
        final index = orders.indexWhere((o) => o.id == deleteId);
        if (index != -1) {
          _removeOrderFromUI(index, remote: true);
        }
        return;
      }

      final newOrder = OrderInfo(
        id: (data['id'] ?? data['orderId'] ?? "").toString(),
        tableNo: (data['table'] ?? data['tableNo'] ?? "Unknown").toString(),
        menus: List<String>.from(data['items'] ?? data['menus'] ?? []),
        time: (data['time'] ?? "").toString(),
      );

      setState(() {
        orders.insert(0, newOrder);
        unreadOrdersCount++;
        _listKey.currentState?.insertItem(
          0,
          duration: const Duration(milliseconds: 500),
        );
      });

      // 신규 주문 알림 소리
      SystemSound.play(SystemSoundType.click);

      // 우측 주문 패널 자동 활성화
      _scaffoldKey.currentState?.openEndDrawer();
    } catch (e) {
      debugPrint("WS JSON Parse Error: $e");
    }
  }

  void _removeOrderFromUI(int index, {bool remote = false}) {
    if (index < 0 || index >= orders.length) return;

    final removedItem = orders[index];

    // UI에서 아이템 제거 애니메이션 수행
    _listKey.currentState?.removeItem(
      index,
      (context, animation) => _buildOrderItem(removedItem, animation, index),
      duration: const Duration(milliseconds: 500),
    );

    setState(() {
      orders.removeAt(index);
    });

    // 직접 삭제한 경우에만 서버에 신호 전송
    if (!remote && _wsChannel != null) {
      final deleteMsg = jsonEncode({
        "type": "DELETE_ORDER",
        "orderId": removedItem.id,
      });
      _wsChannel!.sink.add(deleteMsg);
    }
  }

  Future<void> _confirmDeleteOrder(int index) async {
    final order = orders[index];
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("조리 완료 확인"),
        content: Text("TABLE #${order.tableNo} 주문을 완료 처리할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text("완료", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _removeOrderFromUI(index);
    }
  }

  Future<void> loadData({bool forceSync = false}) async {
    if (serverIp.isEmpty || serverPort.isEmpty) {
      if (forceSync) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("서버 주소가 설정되지 않았습니다.")));
      }
      return;
    }

    setState(() {
      isLoading = !forceSync; // 강제 동기화 시에는 전체 로딩 대신 별도 처리 가능
      isSyncing = forceSync;
    });

    bool loadSuccess = await _fetchFromServer();

    if (forceSync) {
      if (!loadSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("서버 연결 실패. 기존 데이터를 유지합니다.")),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("데이터 동기화 완료")));
        }
      }
    } else if (!loadSuccess) {
      // 일반 로딩 시 서버 실패했고 이미 로컬 데이터가 없다면 Mock 로드
      if (allMenus.isEmpty) {
        await loadJsonData();
      }
    }

    setState(() {
      isLoading = false;
      isSyncing = false;
    });
  }

  Future<bool> _fetchFromServer() async {
    try {
      final url = Uri.parse('http://$serverIp:$serverPort/api/kitchen_data');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _parseAndSetData(data);
        await _saveToLocal(response.body); // 로컬 저장
        return true;
      }
    } catch (e) {
      debugPrint("Server fetch error: $e");
    }
    return false;
  }

  void _parseAndSetData(dynamic data) {
    setState(() {
      categories = List<String>.from(data['categories']);
      allMenus = (data['menus'] as List)
          .map(
            (m) => MenuInfo(
              name: m['name'],
              cat: m['cat'],
              time: m['time'] ?? 0,
              recipe: m['recipe'] ?? "",
              imageUrl: m['image'] ?? m['imageUrl'] ?? "",
            ),
          )
          .toList();
      orders = (data['orders'] as List)
          .map(
            (o) => OrderInfo(
              id: (o['id'] ?? o['orderId'] ?? "").toString(),
              tableNo: o['tableNo'] ?? o['table'] ?? "",
              menus: List<String>.from(o['menus'] ?? o['items'] ?? []),
              time: o['time'] ?? "",
            ),
          )
          .toList();
    });
  }

  Future<void> loadJsonData() async {
    // 1. 파일 읽기
    final String response = await rootBundle.loadString(
      'assets/data/mock_data.json',
    );
    final data = await jsonDecode(response);

    setState(() {
      // 2. 카테고리 로드
      categories = List<String>.from(data['categories']);

      // 3. 메뉴 로드 (JSON -> 객체 변환)
      allMenus = (data['menus'] as List)
          .map(
            (m) => MenuInfo(
              name: m['name'],
              cat: m['cat'],
              time: m['time'] ?? 0,
              recipe: m['recipe'] ?? "",
            ),
          )
          .toList();

      // 4. 주문 로드
      orders = (data['orders'] as List)
          .map(
            (o) => OrderInfo(
              id: (o['orderId'] ?? "").toString(),
              tableNo: (o['tableNo'] ?? o['table'] ?? "").toString(),
              menus: List<String>.from(o['menus'] ?? o['items'] ?? []),
              time: (o['time'] ?? "").toString(),
            ),
          )
          .toList();

      isLoading = false; // 로딩 완료
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.black87),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text(
          "KITCHEN SYSTEM",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.assignment, color: Colors.blue),
                onPressed: () {
                  setState(() => unreadOrdersCount = 0);
                  _scaffoldKey.currentState?.openEndDrawer();
                },
              ),
              if (unreadOrdersCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      "$unreadOrdersCount",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(width: 300, child: _buildSidebar()),
      endDrawer: Drawer(width: 380, child: _buildOrderSidebar()),
      body: _buildMenuGrid(),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "KITCHEN SYSTEM",
            style: TextStyle(
              color: Colors.blue,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            "카테고리",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, i) {
                bool isActive =
                    filterMode == "CATEGORY" &&
                    selectedCategory == categories[i];
                return ListTile(
                  selected: isActive,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    categories[i],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.blue : Colors.black54,
                    ),
                  ),
                  trailing: isActive
                      ? const Icon(Icons.chevron_right, color: Colors.blue)
                      : null,
                  onTap: () => setState(() {
                    filterMode = "CATEGORY";
                    selectedCategory = categories[i];
                    searchTerm = "";
                  }),
                );
              },
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: const Text("서버 설정", style: TextStyle(color: Colors.black54)),
            onTap: _showSettingsDialog,
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    final ipController = TextEditingController(text: serverIp);
    final portController = TextEditingController(text: serverPort);
    bool isServerConnected = false;
    String? testButtonLabel;
    int? countdownSeconds;
    Timer? countdownTimer;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              "서버 연결 설정",
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ipController,
                  decoration: const InputDecoration(
                    labelText: "서버 IP (Tailscale)",
                    hintText: "100.x.x.x",
                    prefixIcon: Icon(Icons.lan),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "포트 번호",
                    hintText: "8080",
                    prefixIcon: Icon(Icons.numbers),
                  ),
                ),
                const SizedBox(height: 24),
                if (connectionStatus != null && connectionStatus != "testing")
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: connectionStatus == "success"
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          connectionStatus == "success"
                              ? Icons.check_circle
                              : Icons.error,
                          color: connectionStatus == "success"
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            connectionStatus == "success"
                                ? "연결 성공!"
                                : (errorMessage ?? "연결 실패"),
                            style: TextStyle(
                              color: connectionStatus == "success"
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  countdownTimer?.cancel();
                  Navigator.pop(context);
                },
                child: const Text("취소"),
              ),
              ElevatedButton(
                onPressed: connectionStatus == "testing"
                    ? null
                    : () async {
                        setDialogState(() {
                          connectionStatus = "testing";
                          errorMessage = null;
                          countdownSeconds = 5;
                          testButtonLabel = "연결 시도 중... (5s)";
                        });

                        countdownTimer?.cancel();
                        countdownTimer = Timer.periodic(
                          const Duration(seconds: 1),
                          (timer) {
                            setDialogState(() {
                              if (countdownSeconds! > 0) {
                                countdownSeconds = countdownSeconds! - 1;
                                testButtonLabel =
                                    "연결 시도 중... (${countdownSeconds}s)";
                              } else {
                                timer.cancel();
                              }
                            });
                          },
                        );

                        try {
                          final testIp = ipController.text.trim();
                          final testPort = portController.text.trim();
                          final url = Uri.parse(
                            'http://$testIp:$testPort/api/kitchen_data',
                          );
                          final response = await http
                              .get(url)
                              .timeout(const Duration(seconds: 5));

                          countdownTimer?.cancel();

                          if (response.statusCode == 200) {
                            setDialogState(() {
                              connectionStatus = "success";
                              isServerConnected = true;
                              testButtonLabel = "연결 성공";
                            });
                            // 연결 성공 시 자동 동기화 트리거
                            _syncDataInternal(testIp, testPort, setDialogState);
                          } else {
                            setDialogState(() {
                              connectionStatus = "error";
                              errorMessage = "상태 코드: ${response.statusCode}";
                              isServerConnected = false;
                              testButtonLabel = "연결 실패";
                            });
                          }
                        } on SocketException catch (e) {
                          countdownTimer?.cancel();
                          setDialogState(() {
                            connectionStatus = "error";
                            errorMessage =
                                "네트워크 오류: ${e.message}\n(IP 주소가 올바른지, 서버가 켜져 있는지 확인하세요)";
                            isServerConnected = false;
                            testButtonLabel = "연결 실패";
                          });
                        } on TimeoutException {
                          countdownTimer?.cancel();
                          setDialogState(() {
                            connectionStatus = "error";
                            errorMessage = "연결 시간 초과\n(서버 응답이 너무 늦습니다)";
                            isServerConnected = false;
                            testButtonLabel = "연결 실패";
                          });
                        } on http.ClientException catch (e) {
                          countdownTimer?.cancel();
                          setDialogState(() {
                            connectionStatus = "error";
                            errorMessage = "클라이언트 오류: ${e.message}";
                            isServerConnected = false;
                            testButtonLabel = "연결 실패";
                          });
                        } catch (e) {
                          countdownTimer?.cancel();
                          setDialogState(() {
                            connectionStatus = "error";
                            errorMessage = "알 수 없는 오류: $e";
                            isServerConnected = false;
                            testButtonLabel = "연결 실패";
                          });
                        }
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connectionStatus == "testing")
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue,
                        ),
                      ),
                    if (connectionStatus == "testing") const SizedBox(width: 8),
                    Text(testButtonLabel ?? "연결 테스트"),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: isServerConnected && !isSyncing
                    ? () => _syncDataInternal(
                        ipController.text.trim(),
                        portController.text.trim(),
                        setDialogState,
                      )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isServerConnected
                      ? Colors.blue
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 50), // 버튼 높이 증가
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSyncing)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    if (isSyncing) const SizedBox(width: 8),
                    Text(syncStatusText ?? "데이터 동기화"),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('server_ip', ipController.text.trim());
                  await prefs.setString(
                    'server_port',
                    portController.text.trim(),
                  );

                  setState(() {
                    serverIp = ipController.text.trim();
                    serverPort = portController.text.trim();
                  });

                  countdownTimer?.cancel();
                  if (context.mounted) Navigator.pop(context);
                  loadData(); // 새 설정으로 데이터 로드 시도
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF141A2E),
                  minimumSize: const Size(0, 50), // 버튼 높이 증가
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "저장 및 불러오기",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      // 다이얼로그 닫힐 때 상태 초기화
      countdownTimer?.cancel();
      setState(() {
        connectionStatus = null;
        errorMessage = null;
        syncStatusText = null;
      });
    });
  }

  String? syncStatusText;

  Future<void> _syncDataInternal(
    String ip,
    String port,
    Function(void Function()) setDialogState,
  ) async {
    setDialogState(() => syncStatusText = "데이터 확인 중...");
    setState(() => isSyncing = true);

    int maxRetries = 2;
    int retryCount = 0;
    bool success = false;

    while (retryCount <= maxRetries && !success) {
      try {
        if (retryCount > 0) {
          setDialogState(
            () => syncStatusText = "재시도 중... ($retryCount/$maxRetries)",
          );
          await Future.delayed(const Duration(seconds: 1));
        }

        // 1. Handshake (Ping)
        final pingUrl = Uri.parse(
          'http://$ip:$port/api/kitchen_data',
        ); // 가벼운 엔드포인트가 없으므로 동일 API 사용하되 타임아웃 짧게
        final pingResponse = await http
            .head(pingUrl)
            .timeout(const Duration(seconds: 3));

        if (pingResponse.statusCode == 200 || pingResponse.statusCode == 405) {
          // HEAD 미지원 시 405 가능
          setDialogState(() => syncStatusText = "다운로드 중...");

          await DefaultCacheManager().emptyCache();

          final originalIp = serverIp;
          final originalPort = serverPort;
          serverIp = ip;
          serverPort = port;

          success = await _fetchFromServer(); // 내부에서 _saveToLocal 호출됨

          serverIp = originalIp;
          serverPort = originalPort;

          if (success) {
            setDialogState(() => syncStatusText = "저장 중...");
            await Future.delayed(
              const Duration(milliseconds: 500),
            ); // 저장 시각적 피드백
            success = true;
          }
        }
      } catch (e) {
        debugPrint("Sync attempt $retryCount failed: $e");
      }

      if (!success) {
        retryCount++;
      }
    }

    setState(() => isSyncing = false);
    setDialogState(() => syncStatusText = success ? "동기화 완료" : "동기화 실패");

    // 최종 상태 확정 후 스낵바 노출
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? "최신 데이터로 업데이트되었습니다." : "데이터 동기화 실패. 네트워크를 확인하세요.",
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }

    // 성공 시 잠시 후 텍스트 원복
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setDialogState(() => syncStatusText = null);
    });
  }

  Widget _buildMenuGrid() {
    return Container(
      color: const Color(0xFFF3F6F9),
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => setState(() => searchTerm = v),
            decoration: InputDecoration(
              hintText: "메뉴명 또는 초성 입력",
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                filterMode == "ORDER"
                    ? "TABLE #$activeTableNo ORDER"
                    : "MENU LIST",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (filterMode == "ORDER")
                TextButton(
                  onPressed: () => setState(() => filterMode = "CATEGORY"),
                  child: const Text("전체 메뉴 보기"),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20), // 전체 패딩 약간 조정
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220, // 카드 최대 너비를 줄여 더 많은 카드를 노출
                mainAxisSpacing: 15, // 여백 최적화
                crossAxisSpacing: 15,
                childAspectRatio: 0.65, // 높이 비율 소폭 축소
              ),
              itemCount: filteredMenus.length,
              itemBuilder: (context, i) => MenuCard(menu: filteredMenus[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSidebar() {
    return Container(
      width: 380,
      color: const Color(0xFFF3F6F9),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "실시간 주문 현황",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                if (unreadOrdersCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "$unreadOrdersCount건의 미처리 주문",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedList(
              key: _listKey,
              initialItemCount: orders.length,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemBuilder: (context, index, animation) {
                return _buildOrderItem(orders[index], animation, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(
    OrderInfo order,
    Animation<double> animation,
    int index,
  ) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Dismissible(
            key: Key(order.id + index.toString()),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _confirmDeleteOrder(index);
              return false; // 애니메이션은 _removeOrderFromUI에서 직접 제어
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 30),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 30),
            ),
            child: GestureDetector(
              onTap: () => setState(() {
                filterMode = "ORDER";
                activeOrderMenus = order.menus;
                activeTableNo = order.tableNo;
              }),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "TABLE",
                            style: TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            order.time,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        order.tableNo.padLeft(3, '0'),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        order.menus.join(", "),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- 메뉴 카드 위젯 (타이머 포함) ---
class MenuCard extends StatefulWidget {
  final MenuInfo menu;
  const MenuCard({super.key, required this.menu});

  @override
  State<MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<MenuCard> {
  late int timeLeft;
  bool isActive = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timeLeft = widget.menu.time;
  }

  void toggleTimer() {
    if (isActive) {
      timer?.cancel();
    } else {
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (timeLeft > 0) {
          setState(() => timeLeft--);
        } else {
          t.cancel();
          setState(() => isActive = false);
        }
      });
    }
    setState(() => isActive = !isActive);
  }

  @override
  Widget build(BuildContext context) {
    bool isActive = timer?.isActive ?? false;
    bool isFinished = timeLeft == 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // 카드 너비에 따른 가변 폰트 사이즈 계산 (clamp 활용)
        final titleFontSize = (cardWidth * 0.08).clamp(
          16.0,
          22.0,
        ); // 폰트 상한 하향 조정
        final categoryFontSize = (cardWidth * 0.045).clamp(10.0, 14.0);
        final iconSize = (cardWidth * 0.08).clamp(16.0, 22.0);
        final miniIconSize = (cardWidth * 0.06).clamp(12.0, 16.0);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                offset: const Offset(0, 6),
                blurRadius: 16,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 상단 이미지 영역 (고정 비율 확보)
                Expanded(
                  flex: 10, // 이미지 영역 높이 축소 (12 -> 10)
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.menu.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.menu.imageUrl,
                              placeholder: (context, url) => Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) =>
                                  _buildPlaceholder(cardWidth),
                              fit: BoxFit.cover,
                            )
                          : _buildPlaceholder(cardWidth),

                      // 타이머 배지
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.blue.withValues(alpha: 0.9)
                                : isFinished
                                ? Colors.red.withValues(alpha: 0.9)
                                : Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isFinished
                                ? "DONE"
                                : "${(timeLeft ~/ 60).toString().padLeft(2, '0')}:${(timeLeft % 60).toString().padLeft(2, '0')}",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: (cardWidth * 0.05).clamp(12.0, 16.0),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. 텍스트 및 정보 영역
                Expanded(
                  flex: 13, // 텍스트 영역 비중 소폭 확대
                  child: Padding(
                    padding: EdgeInsets.all(cardWidth * 0.06), // 패딩 축소
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.menu.cat,
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: categoryFontSize,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 메뉴명: 너비에 따른 폰트 자동 조절 및 2줄 제한
                        Expanded(
                          flex: 2,
                          child: Container(
                            alignment: Alignment.topLeft,
                            child: Text(
                              widget.menu.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: titleFontSize,
                                height: 1.1,
                                color: const Color(0xFF141A2E),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        // 3. 버튼 레이아웃 - Scalable 가변 디자인
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // [조리 시작 / 정지]
                              SizedBox(
                                width: double.infinity,
                                height: (cardWidth * 0.2).clamp(44.0, 56.0),
                                child: ElevatedButton(
                                  onPressed: isFinished ? null : toggleTimer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isActive
                                        ? Colors.orange
                                        : const Color(0xFF1A61FF),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    padding: EdgeInsets.zero,
                                    shadowColor:
                                        (isActive ? Colors.orange : Colors.blue)
                                            .withValues(alpha: 0.3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isActive
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_fill,
                                        size: iconSize,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            isActive ? "조리 정지" : "조리 시작",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  // [리셋]
                                  Expanded(
                                    child: SizedBox(
                                      height: (cardWidth * 0.16).clamp(
                                        38.0,
                                        48.0,
                                      ),
                                      child: OutlinedButton(
                                        onPressed: () => setState(() {
                                          timeLeft = widget.menu.time;
                                          isActive = false;
                                          timer?.cancel();
                                        }),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.grey.shade700,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          side: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.refresh,
                                              size: miniIconSize,
                                            ),
                                            const SizedBox(width: 3),
                                            const Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "초기화",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // [레시피]
                                  Expanded(
                                    child: SizedBox(
                                      height: (cardWidth * 0.16).clamp(
                                        38.0,
                                        48.0,
                                      ),
                                      child: ElevatedButton(
                                        onPressed: () => _showRecipe(context),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF141A2E,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.menu_book,
                                              size: miniIconSize,
                                            ),
                                            const SizedBox(width: 3),
                                            const Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  "레시피",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 이미지 없을 때 메뉴명을 활용한 플레이스홀더
  Widget _buildPlaceholder(double cardWidth) {
    String initial = widget.menu.name.isNotEmpty
        ? widget.menu.name.substring(0, 1)
        : "?";
    return Container(
      color: const Color(0xFFF3F6F9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: cardWidth * 0.25,
              height: cardWidth * 0.25,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: cardWidth * 0.12,
                    fontWeight: FontWeight.w900,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "이미지 로드 중...",
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: (cardWidth * 0.04).clamp(10.0, 14.0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecipe(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
        title: Text(
          "${widget.menu.name} 레시피",
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(widget.menu.recipe),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }
}
