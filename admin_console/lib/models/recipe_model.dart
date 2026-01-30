/**
 * 작성의도: 메뉴별 레시피 정보를 정의하는 데이터 모델 파일입니다.
 * 기능 원리: 요리 단계, 주재료 정보 등을 구조화하여 관리하며, 향후 주방 HUD에서 단계별 가이드를 제공할 수 있는 기반이 됩니다.
 */

class RecipeModel {
  final String menuId;
  final List<String> steps;
  final List<String> ingredients;

  RecipeModel({
    required this.menuId,
    required this.steps,
    this.ingredients = const [],
  });

  Map<String, dynamic> toJson() => {
    "menuId": menuId,
    "steps": steps,
    "ingredients": ingredients,
  };

  factory RecipeModel.fromJson(Map<String, dynamic> json) => RecipeModel(
    menuId: json["menuId"] ?? "",
    steps: List<String>.from(json["steps"] ?? []),
    ingredients: List<String>.from(json["ingredients"] ?? []),
  );
}
