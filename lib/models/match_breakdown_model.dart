/// A deterministic "why this score" breakdown for one Recommended
/// Candidates row (Recommendation Accuracy Patch, extended by the Matching
/// Formula Audit, tightened by the Opportunity Academic Matching Cleanup,
/// extended by "Recommendation Match: Major Must Contribute to Total
/// Score", and again by "Candidate Opportunity Preferences + Final
/// Recommendation Match Formula") — built entirely from real,
/// already-computed `MatchingService`/`OpportunityEligibilityService`
/// inputs, never a fabricated or AI-generated explanation, and never a
/// second scoring formula. Every candidate in the parent list already
/// passed Opportunity Type interest, Major, and Location eligibility, so
/// [majorEligibility] is always `'eligible'` and [locationEligibility] is
/// never a rejection state.
///
/// **v2.0 — Final Recommendation Match Formula**: Experience is completely
/// removed (there is no `experienceMatch`/`experienceMatchScore` any
/// more). Location joins Skills and Major as a genuine, weighted scoring
/// factor for On-site/Hybrid Opportunities — [locationMatchScore] — and is
/// never computed at all for Remote (`null`, [locationWeight]/
/// [locationContribution] also `null`, never a phantom `0`).
///
/// Every `*Contribution`/`*Weight` pair here is already expressed in the
/// exact points that sum to [RecommendedCandidateModel.matchScore]/
/// `match_score` — this app never multiplies a raw factor score by a
/// weight itself; it only ever displays the numbers the backend already
/// computed, so a "Why X%?" breakdown can never show a number that fails
/// to add up to the displayed total.
class MatchBreakdownModel {
  const MatchBreakdownModel({
    required this.majorEligibility,
    required this.academicMatch,
    this.majorMatchScore,
    this.majorWeight,
    this.majorContribution,
    required this.requiredSkillsTotal,
    required this.requiredSkillsMatched,
    required this.matchedRequiredSkills,
    required this.missingRequiredSkills,
    this.skillsMatchScore,
    this.skillsWeight,
    this.skillsContribution,
    required this.locationEligibility,
    this.locationMatchScore,
    this.locationWeight,
    this.locationContribution,
  });

  /// Always `'eligible'` today — every listed candidate already passed
  /// `OpportunityEligibilityService::isStudentEligible()`. The
  /// eligibility *gate*, never itself a score input — see [academicMatch]
  /// for the real, weighted scoring factor built from the same canonical
  /// data.
  final String majorEligibility;

  /// The real `MatchingService::analyzeMajor()` factor status — one of
  /// `'not_applicable'` (the Opportunity has no Eligible Majors
  /// configured — unrestricted, nothing to compare against),
  /// `'matched'`, or `'not_matched'` (defensive/rare on Recommended
  /// Candidates — reachable only for a stale Application Match Analysis
  /// recalculated after the Student's major changed post-submission).
  final String academicMatch;

  /// The real, weighted Major/academic-compatibility factor score — `null`
  /// exactly when [academicMatch] is `'not_applicable'`.
  final double? majorMatchScore;

  /// The real weight (out of 100, e.g. `25` on-site/hybrid or `30`
  /// remote) this factor was scored against for this candidate — `null`
  /// only when [majorMatchScore] is `null`.
  final int? majorWeight;

  /// The real points this factor contributed to [majorMatchScore]'s share
  /// of the overall Match — already weighted, never something this app
  /// computes itself.
  final double? majorContribution;

  final int requiredSkillsTotal;
  final int requiredSkillsMatched;
  final List<String> matchedRequiredSkills;
  final List<String> missingRequiredSkills;

  /// The real, weighted Skills factor score — `null` only when the
  /// Opportunity has zero Required/Preferred Skills configured (nothing
  /// to score against), matching [requiredSkillsTotal] being 0.
  final double? skillsMatchScore;

  /// The real weight (out of 100, e.g. `60` on-site/hybrid or `70`
  /// remote) — `null` only when [skillsMatchScore] is `null`.
  final int? skillsWeight;

  /// The real points Skills contributed to the overall Match.
  final double? skillsContribution;

  /// One of:
  /// - `'not_considered'`: the Opportunity is Remote — location is never
  ///   consulted at all.
  /// - `'unrestricted'`: On-site/Hybrid, but this Opportunity has no
  ///   canonical location set — nothing was compared against.
  /// - `'matched'`: On-site/Hybrid with a real location — this candidate's
  ///   Available Work Locations genuinely includes it.
  final String locationEligibility;

  /// The real, weighted Location factor score — `null` for Remote
  /// ([locationEligibility] `'not_considered'`) or an unconfigured
  /// On-site/Hybrid Opportunity ([locationEligibility] `'unrestricted'`).
  final double? locationMatchScore;

  /// The real weight (`15` on-site/hybrid when scoreable) — always `null`
  /// on Remote, since Location never enters the formula there at all.
  final int? locationWeight;

  /// The real points Location contributed to the overall Match — always
  /// `null` on Remote, never a phantom `0`.
  final double? locationContribution;

  factory MatchBreakdownModel.fromJson(Map<String, dynamic> json) {
    final matchedJson = json['matched_required_skills'] as List? ?? const [];
    final missingJson = json['missing_required_skills'] as List? ?? const [];

    return MatchBreakdownModel(
      majorEligibility: json['major_eligibility'] as String? ?? 'eligible',
      academicMatch: json['academic_match'] as String? ?? 'not_applicable',
      majorMatchScore: (json['major_match_score'] as num?)?.toDouble(),
      majorWeight: json['major_weight'] as int?,
      majorContribution: (json['major_contribution'] as num?)?.toDouble(),
      requiredSkillsTotal: json['required_skills_total'] as int? ?? 0,
      requiredSkillsMatched: json['required_skills_matched'] as int? ?? 0,
      matchedRequiredSkills: matchedJson.map((s) => s as String).toList(),
      missingRequiredSkills: missingJson.map((s) => s as String).toList(),
      skillsMatchScore: (json['skills_match_score'] as num?)?.toDouble(),
      skillsWeight: json['skills_weight'] as int?,
      skillsContribution: (json['skills_contribution'] as num?)?.toDouble(),
      locationEligibility:
          json['location_eligibility'] as String? ?? 'not_considered',
      locationMatchScore: (json['location_match_score'] as num?)?.toDouble(),
      locationWeight: json['location_weight'] as int?,
      locationContribution: (json['location_contribution'] as num?)
          ?.toDouble(),
    );
  }
}
