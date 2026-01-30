import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kitchen_provider.dart';
import '../widgets/menu_card.dart';
import '../widgets/sidebar.dart';
import '../widgets/order_sidebar.dart';
import '../widgets/settings_dialog.dart';

/// 파일명: lib/ui/screens/home_screen.dart
/// 작성의도: 앱의 메인 화면 레이아웃을 정의합니다.
/// 기능 원리: `Scaffold`를 기반으로 상단 바, 좌우측 사이드바, 메인 메뉴 그리드를 배치합니다.
///          `KitchenProvider`를 구독하여 상태 변화에 따라 화면 전체를 반응형으로 렌더링합니다.

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<KitchenProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: _buildAppBar(context, provider),
          drawer: Drawer(
            width: 300,
            child: Sidebar(onShowSettings: () => _showSettings(context)),
          ),
          endDrawer: const Drawer(width: 380, child: OrderSidebar()),
          body: _buildBody(provider),
          floatingActionButton: provider.isSyncing
              ? const FloatingActionButton(
                  onPressed: null,
                  backgroundColor: Colors.blue,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : null,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    KitchenProvider provider,
  ) {
    return AppBar(
      titleSpacing: 0,
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.black87),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
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
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.assignment, color: Colors.blue),
                onPressed: () {
                  provider.resetUnreadCount();
                  Scaffold.of(context).openEndDrawer();
                },
              ),
            ),
            if (provider.unreadOrdersCount > 0)
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
                    "${provider.unreadOrdersCount}",
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
    );
  }

  Widget _buildBody(KitchenProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: const Color(0xFFF3F6F9),
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => provider.setSearchTerm(v),
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
                provider.filterMode == "ORDER"
                    ? "TABLE #${provider.activeTableNo} ORDER"
                    : "MENU LIST",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (provider.filterMode == "ORDER")
                TextButton(
                  onPressed: () => provider.setCategory("전체"),
                  child: const Text("전체 메뉴 보기"),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: provider.filteredMenus.isEmpty
                ? const Center(child: Text("검색 결과가 없습니다."))
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 15,
                          crossAxisSpacing: 15,
                          childAspectRatio: 0.65,
                        ),
                    itemCount: provider.filteredMenus.length,
                    itemBuilder: (context, i) =>
                        MenuCard(menu: provider.filteredMenus[i]),
                  ),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    showDialog(context: context, builder: (context) => const SettingsDialog());
  }
}
