/// A student's profile, as returned by the Laravel `student_profile`
/// endpoints (`GET`/`POST /api/student/profile`).
///
/// Only the fields this app collects and displays are modeled here
/// (`university`, `major`, `graduation_year`) — the backend record also has
/// `phone`, `bio`, and `profile_image`, but nothing in the app reads those
/// yet.
class StudentProfileModel {
  const StudentProfileModel({
    required this.id,
    required this.university,
    required this.major,
    required this.graduationYear,
  });

  final int id;
  final String? university;
  final String? major;
  final int? graduationYear;

  factory StudentProfileModel.fromJson(Map<String, dynamic> json) {
    return StudentProfileModel(
      id: json['id'] as int,
      university: json['university'] as String?,
      major: json['major'] as String?,
      graduationYear: json['graduation_year'] as int?,
    );
  }
}
