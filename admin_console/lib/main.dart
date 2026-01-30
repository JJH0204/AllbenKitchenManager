/**
 * 작성의도: 애플리케이션의 진입점이자 최상위 위젯 관리 파일입니다.
 * 기능 원리: 서비스 및 Provider를 초기화하고, 화면 레이아웃(사이드바, 헤더, 메인 컨텐츠)을 구성하며 전체 앱의 상태 흐름을 제어합니다.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/server_service.dart';
import 'providers/menu_provider.dart';
import 'providers/server_provider.dart';
import 'providers/order_provider.dart';
import 'ui/widgets/sidebar.dart';
import 'ui/widgets/header.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/menu_management_screen.dart';
import 'ui/screens/orders_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() {
  final storageService = StorageService();
  final serverService = ServerService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => MenuProvider(storageService)..loadMenus(),
        ),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProxyProvider2<
          MenuProvider,
          OrderProvider,
          ServerProvider
        >(
          create: (_) => ServerProvider(serverService, storageService),
          update: (_, menuProvider, orderProvider, serverProvider) {
            serverProvider!..onOrderDeleted = orderProvider.removeOrder;
            serverProvider.getMenus = () => menuProvider.menus;
            serverProvider.getOrders = () => orderProvider.orders;

            // 메뉴 변경 시 전체 기기 동기화 알림 (KITCHEN_DATA)
            menuProvider.onMenuChanged = (_) => serverProvider.syncAllData();
            // 메뉴 에러 발생 시 서버 로그에 출력
            menuProvider.onLogError = serverProvider.addLog;

            return serverProvider;
          },
        ),
      ],
      child: const AdminApp(),
    ),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Allben Kitchen Admin',
      theme: ThemeData(fontFamily: 'Pretendard', primarySwatch: Colors.blue),
      home: const AdminServerPage(),
    );
  }
}

class AdminServerPage extends StatefulWidget {
  const AdminServerPage({super.key});

  @override
  State<AdminServerPage> createState() => _AdminServerPageState();
}

class _AdminServerPageState extends State<AdminServerPage> {
  String activeTab = "menu";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      body: Row(
        children: [
          // 1. Sidebar
          AdminSidebar(
            activeTab: activeTab,
            onTabChanged: (tab) => setState(() => activeTab = tab),
          ),

          // 2. Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                children: [
                  AdminHeader(activeTab: activeTab),
                  const SizedBox(height: 32),
                  Expanded(child: _buildActiveContent()),
                  const StatusBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveContent() {
    switch (activeTab) {
      case "dashboard":
        return const DashboardScreen();
      case "menu":
        return const MenuManagementScreen();
      case "orders":
        return const OrdersScreen();
      case "settings":
        return const SettingsScreen();
      default:
        return const Center(child: Text("Page Not Found"));
    }
  }
}

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, child) {
        final statusMessage = serverProvider.statusMessage;
        if (statusMessage == null) return const SizedBox.shrink();

        final isOn = serverProvider.isServerOn;
        return Container(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isOn
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOn
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isOn ? Icons.check_circle : Icons.error_outline,
                color: isOn ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                statusMessage,
                style: TextStyle(
                  color: isOn ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
