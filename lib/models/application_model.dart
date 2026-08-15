import 'applicant_summary_model.dart';
import 'cv_model.dart';
import 'opportunity_model.dart';

/// A student's application to an opportunity, as returned by both the
/// student-facing endpoints (`POST /opportunities/{opportunity}/apply`,
/// `GET /student/applications`) and the organization-facing endpoints
/// (`GET /organization/applications`,
/// `GET /organization/opportunities/{opportunity}/applications`,
/// `GET /organization/applications/{application}`,
/// `PUT /organization/applications/{application}/status`).
///
/// [opportunity] and [cv] reuse the existing [OpportunityModel]/[CvModel]
/// rather than duplicating their fields.
///
/// [opportunity] is nullable: every endpoint eager-loads it *except*
/// `GET /organization/opportunities/{opportunity}/applications`, which
/// omits it entirely (the caller already knows the opportunity from the
/// URL) — callers must not assume it's always populated. Note also that
/// the backend does NOT eager-load `opportunity.organizationProfile` for
/// applications (only `opportunity` itself), so
/// [OpportunityModel.organizationProfile] on the nested [opportunity] is
/// always `null` here — different from the public opportunity-browsing
/// endpoints.
///
/// [applicant] is only ever populated on the organization-facing
/// endpoints, which eager-load `student_profile.user` — student-facing
/// endpoints never include `student_profile` at all, so [applicant] is
/// always `null` there.
class ApplicationModel {
  const ApplicationModel({
    required this.id,
    required this.studentId,
    required this.opportunityId,
    required this.cvId,
    required this.status,
    required this.cv,
    this.opportunity,
    this.applicant,
    this.matchScore,
    this.coverLetter,
    this.appliedAt,
    this.reviewedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int studentId;
  final int opportunityId;
  final int cvId;

  /// One of: pending, reviewed, shortlisted, interview_scheduled, accepted,
  /// rejected, withdrawn.
  final String status;

  final OpportunityModel? opportunity;
  final CvModel cv;

  /// The applicant's identity/profile summary — populated only on
  /// organization-facing responses (built from the nested
  /// `student_profile`/`student_profile.user` objects). Always `null` on
  /// student-facing responses.
  final ApplicantSummaryModel? applicant;

  /// Parsed from the backend's `decimal:2`-cast field, which serializes as
  /// a JSON string (e.g. `"75.50"`), not a number. `null` means not yet
  /// calculated; `0`–`100` (including a genuine `0`) means calculated —
  /// never conflate the two. Populated by the backend's deterministic,
  /// rule-based `MatchingService` (Phase 8A-2), either automatically on
  /// application submission or via an organization's manual recalculation.
  /// Organization-facing only — stripped from every Student-facing
  /// response by `HidesInternalApplicationFields` on the backend (Phase
  /// 8A-1); this app must never surface it to a Student. Displayed to the
  /// organization on the applicants list and application details screen
  /// (Phase 8A-3), including the full factor breakdown via
  /// `MatchAnalysisModel`.
  final double? matchScore;

  final String? coverLetter;
  final DateTime? appliedAt;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ApplicationModel.fromJson(Map<String, dynamic> json) {
    final opportunityJson = json['opportunity'];
    final studentProfileJson = json['student_profile'];

    return ApplicationModel(
      id: json['id'] as int,
      studentId: json['student_id'] as int,
      opportunityId: json['opportunity_id'] as int,
      cvId: json['cv_id'] as int,
      status: json['status'] as String,
      opportunity: opportunityJson is Map<String, dynamic>
          ? OpportunityModel.fromJson(opportunityJson)
          : null,
      cv: CvModel.fromJson(json['cv'] as Map<String, dynamic>),
      applicant: studentProfileJson is Map<String, dynamic>
          ? ApplicantSummaryModel.fromJson(studentProfileJson)
          : null,
      matchScore: _parseDecimal(json['match_score']),
      coverLetter: json['cover_letter'] as String?,
      appliedAt: _parseDate(json['applied_at']),
      reviewedAt: _parseDate(json['reviewed_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
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
