import 'opportunity_skill_model.dart';
import 'organization_profile_model.dart';

/// An organization's opportunity, as returned by both the organization's own
/// `organization/opportunities` endpoints and the public
/// `opportunities` endpoints.
///
/// The backend has a single `opportunities` table — `opportunityType` is
/// purely a categorization label (job, internship, volunteer, scholarship,
/// competition); there are no type-specific fields (no internship-only
/// university/major/GPA/hours-per-week fields exist anywhere in the
/// documented contract). Every field below applies uniformly regardless of
/// type.
///
/// [organizationProfile] is only ever populated by the public endpoints,
/// which eager-load it — the organization's own endpoints don't include
/// this relation, so it's `null` there. [opportunitySkills] is populated by
/// both the public endpoints and, as of Phase O8.2, the organization's own
/// `show()` endpoint too (so Edit Opportunity can prefill its Required
/// Skills selection) — still empty (not null) wherever it isn't eager-
/// loaded (e.g. the organization's own list endpoint). Modeled as real
/// nested objects (reusing [OrganizationProfileModel] as-is, and a new
/// lightweight [OpportunitySkillModel]) rather than flattened into strings,
/// so the full nested data survives for the student-facing screens.
class OpportunityModel {
  const OpportunityModel({
    required this.id,
    required this.title,
    required this.description,
    required this.opportunityType,
    required this.employmentType,
    required this.workMode,
    required this.experienceLevel,
    required this.positionsAvailable,
    required this.status,
    this.educationLevel,
    this.location,
    this.locationId,
    this.salaryMin,
    this.salaryMax,
    this.applicationDeadline,
    this.createdAt,
    this.organizationProfile,
    this.opportunitySkills = const [],
    this.eligibleMajors = const [],
    this.recruitmentProcess = 'none',
    this.canDelete = false,
    this.closedAt,
  });

  final int id;
  final String title;
  final String description;

  /// One of: job, internship, volunteer, scholarship, competition.
  final String opportunityType;

  /// One of: full_time, part_time, contract.
  final String employmentType;

  /// One of: remote, hybrid, onsite.
  final String workMode;

  /// One of: no_experience, junior, mid, senior, expert.
  final String experienceLevel;

  /// One of: high_school, diploma, bachelor, master, phd — or `null`.
  final String? educationLevel;

  /// The legacy free-text location string -- preserved for a historical
  /// Opportunity that predates the canonical Location Catalog (Phase
  /// O8.2). A new/edited Opportunity keeps this in sync automatically
  /// (mirrored server-side from [locationId]'s canonical name), so this
  /// remains safe to display directly either way.
  final String? location;

  /// The canonical Location Catalog ID (Phase O8.2) -- `null` for a
  /// Remote Opportunity, or a historical Opportunity that predates this
  /// field. This, not [location], is what location eligibility on
  /// Recommended Candidates actually compares.
  final int? locationId;

  /// Parsed from the backend's `decimal:2`-cast fields, which serialize as
  /// JSON strings (e.g. `"1500.00"`), not numbers.
  final double? salaryMin;
  final double? salaryMax;

  final DateTime? applicationDeadline;

  final int positionsAvailable;

  /// One of: draft, open, closed.
  final String status;

  final DateTime? createdAt;

  /// The posting organization — present only when the public endpoints'
  /// eager-loaded `organization_profile` relation is in the response.
  final OrganizationProfileModel? organizationProfile;

  /// Skills attached to this opportunity — present only when the public
  /// endpoints' eager-loaded `opportunity_skills` relation is in the
  /// response. Empty (not null) when absent, so callers never need a null
  /// check before iterating.
  final List<OpportunitySkillModel> opportunitySkills;

  /// Explicit accepted majors (Phase 8B-3.2) — the backend always appends
  /// this field, but empty (not null) here too for the same "never null
  /// check before iterating" reason, and to stay safe against any legacy
  /// response that predates this field entirely. An empty list means the
  /// opportunity is unrestricted — any Student major is eligible. This is
  /// the sole authoritative academic-eligibility source anywhere in this
  /// app (see `OpportunityEligibilityService` on the backend) — the
  /// legacy free-text `field_of_study` column is deprecated as of the
  /// Opportunity Academic Matching Cleanup and is no longer modeled here
  /// at all (never displayed, never sent, never a matching input).
  final List<String> eligibleMajors;

  /// Phase 10A.4B — one of: none, interview, quiz. `none` (the DB column's
  /// own default) means the pre-10A.4B unrestricted ad-hoc "Choose
  /// Assessment" flow (Interview or a private Quiz, freely chosen per
  /// candidate) applies unchanged. `quiz` means candidates are advanced to
  /// this Opportunity's own shared Quiz template instead of a fresh
  /// private one — see `AssessmentRepository.advanceToSharedQuiz()`.
  final String recruitmentProcess;

  /// Company Profile Polish phase: true when this Opportunity has no
  /// recruitment history (no Application, no Invitation, no authored
  /// shared Quiz Template) and can therefore be safely, permanently
  /// deleted. Status-independent -- the Company Profile's own "Closed
  /// Opportunities" cleanup additionally only ever offers this action
  /// for a `closed` Opportunity; the backend independently re-enforces
  /// both conditions regardless of what this field says. Defaults to
  /// `false` (the safe default) on any response that predates this
  /// field.
  final bool canDelete;

  /// Closed Opportunities Scalability Polish -- the real moment this
  /// Opportunity transitioned to `closed` (manual close or automatic
  /// expiration), never `updated_at` (which changes for any unrelated
  /// edit). `null` either because it's not closed, or because it's a
  /// legacy closed row whose true closure time can't be reliably proven
  /// (see the backend migration's own doc comment) -- the UI shows
  /// "Closure date unavailable" for that case rather than a fabricated
  /// date.
  final DateTime? closedAt;

  factory OpportunityModel.fromJson(Map<String, dynamic> json) {
    final organizationProfileJson = json['organization_profile'];
    final opportunitySkillsJson = json['opportunity_skills'];
    final eligibleMajorsJson = json['eligible_majors'];

    return OpportunityModel(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      opportunityType: json['opportunity_type'] as String,
      employmentType: json['employment_type'] as String,
      workMode: json['work_mode'] as String,
      experienceLevel: json['experience_level'] as String,
      educationLevel: json['education_level'] as String?,
      location: json['location'] as String?,
      locationId: json['location_id'] as int?,
      salaryMin: _parseDecimal(json['salary_min']),
      salaryMax: _parseDecimal(json['salary_max']),
      applicationDeadline: _parseDate(json['application_deadline']),
      positionsAvailable: json['positions_available'] as int? ?? 1,
      status: json['status'] as String,
      createdAt: _parseDate(json['created_at']),
      organizationProfile: organizationProfileJson is Map<String, dynamic>
          ? OrganizationProfileModel.fromJson(organizationProfileJson)
          : null,
      opportunitySkills: opportunitySkillsJson is List
          ? opportunitySkillsJson
                .map(
                  (json) => OpportunitySkillModel.fromJson(
                    json as Map<String, dynamic>,
                  ),
                )
                .toList()
          : const [],
      eligibleMajors: eligibleMajorsJson is List
          ? eligibleMajorsJson.map((m) => m as String).toList()
          : const [],
      recruitmentProcess: json['recruitment_process'] as String? ?? 'none',
      canDelete: json['can_delete'] as bool? ?? false,
      closedAt: _parseDate(json['closed_at']),
    );
  }

  static double? _parseDecimal(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
