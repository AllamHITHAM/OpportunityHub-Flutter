/// A skill, as returned nested inside an opportunity's `opportunity_skills`
/// relation (`GET /api/opportunities`, `GET /api/opportunities/{id}`) as
/// well as the Admin skill-management endpoints (`GET`/`POST`/`PUT`
/// `/api/admin/skills`).
class SkillModel {
  const SkillModel({
    required this.id,
    required this.name,
    this.category,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? category;

  /// Only populated on responses that include it (the Admin endpoints);
  /// the opportunity-nested `opportunity_skills.skill` shape this model
  /// was originally built for doesn't send it, so it stays `null` there
  /// rather than being required.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SkillModel.fromJson(Map<String, dynamic> json) {
    return SkillModel(
      id: json['id'] as int,
      name: json['name'] as String,
      category: json['category'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
