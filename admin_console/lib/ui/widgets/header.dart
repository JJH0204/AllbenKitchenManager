/// 작성의도: 관리자 콘솔 상단의 헤더 위젯입니다.
/// 기능 원리: 현재 탭의 제목을 표시하고, 서버를 즉시 시작하거나 중지할 수 있는 버튼 기능을 제공합니다.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/menu_provider.dart';
import '../../providers/order_provider.dart';

class AdminHeader extends StatelessWidget {
  final String activeTab;

  const AdminHeader({super.key, required this.activeTab});

  @override
  Widget build(BuildContext context) {
    return Consumer3<ServerProvider, MenuProvider, OrderProvider>(
      builder: (context, serverProvider, menuProvider, orderProvider, child) {
        return Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeTab == "dashboard"
                      ? "SERVER DASHBOARD"
                      : "DATA MANAGEMENT",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  serverProvider.isServerOn
                      ? "Host: 0.0.0.0:${serverProvider.currentPort} | Active"
                      : "Server Offline | Last Sync: 2026-01-29",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (serverProvider.isServerOn) ...[
              _buildHeaderButton(
                label: "전체 기기 동기화",
                icon: Icons.sync,
                color: const Color(0xFFE3F2FD),
                textColor: Colors.blue,
                onPressed: () => serverProvider.syncAllData(),
              ),
              const SizedBox(width: 12),
              _buildHeaderButton(
                label: "테스트 오더 생성",
                icon: Icons.shopping_cart_checkout,
                color: Colors.orange,
                textColor: Colors.white,
                onPressed: () {
                  final testOrder = orderProvider.generateTestOrder(
                    menuProvider.menus,
                  );
                  orderProvider.addOrder(testOrder);
                  serverProvider.broadcastNewOrder(testOrder);
                },
              ),
              const SizedBox(width: 12),
            ],
            _buildHeaderButton(
              label: serverProvider.isServerOn ? "SERVER STOP" : "SERVER START",
              icon: serverProvider.isServerOn ? Icons.stop : Icons.play_arrow,
              color: serverProvider.isServerOn
                  ? Colors.redAccent
                  : Colors.green,
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await serverProvider.toggleServer(
                    () => menuProvider.menus,
                    () => orderProvider.orders,
                  );
                } catch (e) {
                  if (context.mounted) {
                    _showErrorDialog(context, "서버 오류", e.toString());
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    required Color textColor,
    IconData? icon,
  }) {
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: textColor,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
    );

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: buttonStyle,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  void _showErrorDialog(BuildContext context, String title, String message) {
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
}
