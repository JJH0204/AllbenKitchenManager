import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kitchen_provider.dart';

/// 파일명: lib/ui/widgets/sidebar.dart
/// 작성의도: 앱의 좌측 메뉴(Drawer)를 구성하며 카테고리 선택 및 설정 접근을 제공합니다.
/// 기능 원리: `KitchenProvider`의 카테고리 목록을 로드하여 표시하고,
///          각 리스트 아이템 클릭 시 선택된 카테고리를 업데이트하여 메인 그리드를 제어합니다.

class Sidebar extends StatelessWidget {
  final VoidCallback onShowSettings;

  const Sidebar({super.key, required this.onShowSettings});

  @override
  Widget build(BuildContext context) {
    return Consumer<KitchenProvider>(
      builder: (context, provider, child) {
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
                  itemCount: provider.categories.length,
                  itemBuilder: (context, i) {
                    final category = provider.categories[i];
                    bool isActive =
                        provider.filterMode == "CATEGORY" &&
                        provider.selectedCategory == category;
                    return ListTile(
                      selected: isActive,
                      selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: Text(
                        category,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.blue : Colors.black54,
                        ),
                      ),
                      trailing: isActive
                          ? const Icon(Icons.chevron_right, color: Colors.blue)
                          : null,
                      onTap: () {
                        provider.setCategory(category);
                        Navigator.pop(context); // 사이드바 닫기
                      },
                    );
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.grey),
                title: const Text(
                  "서버 설정",
                  style: TextStyle(color: Colors.black54),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onShowSettings();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
