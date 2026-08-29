/// The fields needed to create a Quiz draft, shaped for
/// `AssessmentRepository.createAssessment` — keeps the repository/provider
/// methods from taking loose positional/named parameters. Mirrors
/// `InterviewCreateInput`'s conventions exactly.
class QuizCreateInput {
  const QuizCreateInput({
    required this.title,
    this.instructions,
    this.timeLimitMinutes,
    required this.passingScore,
    this.displayMode,
    this.questionsPerPage,
    this.resultReleaseMode,
    this.resultReleaseAt,
    this.availabilityDelayDays,
    this.availabilityTime,
    this.submissionWindowHours,
  });

  final String title;
  final String? instructions;
  final int? timeLimitMinutes;

  /// An integer percentage, 0–100.
  final int passingScore;

  /// One of: single, paginated, all (Phase 10A.2). `null` omits the field
  /// entirely, leaving the backend's own default (`all`) in effect —
  /// matching the pre-Phase-10A.2 behavior.
  final String? displayMode;

  /// Only meaningful when [displayMode] is `'paginated'`.
  final int? questionsPerPage;

  /// One of: manual, immediate, scheduled (Phase 10A.2). `null` omits the
  /// field entirely, leaving the backend's own default (`immediate`) in
  /// effect — matching the pre-Phase-10A.2 behavior.
  final String? resultReleaseMode;

  /// Only meaningful when [resultReleaseMode] is `'scheduled'`.
  final DateTime? resultReleaseAt;

  /// Phase 10A.4B addendum — the shared candidate-availability policy.
  /// Required by the backend on the *template* endpoints
  /// (`createOpportunityQuiz`/`updateOpportunityQuiz`) only; the legacy
  /// ad-hoc `quiz.*` payload (`createAssessment`) doesn't accept these
  /// fields at all, so they must stay `null` there — `toJson()` only ever
  /// includes a field when it's non-null, so the ad-hoc payload shape is
  /// completely unaffected as long as callers on that path never set them.
  final int? availabilityDelayDays;

  /// `"HH:MM"`, 24-hour.
  final String? availabilityTime;
  final int? submissionWindowHours;

  /// Builds the backend's expected `quiz` request body. [instructions] is
  /// trimmed and, if empty or whitespace-only, omitted entirely rather than
  /// sent as an empty string — matching [InterviewCreateInput]'s
  /// "not specified" convention.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'title': title.trim(),
      'passing_score': passingScore,
    };

    if (timeLimitMinutes != null) {
      json['time_limit_minutes'] = timeLimitMinutes;
    }

    final instructionsValue = _cleaned(instructions);
    if (instructionsValue != null) json['instructions'] = instructionsValue;

    if (displayMode != null) json['display_mode'] = displayMode;
    if (questionsPerPage != null) {
      json['questions_per_page'] = questionsPerPage;
    }
    if (resultReleaseMode != null) {
      json['result_release_mode'] = resultReleaseMode;
    }
    if (resultReleaseAt != null) {
      json['result_release_at'] = resultReleaseAt!.toIso8601String();
    }
    if (availabilityDelayDays != null) {
      json['availability_delay_days'] = availabilityDelayDays;
    }
    if (availabilityTime != null) {
      json['availability_time'] = availabilityTime;
    }
    if (submissionWindowHours != null) {
      json['submission_window_hours'] = submissionWindowHours;
    }

    return json;
  }

  static String? _cleaned(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
