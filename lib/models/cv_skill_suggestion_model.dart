/// A single AI-suggested skill returned by
/// `POST /api/student/cvs/{cv}/extract-skills` (Phase 8A-6, extended by
/// Phase 8A-6.1 with catalog-suggestion fields).
///
/// Suggestion only -- the AI never mutates the student's skills on its
/// own. Accepting a suggestion is a separate, explicit action that goes
/// through the existing Student Skill endpoint
/// (`StudentSkillRepository.addSkill`), never this model.
class CvSkillSuggestion {
  const CvSkillSuggestion({
    required this.name,
    required this.confidence,
    required this.skillId,
    required this.isAvailable,
    required this.alreadyAdded,
    this.suggestionId,
    this.suggestionStatus,
  });

  final String name;

  /// 0.0-1.0, how directly the CV text supports this skill.
  final double confidence;

  /// Null when the AI-suggested name doesn't match any skill in the
  /// existing Admin-owned catalog -- see [isAvailable].
  final int? skillId;

  /// True only when [skillId] resolves to an existing catalog Skill. A
  /// suggestion with `isAvailable == false` can never be selected for
  /// "Add Selected Skills" -- the UI must disable it, never auto-create a
  /// Skill record.
  final bool isAvailable;

  /// True when the student already has this skill -- prevents offering a
  /// duplicate-add selection.
  final bool alreadyAdded;

  /// Phase 8A-6.1: non-null only when [isAvailable] is false -- the
  /// pending (or, in principle, since-reviewed) `SkillSuggestion` id this
  /// name resolved to. Never itself addable; shown so the student
  /// understands the name is awaiting Admin review rather than simply
  /// unsupported.
  final int? suggestionId;

  /// Phase 8A-6.1: `pending` in every case this endpoint can actually
  /// return today (see `AiSkillExtractionService::mapToCatalog` -- an
  /// approved suggestion always becomes a direct catalog match instead,
  /// and a rejected one is re-raised as a fresh pending suggestion rather
  /// than ever being returned as `rejected`). Kept as a plain nullable
  /// string rather than a bool so the UI reflects exactly what the
  /// backend says instead of assuming a single fixed meaning.
  final String? suggestionStatus;

  factory CvSkillSuggestion.fromJson(Map<String, dynamic> json) {
    return CvSkillSuggestion(
      name: json['name'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      skillId: json['skill_id'] as int?,
      isAvailable: json['is_available'] as bool,
      alreadyAdded: json['already_added'] as bool,
      suggestionId: json['suggestion_id'] as int?,
      suggestionStatus: json['suggestion_status'] as String?,
    );
  }

  CvSkillSuggestion copyWith({bool? alreadyAdded}) {
    return CvSkillSuggestion(
      name: name,
      confidence: confidence,
      skillId: skillId,
      isAvailable: isAvailable,
      alreadyAdded: alreadyAdded ?? this.alreadyAdded,
      suggestionId: suggestionId,
      suggestionStatus: suggestionStatus,
    );
  }
}
