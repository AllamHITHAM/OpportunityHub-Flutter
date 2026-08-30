import 'candidate_skill_model.dart';
import 'location_model.dart';
import 'match_breakdown_model.dart';

/// One ranked result row from
/// `GET /api/organization/opportunities/{opportunity}/recommended-candidates`
/// (Phase O8.1) — the real, eligible Student candidates for one specific
/// Opportunity, ordered by the same match formula an [ApplicationModel]
/// would later be scored with (see backend `MatchingService::scoreCandidate()`),
/// computed live without ever creating a throwaway Application.
///
/// Deliberately a separate model from [CandidateModel] (the Talent
/// Directory's own, simpler shape) rather than extending it — this one
/// carries real match-score/factor data and this-Opportunity relationship
/// state that only ever exists in a recommendations context, and
/// [CandidateModel] must stay exactly as narrow as the plain candidate
/// browse endpoint it represents.
class RecommendedCandidateModel {
  const RecommendedCandidateModel({
    required this.id,
    required this.name,
    required this.university,
    required this.major,
    required this.graduationYear,
    required this.bio,
    required this.educationVerificationStatus,
    required this.currentLocation,
    required this.availableLocations,
    required this.skills,
    this.photoUrl,
    required this.matchScore,
    this.skillsMatchScore,
    this.majorMatchScore,
    this.locationMatchScore,
    required this.alreadyApplied,
    this.applicationId,
    this.phone,
    this.email,
    this.invitationStatus,
    this.matchBreakdown,
  });

  /// The candidate's `student_profiles.id` — what
  /// `POST /organization/invitations` expects as `student_id`.
  final int id;

  final String name;
  final String? university;
  final String? major;
  final int? graduationYear;
  final String? bio;

  /// `not_submitted`, `pending`, `verified`, or `rejected`.
  final String educationVerificationStatus;

  /// The Student's own current/home Location -- `null` when not set.
  final LocationModel? currentLocation;

  /// The Student's own selected available/preferred work Locations --
  /// empty (never `null`) when none are configured.
  final List<LocationModel> availableLocations;

  final List<CandidateSkillModel> skills;

  /// Student Profile Photo: the candidate's uploaded profile photo, if
  /// any -- `null` keeps the existing initials-avatar fallback rendering.
  final String? photoUrl;

  /// The same deterministic 0-100 overall match score
  /// `MatchingService::scoreCandidate()` computes — never a fabricated or
  /// estimated number, and never a misleading `0` for "not computed" (this
  /// endpoint only ever returns a genuinely computed score for every real
  /// candidate it lists).
  final double matchScore;

  /// Factor breakdown — `null` exactly when the corresponding backend
  /// factor was itself unavailable for this candidate/opportunity pair
  /// (e.g. no skills configured, or the Opportunity has no Eligible
  /// Majors configured for [majorMatchScore]), matching
  /// [ApplicationModel]'s own Match Analysis breakdown semantics. Never
  /// displayed as a fake `0%`.
  ///
  /// There is no `experienceMatchScore` any more (Final Recommendation
  /// Match Formula) — Experience was removed from the formula entirely.
  final double? skillsMatchScore;

  /// The real, weighted Major/academic-compatibility factor score —
  /// computed from the Student's major against the Opportunity's
  /// canonical Eligible Majors, never the deprecated `field_of_study`.
  /// `null` when the Opportunity has no Eligible Majors configured
  /// (unrestricted — nothing to compare against).
  final double? majorMatchScore;

  /// The real, weighted Location factor score (Candidate Opportunity
  /// Preferences + Final Recommendation Match Formula) — `null` on a
  /// Remote Opportunity (Location is never considered at all) or an
  /// unconfigured On-site/Hybrid one (nothing to compare against).
  final double? locationMatchScore;

  /// True once this candidate has a real [ApplicationModel] for this
  /// Opportunity (via either the direct Apply flow or having accepted an
  /// Invitation and then applied).
  final bool alreadyApplied;

  /// The real Application ID to navigate to when [alreadyApplied] — `null`
  /// whenever [alreadyApplied] is false.
  final int? applicationId;

