import 'candidate_skill_model.dart';

/// One result row from `GET /api/organization/candidates` (Phase 8B-3
/// Candidate Search). Deliberately narrow -- the backend never sends
/// email/phone/raw CV text/education document paths here, so this model
/// has no fields for them either.
class CandidateModel {
  const CandidateModel({
    required this.id,
    required this.name,
    required this.university,
    required this.major,
    required this.graduationYear,
    required this.educationVerificationStatus,
    required this.skills,
    this.alreadyApplied,
    this.alreadyInvited,
  });

  /// The candidate's `student_profiles.id` -- what
  /// `POST /organization/invitations` expects as `student_id`.
  final int id;

  final String name;
  final String? university;
  final String? major;
  final int? graduationYear;

  /// `not_submitted`, `pending`, `verified`, or `rejected`.
  final String educationVerificationStatus;

  final List<CandidateSkillModel> skills;

  /// Only present when the search was scoped to a specific
  /// `opportunity_id` -- `null` otherwise, never a stand-in `false`, so
  /// the UI can tell "not applicable" apart from "no".
  final bool? alreadyApplied;
  final bool? alreadyInvited;

  factory CandidateModel.fromJson(Map<String, dynamic> json) {
    final skillsJson = json['skills'] as List? ?? const [];

    return CandidateModel(
      id: json['id'] as int,
      name: json['name'] as String,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
      educationVerificationStatus:
          json['education_verification_status'] as String? ??
          'not_submitted',
      skills: skillsJson
          .map((s) => CandidateSkillModel.fromJson(s as Map<String, dynamic>))
          .toList(),
      alreadyApplied: json['already_applied'] as bool?,
      alreadyInvited: json['already_invited'] as bool?,
    );
  }
}
