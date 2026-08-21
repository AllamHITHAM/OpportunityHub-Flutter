/// The authenticated student's own education-verification state, as
/// returned by `GET /api/student/education-verification` (Phase 8B-1).
///
/// `status` is one of `not_submitted`, `pending`, `verified`, `rejected`.
/// "Verified" means an Admin reviewed the uploaded document and approved
/// it -- never a direct university/government/cryptographic check. The
/// raw document is never included here; see
/// `EducationVerificationRepository.downloadDocument`.
class EducationVerificationModel {
  const EducationVerificationModel({
    required this.institutionName,
    required this.degreeOrProgram,
    required this.status,
    this.rejectionReason,
    this.submittedAt,
    this.reviewedAt,
  });

  final String? institutionName;
  final String? degreeOrProgram;
  final String status;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  bool get isNotSubmitted => status == 'not_submitted';
  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isRejected => status == 'rejected';

  factory EducationVerificationModel.fromJson(Map<String, dynamic> json) {
    return EducationVerificationModel(
      institutionName: json['institution_name'] as String?,
      degreeOrProgram: json['degree_or_program'] as String?,
      status: json['status'] as String? ?? 'not_submitted',
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
