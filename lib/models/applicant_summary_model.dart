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
    this.profileImage,
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
  final String? profileImage;

  factory ApplicantSummaryModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    final user = userJson is Map<String, dynamic> ? userJson : null;

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
      profileImage: json['profile_image'] as String?,
    );
  }
}
