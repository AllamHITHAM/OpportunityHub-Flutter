import 'candidate_skill_model.dart';
import 'location_model.dart';

/// One result row from `GET /api/organization/candidates` (Phase 8B-3
/// Candidate Search, extended by the Organization Candidate Profile
/// Enrichment phase). [bio]/[currentLocation]/[availableLocations] are now
/// intentionally exposed here (a professional recruiter profile needs
/// them) -- but [phone]/[email] stay `null` unless the search was scoped
/// to a specific `opportunity_id` *and* this candidate already has a real
/// Application for it (see [applicationId]); raw CV text and the
/// education-verification document path are still never sent by the
/// backend at all, so this model has no fields for them.
class CandidateModel {
  const CandidateModel({
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
    this.alreadyApplied,
    this.alreadyInvited,
    this.applicationId,
    this.phone,
    this.email,
    this.interestedIn,
  });

  /// The candidate's `student_profiles.id` -- what
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
  /// Purely informational, never an eligibility signal (see
  /// `LocationModel`'s own backend counterpart doc comment).
  final LocationModel? currentLocation;

  /// The Student's own selected available/preferred work Locations --
  /// empty (never `null`) when none are configured, so the UI can render
  /// "No work locations provided" without a separate null check.
  final List<LocationModel> availableLocations;

  final List<CandidateSkillModel> skills;

  /// Only present when the search was scoped to a specific
  /// `opportunity_id` -- `null` otherwise, never a stand-in `false`, so
  /// the UI can tell "not applicable" apart from "no".
  final bool? alreadyApplied;
  final bool? alreadyInvited;

  /// The real Application ID for this candidate/Opportunity pair --
  /// `null` unless [alreadyApplied] is `true`. This is also the exact
  /// signal that gates [phone]/[email] below and CV access on the
  /// Candidate Profile screen (see `CandidateController`'s own doc
  /// comment on why: the only Organization-facing CV route today is
  /// Application-scoped, so contact info is deliberately gated on the
  /// same real relationship rather than opening a new, broader
  /// authorization surface).
  final int? applicationId;

  /// Only ever present alongside a real [applicationId] -- `null` in
  /// every other case, including general (unscoped) Talent Directory
  /// browsing, where the backend never sends these fields at all.
  final String? phone;
  final String? email;

  /// Candidate Opportunity Preferences patch: the canonical Opportunity
  /// Type(s) this candidate wants to be recommended for -- purely
  /// informational on this profile-browsing screen (Talent Directory is
  /// never itself an eligibility filter). `null` for a profile from
  /// before this patch, never backfilled or guessed.
  final List<String>? interestedIn;

  factory CandidateModel.fromJson(Map<String, dynamic> json) {
    final skillsJson = json['skills'] as List? ?? const [];
    final interestedInJson = json['interested_in'];
    final currentLocationJson = json['current_location'];
    final availableLocationsJson = json['available_locations'] as List? ?? const [];

    return CandidateModel(
      id: json['id'] as int,
      name: json['name'] as String,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
      bio: json['bio'] as String?,
      educationVerificationStatus:
          json['education_verification_status'] as String? ??
          'not_submitted',
      currentLocation: currentLocationJson is Map<String, dynamic>
          ? LocationModel.fromJson(currentLocationJson)
          : null,
      availableLocations: availableLocationsJson
          .map((l) => LocationModel.fromJson(l as Map<String, dynamic>))
          .toList(),
      skills: skillsJson
          .map((s) => CandidateSkillModel.fromJson(s as Map<String, dynamic>))
          .toList(),
      alreadyApplied: json['already_applied'] as bool?,
      alreadyInvited: json['already_invited'] as bool?,
      applicationId: json['application_id'] as int?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      interestedIn: interestedInJson is List
          ? interestedInJson.map((value) => value as String).toList()
          : null,
    );
  }
}
