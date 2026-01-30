/**
 * 작성의도: 메뉴 데이터를 정의하는 데이터 모델 파일입니다.
 * 기능 원리: JSON 직렬화 및 역직렬화를 지원하며, 메뉴의 ID, 이름, 카테고리, 조리 시간, 레시피, 이미지 경로 등을 저장합니다.
 */

class MenuModel {
  String id;
  String name;
  String cat;
  int time;
  String recipe;
  String image; // 파일명 또는 URL

  MenuModel({
    required this.id,
    required this.name,
    this.cat = "분류 없음",
    this.time = 0,
    this.recipe = "",
    this.image = "",
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "name": name,
    "cat": cat,
    "time": time,
    "recipe": recipe,
    "image": image,
  };

  factory MenuModel.fromJson(Map<String, dynamic> json) => MenuModel(
    id: json["id"] ?? "",
    name: json["name"] ?? "",
    cat: json["cat"] ?? "분류 없음",
    time: json["time"] ?? 0,
    recipe: json["recipe"] ?? "",
    image: json["image"] ?? "",
  );
}
