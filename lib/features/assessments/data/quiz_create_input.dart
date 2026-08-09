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
  });

  final String title;
  final String? instructions;
  final int? timeLimitMinutes;

  /// An integer percentage, 0–100.
  final int passingScore;

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

    return json;
  }

  static String? _cleaned(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
