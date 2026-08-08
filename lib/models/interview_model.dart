/// Interview-specific scheduling/outcome detail, as nested under an
/// [AssessmentModel] (`data.interview` on
/// `POST /organization/applications/{application}/assessments` and
/// `GET /organization/applications/{application}/assessment`) — and, in a
/// future phase, under the standalone legacy Interview endpoints too. This
/// model is deliberately endpoint-agnostic: it parses whatever `interview`
/// JSON shape it's given and has no idea which endpoint produced it. Any
/// nested `application` key (present on the legacy Interview endpoints'
/// backward-compatible shape) is simply ignored — not every field a
/// response carries needs to be modeled here.
class InterviewModel {
  const InterviewModel({
    required this.id,
    required this.assessmentId,
    required this.interviewType,
    this.scheduledAt,
    this.durationMinutes,
    this.meetingLink,
    this.location,
    this.interviewerName,
    this.interviewerEmail,
    this.notes,
    required this.status,
    this.decision,
    this.rating,
    this.companyFeedback,
    this.completedAt,
  });

  final int id;
  final int assessmentId;

  /// One of: onsite, online, phone.
  final String interviewType;

  final DateTime? scheduledAt;
  final int? durationMinutes;
  final String? meetingLink;
  final String? location;
  final String? interviewerName;
  final String? interviewerEmail;
  final String? notes;

  /// One of: scheduled, completed, cancelled, rescheduled, no_show.
  final String status;

  /// One of: null, pending, passed, failed, waiting. Organization-facing
  /// responses always send this (never `null` in practice — the backend
  /// column defaults to `pending`). The Student-facing endpoints
  /// deliberately omit this field entirely — it's organization-internal
  /// decision state a candidate must never see raw; see
  /// `AssessmentRepository`'s student methods and use
  /// [AssessmentModel.result] instead for the student-facing outcome —
  /// so it parses to `null` there rather than throwing.
  final String? decision;

  final int? rating;
  final String? companyFeedback;
  final DateTime? completedAt;

  factory InterviewModel.fromJson(Map<String, dynamic> json) {
    return InterviewModel(
      id: json['id'] as int,
      assessmentId: json['assessment_id'] as int,
      interviewType: json['interview_type'] as String,
      scheduledAt: _parseDate(json['scheduled_at']),
      durationMinutes: _parseInt(json['duration_minutes']),
      meetingLink: json['meeting_link'] as String?,
      location: json['location'] as String?,
      interviewerName: json['interviewer_name'] as String?,
      interviewerEmail: json['interviewer_email'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String,
      decision: json['decision'] as String?,
      rating: _parseInt(json['rating']),
      companyFeedback: json['company_feedback'] as String?,
      completedAt: _parseDate(json['completed_at']),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
