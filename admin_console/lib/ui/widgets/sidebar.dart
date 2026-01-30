/**
 * 작성의도: 관리자 콘솔의 사이드바 내비게이션 위젯입니다.
 * 기능 원리: 대시보드, 메뉴 관리, 주문 내역, 설정 등의 탭 이동 기능을 제공하며 서버의 현재 상태를 시각적으로 표시합니다.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/server_provider.dart';

class AdminSidebar extends StatelessWidget {
  final String activeTab;
  final Function(String) onTabChanged;

  const AdminSidebar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: const Color(0xFF1A1F2E),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ADMIN CONSOLE",
            style: TextStyle(
              color: Colors.blueAccent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
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
          const ServerStatusCard(),
        ],
      ),
    );
  }

  Widget _sidebarButton(String id, String icon, String label) {
    bool isActive = activeTab == id;
    return InkWell(
      onTap: () => onTabChanged(id),
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
}

class ServerStatusCard extends StatelessWidget {
  const ServerStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, child) {
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
                      color: serverProvider.isServerOn
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                serverProvider.isServerOn
                    ? "RUNNING: ${serverProvider.currentPort}"
                    : "STOPPED",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
