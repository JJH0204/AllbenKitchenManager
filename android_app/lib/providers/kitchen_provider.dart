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

enum DisplayMode { menus, orders, settings }

class KitchenProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();
  final WebSocketService _wsService = WebSocketService();
  Completer<bool>? _syncCompleter;
  Completer<bool>? _ackCompleter; // Handshake completer
  Timer? _cookingTimer;

  // Data State
  List<MenuInfo> _allMenus = [];
  final Map<String, MenuInfo> _menuMap = {}; // ID to MenuInfo cache
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
  String _activeTable = "";
  int _unreadOrdersCount = 0;
  DisplayMode _displayMode = DisplayMode.orders;

  // Server Settings
  String _serverIp = "";
  String _serverPort = "";

  // Getters
  List<MenuInfo> get allMenus => _allMenus;
  Map<String, MenuInfo> get menuMap => _menuMap;
  List<OrderInfo> get orders => _orders;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String get selectedCategory => _selectedCategory;
  String get searchTerm => _searchTerm;
  String get filterMode => _filterMode;
  List<String> get activeOrderMenus => _activeOrderMenus;
  String get activeTable => _activeTable;
  int get unreadOrdersCount => _unreadOrdersCount;
  String get serverIp => _serverIp;
  String get serverPort => _serverPort;
  String? get wsConnectionStatus => _wsConnectionStatus;
  String? get wsErrorMessage => _wsErrorMessage;
  DisplayMode get displayMode => _displayMode;

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

  void setOrderFilter(List<String> menus, String table) {
    _filterMode = "ORDER";
    _activeOrderMenus = menus;
    _activeTable = table;
    notifyListeners();
  }

  void resetUnreadCount() {
    _unreadOrdersCount = 0;
    notifyListeners();
  }

  void setDisplayMode(DisplayMode mode) {
    _displayMode = mode;
    notifyListeners();
  }

  void _startCookingTimer() {
    _cookingTimer?.cancel();
    _cookingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      bool changed = false;
      for (var order in _orders) {
        for (var item in order.ord) {
          if (item.status == CookingStatus.cooking &&
              item.remainingSeconds > 0) {
            item.remainingSeconds--;
            if (item.remainingSeconds == 0) {
              item.status = CookingStatus.done;
            }
            changed = true;
          }
        }
      }
      if (changed) notifyListeners();
    });
  }

  void toggleItemStatus(OrderInfo order, OrderItem item) {
    if (item.status == CookingStatus.done) return;

    if (item.status == CookingStatus.waiting) {
      item.status = CookingStatus.cooking;
    } else {
      item.status = CookingStatus.waiting;
    }
    notifyListeners();
  }

  Future<void> initApp() async {
    final settings = await _storageService.loadSettings();
    _serverIp = settings['ip']!;
    _serverPort = settings['port']!;

    // 1. 메뉴 마스터 최우선 로드
    await _loadMenuMaster();

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
    _startCookingTimer();
    notifyListeners();
  }

  Future<void> _loadMenuMaster() async {
    try {
      final String response = await rootBundle.loadString('json/menus.json');
      final List<dynamic> data = jsonDecode(response);
      _parseAndSetMenuData(data);
      debugPrint("Menu Master loaded: ${_menuMap.length} items.");
    } catch (e) {
      debugPrint("Error loading Menu Master: $e");
    }
  }

  void _resolveOrder(OrderInfo order) {
    for (var item in order.ord) {
      final menu = _menuMap[item.main];
      if (menu != null) {
        // Enrichment
        item.name = menu.name;
        item.recipe = menu.recipe;
        item.totalSeconds = menu.cookTime;
        item.remainingSeconds = menu.cookTime;
      } else {
        // Fallback for missing master data
        item.name = item.main;
        item.recipe = "레시피 정보가 없습니다.";
      }
    }
  }

  // Helper to create a resolved OrderItem for sub-items (read-only slot representation)
  OrderItem resolveSubItem(String subId, CookingStatus status) {
    final menu = _menuMap[subId];
    return OrderItem(
      main: subId,
      name: menu?.name ?? subId,
      recipe: menu?.recipe ?? "레시피 정보가 없습니다.",
      status: status,
      totalSeconds: menu?.cookTime ?? 0,
      remainingSeconds: menu?.cookTime ?? 0,
    );
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
          _resolveOrder(newOrder);
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
      if (data.isNotEmpty) {
        final first = data[0];
        // 주문 데이터인지 메뉴 데이터인지 대각선 검사
        if (first is Map<String, dynamic>) {
          if (first.containsKey('ord') || first.containsKey('table')) {
            rawOrders = data;
          } else if (first.containsKey('cat') ||
              first.containsKey('category')) {
            rawMenus = data;
          }
        }
      }
    } else if (data is Map<String, dynamic>) {
      if (data['menus'] is List) rawMenus = data['menus'];
      if (data['orders'] is List) rawOrders = data['orders'];
    }

    // 2. 메뉴 데이터 갱신 (마스터 맵 빌드 포함)
    if (rawMenus != null) {
      _parseAndSetMenuData(rawMenus);
    }

    // 3. 주문 데이터 갱신 및 Enrichment
    if (rawOrders != null) {
      _orders.clear();
      for (var o in rawOrders) {
        if (o is Map<String, dynamic>) {
          final order = OrderInfo.fromJson(o);
          _resolveOrder(order);
          _orders.add(order);
        }
      }
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
    _menuMap.clear();

    final newMenus = menuList.map((m) => MenuInfo.fromJson(m)).toList();
    _allMenus.addAll(newMenus);

    for (var m in newMenus) {
      _menuMap[m.id] = m;
    }

    // 카테고리 동적 추출 및 정렬
    final extractedCategories = newMenus.map((m) => m.cat).toSet().toList();
    extractedCategories.sort();

    _categories.clear();
    _categories.add("전체");
    _categories.addAll(extractedCategories);

    notifyListeners();
  }

  Future<void> loadMockData() async {
    debugPrint("Starting loadMockData...");
    // 1. 메뉴 마스터 강제 선행 로드 (정합성 보장)
    await _loadMenuMaster();

    final String response = await rootBundle.loadString(
      'json/mock_orders.json',
    );
    final data = jsonDecode(response);
    _parseAndSetData(data);
    debugPrint("loadMockData complete. Total orders: ${_orders.length}");
  }

  /// 파일명: loadMockDataFromLocal
  /// 작성의도: json/mock_orders.json 파일에서 대량의 더미 주문 데이터를 로드합니다.
  /// 기능 원리: rootBundle을 통해 로컬 에셋을 읽어오고, 명시적 타입 캐스팅을 통해 List<OrderInfo>로 변환합니다.
  Future<void> loadMockDataFromLocal() async {
    try {
      final String response = await rootBundle.loadString(
        'json/mock_orders.json',
      );

      // 파싱 작업은 Future 기반 비동기로 처리하여 UI 프리징 방지
      final List<dynamic> decoded = await Future.value(jsonDecode(response));

      // 명시적 타입 캐스팅 적용 (List<dynamic> -> List<OrderInfo>)
      final List<OrderInfo> mockOrders = decoded
          .whereType<Map<String, dynamic>>()
          .map((o) {
            final order = OrderInfo.fromJson(o);
            _resolveOrder(order);
            return order;
          })
          .toList();

      _orders.clear();
      _orders.addAll(mockOrders);
      _unreadOrdersCount = _orders.length;

      notifyListeners();
      debugPrint(
        "Successfully loaded ${_orders.length} mock orders from local.",
      );
    } catch (e) {
      debugPrint("Error loading mock data: $e");
    }
  }

  Future<void> updateSettings(String ip, String port) async {
    await connectAndSync(ip, port);
  }

  @override
  void dispose() {
    _cookingTimer?.cancel();
    _wsService.dispose();
    super.dispose();
  }
}
