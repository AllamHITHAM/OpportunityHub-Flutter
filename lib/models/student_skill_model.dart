/// A Student's own skill, as returned by `GET /api/student/skills` and
/// nested under `student_profile.student_skills` on every
/// organization-facing Application response (Phase 8A-6.1).
///
/// [source] is the evidence behind the skill -- `manual` (the student
/// declared it themselves) or `cv_ai` (accepted from an AI CV suggestion,
/// backend-verified against real extraction evidence before it could ever
/// be stored). `cv_ai` is shown as "CV-supported", never "Verified" --
/// it means the CV text supports the skill, not that proficiency was
/// independently confirmed. See docs/BUSINESS_RULES.md.
class StudentSkillModel {
  const StudentSkillModel({
    required this.id,
    required this.skillId,
    required this.skillName,
    this.category,
    required this.level,
    this.yearsOfExperience,
    required this.source,
  });

  final int id;
  final int skillId;
  final String skillName;

  /// The catalog `Skill`'s own discipline label (e.g. "Civil Engineering",
  /// "Computer Science") -- a real, Admin-set/seeded column
  /// (`BaselineSkillSeeder`), not a client-invented taxonomy. Nullable: an
  /// Admin-created or suggestion-approved `Skill` may not have one set.
  final String? category;

  /// One of: beginner, intermediate, advanced, expert.
  final String level;
  final double? yearsOfExperience;

  /// `manual` or `cv_ai`.
  final String source;

  bool get isCvSupported => source == 'cv_ai';

  /// The user-facing evidence label -- "CV-supported" or "Self-declared".
  /// Deliberately never "Verified": see this class's own doc comment.
  String get evidenceLabel => isCvSupported ? 'CV-supported' : 'Self-declared';

  factory StudentSkillModel.fromJson(Map<String, dynamic> json) {
    final skillJson = json['skill'] as Map<String, dynamic>;

    return StudentSkillModel(
      id: json['id'] as int,
      skillId: skillJson['id'] as int,
      skillName: skillJson['name'] as String,
      category: skillJson['category'] as String?,
      level: json['level'] as String,
      yearsOfExperience: _parseDecimal(json['years_of_experience']),
      source: json['source'] as String? ?? 'manual',
    );
  }

  static double? _parseDecimal(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
