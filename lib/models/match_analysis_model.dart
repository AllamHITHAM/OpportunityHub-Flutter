/// The rule-based match analysis breakdown for one `Application`, as
/// returned by both `POST /organization/applications/{id}/analyze` and
/// `GET /organization/applications/{id}/analysis` (both wrap the backend's
/// `MatchingService::analyze()`, so they share the exact same shape — see
/// docs/API.md section 8 on the backend).
///
/// [overallMatchScore] is always present (the backend never returns a
/// `null` overall score from either endpoint — an application with
/// literally nothing scoreable still gets a real, calculated `0.0`, not a
/// missing value). Each individual factor score, by contrast, is `null`
/// whenever the backend genuinely couldn't score it (e.g. no student major
/// recorded, or the opportunity has no skills listed) — this is
/// deliberately never coerced to `0`, since the backend distinguishes
/// "scored zero" from "not scoreable" and this model must preserve that
/// distinction for the UI to render "Not available" rather than a
/// misleading 0%.
///
/// There is no education/location/work-mode field — the backend's v1.1
/// formula (Phase 8A-2) has none.
class MatchAnalysisModel {
  const MatchAnalysisModel({
    required this.overallMatchScore,
    this.skillsMatchScore,
    this.fieldMatchScore,
    this.experienceMatchScore,
    this.strengths = const [],
    this.weaknesses = const [],
    this.recommendation,
  });

  final double overallMatchScore;
  final double? skillsMatchScore;
  final double? fieldMatchScore;
  final double? experienceMatchScore;
  final List<String> strengths;
  final List<String> weaknesses;
  final String? recommendation;

  factory MatchAnalysisModel.fromJson(Map<String, dynamic> json) {
    return MatchAnalysisModel(
      overallMatchScore: (json['overall_match_score'] as num).toDouble(),
      skillsMatchScore: _parseNullableScore(json['skills_match_score']),
      fieldMatchScore: _parseNullableScore(json['field_match_score']),
      experienceMatchScore: _parseNullableScore(json['experience_match_score']),
      strengths: _parseStringList(json['strengths']),
      weaknesses: _parseStringList(json['weaknesses']),
      recommendation: json['recommendation'] as String?,
    );
  }

  static double? _parseNullableScore(dynamic value) {
    if (value == null) return null;
    return (value as num).toDouble();
  }

  /// Never throws on a missing/malformed list — an unexpected shape here
  /// (not a list, or a list containing non-string entries) degrades to an
  /// empty/filtered list rather than taking down the whole analysis parse,
  /// since strengths/weaknesses are supplementary display data, not a
  /// structural field.
  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }
}
