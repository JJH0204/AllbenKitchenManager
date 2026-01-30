import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/menu_info.dart';
import '../models/order_info.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/websocket_service.dart';
import '../utils/hangul_utils.dart';

/// 파일명: lib/providers/kitchen_provider.dart
/// 작성의도: 앱의 핵심 비즈니스 로직과 상태 관리를 통합 제어합니다. (Brain 역할)
/// 기능 원리: `ChangeNotifier`를 상속받아 메뉴 목록, 주문 목록, 검색 상태 등을 관리합니다.
///          각종 Service(API, Storage, WS)와 상호작용하여 데이터를 가져오고,
///          상태 변화 발생 시 UI에 알림(`notifyListeners`)을 보내 화면을 갱신합니다.

class KitchenProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final WebSocketService _wsService = WebSocketService();
  Completer<bool>? _syncCompleter;
  Completer<bool>? _ackCompleter; // Handshake completer

  // Data State
  List<MenuInfo> _allMenus = [];
  List<OrderInfo> _orders = [];
  List<String> _categories = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _wsConnectionStatus; // null, "connecting", "success", "error"
  String? _wsErrorMessage;

  // UI State
  String _selectedCategory = "전체";
  String _searchTerm = "";
  String _filterMode = "CATEGORY"; // "CATEGORY" or "ORDER"
  List<String> _activeOrderMenus = [];
  String _activeTableNo = "";
  int _unreadOrdersCount = 0;

  // Server Settings
  String _serverIp = "";
  String _serverPort = "";

  // Getters
  List<MenuInfo> get allMenus => _allMenus;
  List<OrderInfo> get orders => _orders;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String get selectedCategory => _selectedCategory;
  String get searchTerm => _searchTerm;
  String get filterMode => _filterMode;
  List<String> get activeOrderMenus => _activeOrderMenus;
  String get activeTableNo => _activeTableNo;
  int get unreadOrdersCount => _unreadOrdersCount;
  String get serverIp => _serverIp;
  String get serverPort => _serverPort;
  String? get wsConnectionStatus => _wsConnectionStatus;
  String? get wsErrorMessage => _wsErrorMessage;

  List<MenuInfo> get filteredMenus {
    Iterable<MenuInfo> temp = _allMenus;
    if (_searchTerm.isNotEmpty) {
      String lowerSearch = _searchTerm.toLowerCase();
      String searchCho = getChosung(lowerSearch);
      temp = temp.where(
        (m) =>
            m.name.toLowerCase().contains(lowerSearch) ||
            getChosung(m.name).contains(searchCho),
      );
    }
    if (_filterMode == "ORDER") {
      temp = temp.where((m) => _activeOrderMenus.contains(m.name));
    } else if (_selectedCategory != "전체") {
      temp = temp.where((m) => m.cat == _selectedCategory);
    }
    return temp.toList();
  }

  void setSearchTerm(String term) {
    _searchTerm = term;
    notifyListeners();
  }

  void setCategory(String category) {
    _filterMode = "CATEGORY";
    _selectedCategory = category;
    _searchTerm = "";
    notifyListeners();
  }

  void setOrderFilter(List<String> menus, String tableNo) {
    _filterMode = "ORDER";
    _activeOrderMenus = menus;
    _activeTableNo = tableNo;
    notifyListeners();
  }

  void resetUnreadCount() {
    _unreadOrdersCount = 0;
    notifyListeners();
  }

  Future<void> initApp() async {
    final settings = await _storageService.loadSettings();
    _serverIp = settings['ip']!;
    _serverPort = settings['port']!;

    bool hasLocalData = false;
    final cachedData = await _storageService.loadFromLocal();
    if (cachedData != null) {
      _parseAndSetData(cachedData);
      hasLocalData = true;
    }

    if (_serverIp.isNotEmpty && _serverPort.isNotEmpty) {
      // 앱 시작 시 자동 연결 및 데이터 동기화
      connectAndSync(_serverIp, _serverPort);
    } else if (!hasLocalData) {
      await loadMockData();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> connectWebSocket({
    String? ip,
    String? port,
    bool autoReqData = false,
  }) async {
    final targetIp = ip ?? _serverIp;
    final targetPort = port ?? _serverPort;

    if (targetIp.isEmpty || targetPort.isEmpty) {
      _wsConnectionStatus = "error";
      _wsErrorMessage = "IP/Port가 설정되지 않았습니다.";
      notifyListeners();
      return;
    }

    _wsConnectionStatus = "connecting";
    _wsErrorMessage = null;
    notifyListeners();

    _wsService.dispose();
    _ackCompleter = Completer<bool>();

    try {
      final channel = _wsService.connect(
        targetIp,
        targetPort,
        onData: (data) => _handleWsMessage(data),
        onDone: () {
          debugPrint("WS Connection Closed. Reconnecting in 5s...");
          _wsConnectionStatus = "error";
          _wsErrorMessage = "실시간 연결 중단됨. 재연결 중...";
          _isSyncing = false;
          _syncCompleter?.complete(false);
          _ackCompleter?.complete(false);
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () => connectWebSocket());
        },
        onError: (e) {
          debugPrint("WS Error: $e");
          _wsConnectionStatus = "error";
          _wsErrorMessage = "연결 오류: $e";
          _isSyncing = false;
          _syncCompleter?.complete(false);
          _ackCompleter?.complete(false);
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () => connectWebSocket());
        },
      );

      if (channel == null) throw Exception("연결 실패");

      // Handshake Timeout: 5초 (Step 2 대응)
      _startHandshakeTimeout();

      // ACK 수신 대기
      final ackReceived = await _ackCompleter!.future;
      if (ackReceived && autoReqData) {
        _wsService.sendMessage(jsonEncode({"type": "REQ_KITCHEN_DATA"}));
      }
    } catch (e) {
      _wsConnectionStatus = "error";
      _wsErrorMessage = e.toString();
      _isSyncing = false;
      _syncCompleter?.complete(false);
      _ackCompleter?.complete(false);
      notifyListeners();
    }
  }

  void _startHandshakeTimeout() {
    Future.delayed(const Duration(seconds: 10), () {
      if (_wsConnectionStatus == "connecting" &&
          _ackCompleter != null &&
          !_ackCompleter!.isCompleted) {
        debugPrint("Handshake Timeout");
        _wsConnectionStatus = "error";
        _wsErrorMessage = "서버 응답 시간 초과 (Handshake Timeout)";
        _isSyncing = false;
        _ackCompleter?.complete(false);
        notifyListeners();
      }
    });
  }

  Future<bool> connectAndSync(String ip, String port) async {
    _serverIp = ip;
    _serverPort = port;
    await _storageService.saveSettings(ip, port);

    _isSyncing = true;
    _wsConnectionStatus = "connecting";
    _syncCompleter = Completer<bool>();
    notifyListeners();

    try {
      await connectWebSocket(ip: ip, port: port, autoReqData: true);

      // 사용자 요구사항: CONNECTION_ACK 수신 시 모달을 닫기 위해 ACK 대기 (Step 4 대응)
      // 데이터 동기화(KITCHEN_DATA)는 백그라운드에서 계속 진행됨.
      final success = await _ackCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      return success;
    } catch (e) {
      _isSyncing = false;
      notifyListeners();
      return false;
    }
  }

  void _handleWsMessage(dynamic data) {
    try {
      // WebSocketService에서 이미 jsonDecode를 수행하여 전달하므로 data는 Map입니다.
      if (data is! Map<String, dynamic>) return;
      final Map<String, dynamic> message = data;
      final type = message['type'];

      switch (type) {
        case 'CONNECTION_ACK':
          debugPrint("CONNECTION_ACK received!");
          _wsConnectionStatus = "success";
          _wsErrorMessage = null;
          _isSyncing = false; // ACK 수신 시 즉시 로딩 상태 해제
          _ackCompleter?.complete(true);
          notifyListeners();
          break;

        case 'KITCHEN_DATA':
        case 'MENU_DATA':
          final rawPayload = message['payload'] ?? message;
          if (rawPayload is List) {
            _parseAndSetMenuData(rawPayload);
          } else if (rawPayload is Map<String, dynamic>) {
            _parseAndSetData(rawPayload);
          } else {
            debugPrint(
              "Invalid payload type for $type: ${rawPayload.runtimeType}",
            );
            return;
          }
          _storageService.saveToLocal(jsonEncode(rawPayload));
          _isSyncing = false;
          _syncCompleter?.complete(true);
          notifyListeners();
          break;

        case 'DELETE_ORDER':
        case 'ORDER_DELETE':
          final deleteId = message['payload'] ?? message['orderId'];
          if (deleteId != null) {
            final index = _orders.indexWhere(
              (o) => o.id == deleteId.toString(),
            );
            if (index != -1) {
              removeOrder(index, remote: true);
            }
          }
          break;

        case 'ORDER_CREATE':
          final orderData = message['payload'] ?? message;
          if (orderData is! Map<String, dynamic>) {
            debugPrint("Order payload is not a Map: ${orderData.runtimeType}");
            return;
          }
          final newOrder = OrderInfo.fromJson(orderData);
          _orders.insert(0, newOrder);
          _unreadOrdersCount++;
          SystemSound.play(SystemSoundType.click);
          notifyListeners();
          break;

        default:
          debugPrint("Unrecognized domain event: $type");
          break;
      }
    } catch (e) {
      debugPrint("Domain Logic Error: $e");
    }
  }

  void removeOrder(int index, {bool remote = false}) {
    if (index < 0 || index >= _orders.length) return;
    final removed = _orders.removeAt(index);
    if (!remote) {
      _wsService.sendMessage(
        jsonEncode({"type": "DELETE_ORDER", "orderId": removed.id}),
      );
    }
    notifyListeners();
  }

  Future<void> loadData({bool forceSync = false}) async {
    if (_serverIp.isEmpty || _serverPort.isEmpty) return;

    if (forceSync) _isSyncing = true;
    notifyListeners();

    try {
      final response = await _apiService.fetchKitchenData(
        _serverIp,
        _serverPort,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _parseAndSetData(data);
        await _storageService.saveToLocal(response.body);
      }
    } catch (e) {
      if (!forceSync && _allMenus.isEmpty) await loadMockData();
    }

    _isSyncing = false;
    notifyListeners();
  }

  void _parseAndSetData(dynamic data) {
    if (data == null) return;

    // 1. 데이터 추출 (Map 또는 List 대응)
    List<dynamic>? rawMenus;
    List<dynamic>? rawOrders;

    if (data is List) {
      rawMenus = data;
    } else if (data is Map) {
      if (data.containsKey('menus')) rawMenus = data['menus'];
      if (data.containsKey('orders')) rawOrders = data['orders'];
    }

    // 2. 메뉴 데이터 갱신 및 카테고리 자동 추출
    if (rawMenus != null) {
      _allMenus.clear();
      _allMenus.addAll(rawMenus.map((m) => MenuInfo.fromJson(m)));

      // 메뉴 기반으로 동적 카테고리 생성
      final extracted = _allMenus.map((m) => m.cat).toSet().toList()..sort();
      _categories = ["전체", ...extracted];
    }

    // 3. 주문 데이터 갱신 (Full Sync 대응)
    if (rawOrders != null) {
      _orders.clear();
      _orders.addAll(rawOrders.map((o) => OrderInfo.fromJson(o)));
    }

    // 4. UI 갱신
    notifyListeners();
  }

  // // 서버에 주문 데이터를 요청하는 함수
  // void _requestOrdersFromServer() {
  //   // WebSocketService 등을 통해 서버가 정의한 '주문 요청' 패킷 전송
  //   _wsService.sendMessage(
  //     jsonEncode({
  //       "type": "GET_ORDERS",
  //       "timestamp": DateTime.now().toIso8601String(),
  //     }),
  //   );
  // }

  void _parseAndSetMenuData(List<dynamic> menuList) {
    _allMenus.clear();

    final newMenus = menuList.map((m) => MenuInfo.fromJson(m)).toList();

    _allMenus.addAll(newMenus);

    // 카테고리 동적 추출 및 정렬

    final extractedCategories = newMenus.map((m) => m.cat).toSet().toList();

    extractedCategories.sort();

    _categories.clear();

    _categories.add("전체");

    _categories.addAll(extractedCategories);

    notifyListeners();
  }

  Future<void> loadMockData() async {
    final String response = await rootBundle.loadString(
      'assets/data/mock_data.json',
    );
    final data = jsonDecode(response);
    _parseAndSetData(data);
  }

  Future<void> updateSettings(String ip, String port) async {
    await connectAndSync(ip, port);
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }
}
