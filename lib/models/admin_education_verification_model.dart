/// An Admin-facing education-verification submission, as returned by
/// `GET /api/admin/education-verifications*` (Phase 8B-1). Carries the
/// applicant's identity so an Admin never has to cross-reference a bare
/// student id -- built from the backend's nested `student_profile.user`
/// object.
class AdminEducationVerificationModel {
  const AdminEducationVerificationModel({
    required this.id,
    required this.institutionName,
    required this.degreeOrProgram,
    required this.status,
    this.studentName,
    this.studentEmail,
    this.rejectionReason,
    this.submittedAt,
    this.reviewedAt,
  });

  final int id;
  final String institutionName;
  final String degreeOrProgram;
  final String status;
  final String? studentName;
  final String? studentEmail;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  bool get isPending => status == 'pending';

  factory AdminEducationVerificationModel.fromJson(Map<String, dynamic> json) {
    final studentProfile = json['student_profile'];
    final profile = studentProfile is Map<String, dynamic>
        ? studentProfile
        : null;
    final userJson = profile?['user'];
    final user = userJson is Map<String, dynamic> ? userJson : null;

    return AdminEducationVerificationModel(
      id: json['id'] as int,
      institutionName: json['institution_name'] as String,
      degreeOrProgram: json['degree_or_program'] as String,
      status: json['status'] as String,
      studentName: user?['name'] as String?,
      studentEmail: user?['email'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      submittedAt: _parseDate(json['submitted_at']),
      reviewedAt: _parseDate(json['reviewed_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
