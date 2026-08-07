/// The fields needed to create an Interview assessment, shaped for
/// `AssessmentRepository.createAssessment`/`createInterviewAssessment` —
/// keeps the repository/provider methods from taking eight loose
/// positional/named parameters.
class InterviewCreateInput {
  const InterviewCreateInput({
    required this.interviewType,
    required this.scheduledAt,
    this.durationMinutes,
    this.meetingLink,
    this.location,
    this.interviewerName,
    this.interviewerEmail,
    this.notes,
  });

  /// One of: onsite, online, phone.
  final String interviewType;

  final DateTime scheduledAt;
  final int? durationMinutes;
  final String? meetingLink;
  final String? location;
  final String? interviewerName;
  final String? interviewerEmail;
  final String? notes;

  /// Builds the backend's expected `interview` request body. Optional text
  /// fields are trimmed and, if empty or whitespace-only, omitted entirely
  /// rather than sent as an empty string — matching the "not specified"
  /// convention already used elsewhere in this app's display layer.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'interview_type': interviewType,
      'scheduled_at': _formatScheduledAt(scheduledAt),
    };

    if (durationMinutes != null) {
      json['duration_minutes'] = durationMinutes;
    }

    final meetingLinkValue = _cleaned(meetingLink);
    if (meetingLinkValue != null) json['meeting_link'] = meetingLinkValue;

    final locationValue = _cleaned(location);
    if (locationValue != null) json['location'] = locationValue;

    final interviewerNameValue = _cleaned(interviewerName);
    if (interviewerNameValue != null) {
      json['interviewer_name'] = interviewerNameValue;
    }

    final interviewerEmailValue = _cleaned(interviewerEmail);
    if (interviewerEmailValue != null) {
      json['interviewer_email'] = interviewerEmailValue;
    }

    final notesValue = _cleaned(notes);
    if (notesValue != null) json['notes'] = notesValue;

    return json;
  }

  static String? _cleaned(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Formats as `YYYY-MM-DD HH:mm:ss`, the shape Laravel's `date` validation
  /// rule expects — deliberately not `DateTime.toString()`, which appends
  /// microseconds Laravel doesn't need, and deliberately not a dependency
  /// on `intl` (this app has never needed it — see `date_formatter.dart`).
  static String _formatScheduledAt(DateTime value) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$year-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}';
  }
}
