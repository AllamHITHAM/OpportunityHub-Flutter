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
///
/// Opportunity Academic Matching Cleanup (v1.2): the backend's Field/Major
/// factor, which compared `major` against the deprecated free-text
/// `field_of_study`, was removed from `MatchingService::score()` entirely.
///
/// Recommendation Match: Major Must Contribute to Total Score (v1.3): a
/// new Major/academic-compatibility factor, [majorMatchScore], was added
/// back in its place — computed from the Student's major against the
/// Opportunity's canonical Eligible Majors (never `field_of_study`, which
/// remains unused by any factor). Unlike the removed v1.1 factor, this one
/// is deliberately allowed to overlap with the pre-scoring Eligible Majors
/// eligibility gate (see the backend `MatchingService` doc comment for the
/// full rationale) — it genuinely contributes to [overallMatchScore], so a
/// major-eligible-but-otherwise-unmatched Application no longer bottoms
/// out at a contradictory `0%`.
///
/// Candidate Opportunity Preferences + Final Recommendation Match Formula
/// (v2.0): Experience is completely removed (there is no
/// `experienceMatchScore` any more). [locationMatchScore] joins Skills and
/// Major as a genuine, weighted scoring factor for an On-site/Hybrid
/// Opportunity — `null` for Remote (never considered at all) or an
/// unconfigured On-site/Hybrid one.
class MatchAnalysisModel {
  const MatchAnalysisModel({
    required this.overallMatchScore,
    this.skillsMatchScore,
    this.majorMatchScore,
    this.locationMatchScore,
    this.strengths = const [],
    this.weaknesses = const [],
    this.recommendation,
  });

  final double overallMatchScore;
  final double? skillsMatchScore;

  /// The real, weighted Major/academic-compatibility factor score —
  /// `null` only when the Opportunity has no Eligible Majors configured
  /// (unrestricted — nothing to compare against).
  final double? majorMatchScore;

  /// The real, weighted Location factor score — `null` on a Remote
  /// Opportunity (never considered) or an unconfigured On-site/Hybrid one
  /// (nothing to compare against).
  final double? locationMatchScore;
  final List<String> strengths;
  final List<String> weaknesses;
  final String? recommendation;

  factory MatchAnalysisModel.fromJson(Map<String, dynamic> json) {
    return MatchAnalysisModel(
      overallMatchScore: (json['overall_match_score'] as num).toDouble(),
      skillsMatchScore: _parseNullableScore(json['skills_match_score']),
      majorMatchScore: _parseNullableScore(json['major_match_score']),
      locationMatchScore: _parseNullableScore(json['location_match_score']),
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
