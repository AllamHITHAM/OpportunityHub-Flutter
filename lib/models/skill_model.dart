/// A skill, as returned nested inside an opportunity's `opportunity_skills`
/// relation (`GET /api/opportunities`, `GET /api/opportunities/{id}`).
class SkillModel {
  const SkillModel({required this.id, required this.name, this.category});

  final int id;
  final String name;
  final String? category;

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    return SkillModel(
      id: json['id'] as int,
      name: json['name'] as String,
      category: json['category'] as String?,
    );
  }
}
