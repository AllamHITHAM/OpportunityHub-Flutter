/// A pending Skill catalog suggestion for Admin review (Phase 8A-6.1), as
/// returned by `GET /api/admin/skill-suggestions`. Only ever pending --
/// see `AdminSkillSuggestionsRepository` for approve/reject.
class SkillSuggestionModel {
  const SkillSuggestionModel({
    required this.id,
    required this.name,
    required this.source,
    required this.status,
  });

  final int id;
  final String name;

  /// Currently only ever `ai_cv` -- the schema also allows `student`/
  /// `organization` for future use, but nothing creates those yet.
  final String source;

  /// `pending`, `approved`, or `rejected` -- the list endpoint only ever
  /// returns `pending` rows, but this stays a plain string rather than an
  /// assumed-pending flag so a stale local copy can't misrepresent one
  /// that was reviewed elsewhere.
  final String status;

  factory SkillSuggestionModel.fromJson(Map<String, dynamic> json) {
    return SkillSuggestionModel(
      id: json['id'] as int,
      name: json['name'] as String,
      source: json['source'] as String,
      status: json['status'] as String,
    );
  }
}
