/// 파일명: lib/models/menu_info.dart
/// 작성의도: 메뉴 정보를 저장하기 위한 데이터 모델 클래스입니다.
/// 기능 원리: 메뉴 이름, 카테고리, 조리 시간, 레시피, 이미지 URL 등을 속성으로 가지며,
///          서버로부터 받은 JSON 데이터를 객체화하거나 UI에서 활용하기 위한 데이터 구조를 정의합니다.

class MenuInfo {
  final String id;
  final String name, cat, recipe, imageUrl;
  final int cookTime;

  MenuInfo({
    required this.id,
    required this.name,
    required this.cat,
    required this.cookTime,
    required this.recipe,
    this.imageUrl = "",
  });

  factory MenuInfo.fromJson(Map<String, dynamic> json) {
    return MenuInfo(
      id: (json['id'] ?? "").toString(),
      name: (json['name'] ?? "").toString(),
      cat: (json['cat'] ?? json['category'] ?? "").toString(),
      cookTime:
          int.tryParse(
            json['cookTime']?.toString() ?? json['time']?.toString() ?? "0",
          ) ??
          0,
      recipe: (json['recipe'] ?? "").toString(),
      imageUrl: (json['image'] ?? json['imageUrl'] ?? "").toString(),
    );
  }
}
