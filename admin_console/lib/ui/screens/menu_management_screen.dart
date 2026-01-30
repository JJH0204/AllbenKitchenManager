/**
 * 작성의도: 메뉴 목록을 관리하고 편집할 수 있는 화면 위젯입니다.
 * 기능 원리: MenuProvider와 연결되어 실시간으로 메뉴 데이터를 테이블 형식으로 표시하며, 추가, 수정, 삭제 및 이미지 변경 기능을 제공합니다.
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../models/menu_model.dart';
import '../../providers/menu_provider.dart';
import '../../providers/server_provider.dart';

class MenuManagementScreen extends StatelessWidget {
  const MenuManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MenuProvider, ServerProvider>(
      builder: (context, menuProvider, serverProvider, child) {
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => menuProvider.refreshMenuData(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text("DB 초기화/새로고침"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade50,
                            foregroundColor: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () => _addMenu(context, menuProvider),
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
                      rows: menuProvider.menus
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.network(
                                              "http://localhost:${serverProvider.currentPort ?? 8080}/images/${m.image}",
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) =>
                                                  const Icon(
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
                                        onPressed: () => _openEditModal(
                                          context,
                                          menuProvider,
                                          serverProvider,
                                          m,
                                        ),
                                        child: const Text("수정"),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            menuProvider.deleteMenu(m.id),
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
      },
    );
  }

  void _addMenu(BuildContext context, MenuProvider menuProvider) {
    final newId =
        "M${(menuProvider.menus.length + 1).toString().padLeft(3, '0')}";
    final newMenu = MenuModel(
      id: newId,
      name: "새 메뉴",
      cat: "기타",
      time: 0,
      recipe: "",
      image: "",
    );
    _openEditModal(
      context,
      menuProvider,
      Provider.of<ServerProvider>(context, listen: false),
      newMenu,
      isNew: true,
    );
  }

  void _openEditModal(
    BuildContext context,
    MenuProvider menuProvider,
    ServerProvider serverProvider,
    MenuModel menu, {
    bool isNew = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => _MenuDetailEditor(
        menu: menu,
        currentPort: serverProvider.currentPort ?? 8080,
        onPickImage: () async {
          final ImagePicker picker = ImagePicker();
          final XFile? image = await picker.pickImage(
            source: ImageSource.gallery,
          );
          if (image != null) {
            await menuProvider.updateMenuImage(menu.id, File(image.path));
            if (context.mounted) (context as Element).markNeedsBuild();
          }
        },
        onSave: (updated) async {
          if (isNew) {
            await menuProvider.addMenu(updated);
          } else {
            await menuProvider.updateMenu(updated);
          }
          if (context.mounted) Navigator.pop(context);
        },
      ),
    );
  }
}

class _MenuDetailEditor extends StatefulWidget {
  final MenuModel menu;
  final int currentPort;
  final VoidCallback onPickImage;
  final Function(MenuModel) onSave;

  const _MenuDetailEditor({
    required this.menu,
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
                        MenuModel(
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
