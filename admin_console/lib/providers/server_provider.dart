/// 작성의도: 서버의 동작 상태 및 연결된 기기 관리를 담당하는 Provider 파일입니다.
/// 기능 원리: 서버 시작/중지 상태, 로그 기록, 연결된 클라이언트 기기 목록, 대기 중인 주문 데이터를 관리하며 UI와 서비스를 매개합니다.

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../models/order_model.dart';
import '../services/server_service.dart';
import '../services/storage_service.dart';
import '../models/menu_model.dart';

class ServerProvider with ChangeNotifier {
  final ServerService _serverService;
  final StorageService _storageService;

  bool _isServerOn = false;
  int? _currentPort;
  String? _statusMessage;
  final List<String> _logs = [];
  final Map<String, DeviceModel> _connectedClientsMap = {};
  Timer? _heartbeatTimer;

  void Function(String orderId)? onOrderDeleted;
  List<MenuModel> Function()? getMenus;
  List<OrderModel> Function()? getOrders;

  ServerProvider(this._serverService, this._storageService) {
    _serverService.onLog = _addLog;
    _serverService.onClientStatusChanged = _updateClientStatus;
    _serverService.onDeleteOrderRequested = _handleDeleteOrder;
  }

  void syncAllData() {
    if (!_isServerOn || getMenus == null || getOrders == null) return;

    final menus = getMenus!();
    final orders = getOrders!();
    final categories = menus.map((m) => m.cat).toSet().toList()..sort();

    final fullData = {
      "type": "KITCHEN_DATA",
      "payload": {
        "menus": menus.map((m) => m.toJson()).toList(),
        "categories": categories,
        "orders": orders
            .where((o) => o.status == OrderStatus.pending)
            .map((o) => o.toJson())
            .toList(),
      },
    };

    _serverService.broadcast(jsonEncode(fullData));
    _addLog("[WS 발송] 전체 데이터(메뉴+주문) 통합 동기화 실행");
  }

  bool get isServerOn => _isServerOn;
  int? get currentPort => _currentPort;
  String? get statusMessage => _statusMessage;
  List<String> get logs => List.unmodifiable(_logs);
  List<DeviceModel> get connectedClients =>
      _connectedClientsMap.values.toList();

  void _addLog(String message) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    _logs.add("[$timeStr] $message");
    if (_logs.length > 100) _logs.removeAt(0);
    notifyListeners();
  }

  void addLog(String message) {
    _addLog(message);
  }

  void _updateClientStatus(String ip, bool isConnected) {
    if (isConnected) {
      if (_connectedClientsMap.containsKey(ip)) {
        _connectedClientsMap[ip] = _connectedClientsMap[ip]!.copyWith(
          isOnline: true,
          lastSeen: DateTime.now(),
        );
      } else {
        _connectedClientsMap[ip] = DeviceModel(
          id: "D-${ip.split('.').last}",
          name: "KDS-Remote",
          ip: ip,
          lastSeen: DateTime.now(),
          isOnline: true,
        );
        _addLog("신규 클라이언트 연결됨: $ip");
      }
    } else {
      if (_connectedClientsMap.containsKey(ip)) {
        _connectedClientsMap.remove(ip);
        _addLog("기기 연결 해제 대기/종료: $ip");
      }
    }
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isServerOn) {
        timer.cancel();
        return;
      }

      // 30초마다 모든 기기에 헬스체크 패킷 발송
      final ping = {
        "type": "PING",
        "payload": {"timestamp": DateTime.now().toIso8601String()},
      };
      _serverService.broadcast(jsonEncode(ping));

      // 세션 관리: 65초 이상 응답 없는 기기 오프라인 처리 (하트비트 2회 주기 + 여유)
      final now = DateTime.now();
      bool changed = false;
      _connectedClientsMap.forEach((ip, device) {
        if (device.isOnline && now.difference(device.lastSeen).inSeconds > 65) {
          _connectedClientsMap[ip] = device.copyWith(isOnline: false);
          changed = true;
          _addLog("세션 타임아웃: $ip (비활동 65초 경과)");
        }
      });

      if (changed) notifyListeners();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleDeleteOrder(String orderId) {
    onOrderDeleted?.call(orderId);
    notifyListeners();
  }

  Future<void> toggleServer(
    List<MenuModel> Function() getMenus,
    List<OrderModel> Function() getOrders,
  ) async {
    if (_isServerOn) {
      await _serverService.stopServer();
      _stopHeartbeat();
      _isServerOn = false;
      _currentPort = null;
      _statusMessage = "서버가 중지되었습니다.";
      _addLog("서버가 종료되었습니다.");
    } else {
      try {
        final port = await _storageService.getServerPort();
        final dataDir = await _storageService.dataDir;

        await _serverService.startServer(
          port: port,
          imagesPath: Directory(pJoin(dataDir.path, 'images')).path,
          getMenus: getMenus,
          getPendingOrders: () => getOrders()
              .where((o) => o.status == OrderStatus.pending)
              .toList(),
          getMockOrders: getOrders,
        );

        _isServerOn = true;
        _currentPort = port;
        _statusMessage = "서버 정상 동작 중 (Port: $port)";
        _addLog("서버가 시작되었습니다. (Port: $port, Binding: 0.0.0.0)");
        _startHeartbeat();
      } catch (e) {
        _statusMessage = "서버 실행 실패: $e";
        _addLog("에러 발생: $e");
        rethrow;
      }
    }
    notifyListeners();
  }

  void broadcastNewOrder(OrderModel order) {
    if (!_isServerOn) return;
    final message = {"type": "ORDER_CREATE", "payload": order.toJson()};
    _serverService.broadcast(jsonEncode(message));
    _addLog("[WS 발송] 신규 주문 브로드캐스팅: ${order.orderId}");
  }

  void broadcastMenuData(List<MenuModel> menus) {
    if (!_isServerOn) return;
    final message = {
      "type": "MENU_DATA",
      "payload": menus.map((m) => m.toJson()).toList(),
    };
    _serverService.broadcast(jsonEncode(message));
    _addLog("[WS 발송] 메뉴 데이터 브로드캐스팅 패킷 전송");
  }

  // path helper (import path as p is used in service, but we need it here if we use join)
  String pJoin(String part1, String part2) =>
      part1 + Platform.pathSeparator + part2;
}