  /// Only ever present alongside a real [applicationId] (Organization
  /// Candidate Profile Enrichment) — the same application_id-gated
  /// contact rule [CandidateModel] uses, `null` for every candidate here
  /// who hasn't applied yet, even though every one of them is otherwise a
  /// real, eligible recommendation.
  final String? phone;
  final String? email;

  /// `null` (never invited), or the real `invitations.status` value:
  /// `pending`, `accepted`, or `declined`.
  final String? invitationStatus;

  /// The deterministic "why this score" breakdown (Recommendation Accuracy
  /// Patch) — `null` only against a stale/legacy cached response that
  /// predates this field; a live load always includes it.
  final MatchBreakdownModel? matchBreakdown;

  factory RecommendedCandidateModel.fromJson(Map<String, dynamic> json) {
    final skillsJson = json['skills'] as List? ?? const [];
    final matchBreakdownJson = json['match_breakdown'];
    final currentLocationJson = json['current_location'];
    final availableLocationsJson = json['available_locations'] as List? ?? const [];

    return RecommendedCandidateModel(
      id: json['id'] as int,
      name: json['name'] as String,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
      bio: json['bio'] as String?,
      educationVerificationStatus:
          json['education_verification_status'] as String? ?? 'not_submitted',
      currentLocation: currentLocationJson is Map<String, dynamic>
          ? LocationModel.fromJson(currentLocationJson)
          : null,
      availableLocations: availableLocationsJson
          .map((l) => LocationModel.fromJson(l as Map<String, dynamic>))
          .toList(),
      skills: skillsJson
          .map((s) => CandidateSkillModel.fromJson(s as Map<String, dynamic>))
          .toList(),
      photoUrl: json['profile_photo_url'] as String?,
      matchScore: (json['match_score'] as num).toDouble(),
      skillsMatchScore: (json['skills_match_score'] as num?)?.toDouble(),
      majorMatchScore: (json['major_match_score'] as num?)?.toDouble(),
      locationMatchScore: (json['location_match_score'] as num?)?.toDouble(),
      alreadyApplied: json['already_applied'] as bool? ?? false,
      applicationId: json['application_id'] as int?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      invitationStatus: json['invitation_status'] as String?,
      matchBreakdown: matchBreakdownJson is Map<String, dynamic>
          ? MatchBreakdownModel.fromJson(matchBreakdownJson)
          : null,
    );
  }
}

/// The full response shape of
/// `GET /organization/opportunities/{opportunity}/recommended-candidates`
/// (Phase O8.2) — the ranked [candidates] plus the real Opportunity context
/// (`work_mode`, and its canonical [locationName] when one is set) needed
/// to render a truthful explanation of what was actually filtered/ranked.
/// [workMode] in particular is what stops the UI from ever claiming
/// location was considered for a Remote opportunity.
class RecommendedCandidatesResult {
  const RecommendedCandidatesResult({
    required this.workMode,
    required this.opportunityType,
    required this.locationName,
    required this.candidates,
  });

  /// One of: remote, hybrid, onsite.
  final String workMode;

  /// The canonical Opportunity Type (`job`/`internship`/`volunteer`/
  /// `scholarship`/`competition`) — the same value every listed candidate
  /// already has in their own `interested_in` preference (Candidate
  /// Opportunity Preferences patch), used to render real, dynamic "these
  /// candidates are interested in X opportunities" copy.
  final String opportunityType;

  /// The Opportunity's canonical location name, or `null` when it has none
  /// set (a Remote Opportunity, or a historical/unconfigured On-site or
  /// Hybrid one).
  final String? locationName;

  final List<RecommendedCandidateModel> candidates;

  factory RecommendedCandidatesResult.fromJson(Map<String, dynamic> json) {
    final opportunityJson = json['opportunity'] as Map<String, dynamic>?;
    final locationJson = opportunityJson?['location'] as Map<String, dynamic>?;
    final candidatesJson = json['candidates'] as List? ?? const [];

    return RecommendedCandidatesResult(
      workMode: opportunityJson?['work_mode'] as String? ?? 'remote',
      opportunityType: opportunityJson?['opportunity_type'] as String? ?? 'job',
      locationName: locationJson?['canonical_name'] as String?,
      candidates: candidatesJson
          .map(
            (json) => RecommendedCandidateModel.fromJson(
              json as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}
