/// A student's profile, as returned by the Laravel `student_profile`
/// endpoints (`GET`/`POST`/`PUT /api/student/profile`).
///
/// Models every field the backend actually returns and accepts for this
/// record (`university`, `major`, `graduation_year`, `phone`, `bio`) except
/// `profile_image` — that column exists on the backend row, but there is no
/// real upload endpoint anywhere in this app to populate it with a genuine
/// file, so treating it as editable here would just be a dead text field.
class StudentProfileModel {
  const StudentProfileModel({
    required this.id,
    required this.university,
    required this.major,
    required this.graduationYear,
    this.phone,
    this.bio,
  });

  final int id;
  final String? university;
  final String? major;
  final int? graduationYear;
  final String? phone;
  final String? bio;

  factory StudentProfileModel.fromJson(Map<String, dynamic> json) {
    return StudentProfileModel(
      id: json['id'] as int,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
      phone: json['phone'] as String?,
      bio: json['bio'] as String?,
    );
  }
}
