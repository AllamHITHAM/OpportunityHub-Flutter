import 'student_skill_model.dart';

/// A summary of the student behind an [ApplicationModel], as seen by an
/// organization — built from the backend's nested `student_profile`
/// object (and its own nested `user` object) on the organization-facing
/// application endpoints (`GET /organization/applications*`,
/// `PUT /organization/applications/{id}/status`).
///
/// Deliberately a separate model from `StudentProfileModel` (which stays
/// minimal, built for the student's own profile-completion check) rather
/// than extending it — this one exists specifically to carry the applicant
/// identity (`name`/`email`, which only ever come from `student_profile.user`,
/// never from `student_profile` itself) an organization needs to review an
/// applicant, which the student-facing model was never meant to hold.
class ApplicantSummaryModel {
  const ApplicantSummaryModel({
    required this.id,
    this.userId,
    this.name,
    this.email,
    this.phone,
    this.university,
    this.major,
    this.graduationYear,
    this.bio,
    this.photoUrl,
    this.skills = const [],
    this.educationVerificationStatus = 'not_submitted',
  });

  final int id;
  final int? userId;

  /// Only ever populated from the nested `student_profile.user` object —
  /// `student_profile` itself has no name/email columns.
  final String? name;
  final String? email;

  final String? phone;
  final String? university;
  final String? major;
  final int? graduationYear;
  final String? bio;

  /// Student Profile Photo: the applicant's uploaded profile photo, if
  /// any -- populated from the nested `student_profile.profile_photo_url`
  /// field (never the raw `profile_image` storage path, which the
  /// backend never exposes). `null` keeps the existing initials-avatar
  /// fallback rendering.
  final String? photoUrl;

  /// The applicant's Student Skills, each carrying its evidence source
  /// (Phase 8A-6.1) — populated from the nested
  /// `student_profile.student_skills` array. Empty (never null) when the
  /// backend omits or sends no skills.
  final List<StudentSkillModel> skills;

  /// One of `not_submitted`, `pending`, `verified`, `rejected` (Phase
  /// 8B-1) — populated from the nested
  /// `student_profile.education_verification_status` field. This is the
  /// only education-verification data an Organization ever receives: the
  /// document, rejection reason, and reviewing admin are never included
  /// in this or any Organization-facing response.
  final String educationVerificationStatus;

  bool get isEducationVerified => educationVerificationStatus == 'verified';

  factory ApplicantSummaryModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    final user = userJson is Map<String, dynamic> ? userJson : null;
    final skillsJson = json['student_skills'];

    return ApplicantSummaryModel(
      id: json['id'] as int,
      userId: json['user_id'] as int?,
      name: user?['name'] as String?,
      email: user?['email'] as String?,
      phone: json['phone'] as String?,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
      bio: json['bio'] as String?,
      photoUrl: json['profile_photo_url'] as String?,
      skills: skillsJson is List
          ? skillsJson
                .whereType<Map<String, dynamic>>()
                .map(StudentSkillModel.fromJson)
                .toList()
          : const [],
      educationVerificationStatus:
          json['education_verification_status'] as String? ?? 'not_submitted',
    );
  }
}
