/// The fields needed to create/update a Question, shaped for
/// `AssessmentRepository.createQuizQuestion`/`updateQuizQuestion`. Used for
/// both create and update — the backend treats both as a full replacement
/// (no partial-update variant), so one input shape covers both.
class QuestionInput {
  const QuestionInput({
    required this.prompt,
    required this.type,
    this.options,
    required this.correctAnswer,
    required this.points,
    required this.position,
  });

  final String prompt;

  /// One of: multiple_choice, true_false.
  final String type;

  /// Only meaningful for `type == 'multiple_choice'` — ignored by [toJson]
  /// for `true_false`.
  final List<String>? options;

  /// For `true_false`, the canonical form is exactly `"True"`/`"False"` —
  /// the caller is expected to already have normalized this before
  /// building the input; this class does not re-canonicalize it.
  final String correctAnswer;

  final int points;
  final int position;

  /// Builds the backend's expected question request body. `options` is
  /// only ever included for `multiple_choice` — `true_false` never sends
  /// it, matching the backend's own contract (not required for that type,
  /// and always overwritten to `null` server-side even if sent). Every
  /// string is trimmed.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'prompt': prompt.trim(),
      'type': type,
      'correct_answer': correctAnswer.trim(),
      'points': points,
      'position': position,
    };

    if (type == 'multiple_choice') {
      json['options'] = (options ?? const [])
          .map((option) => option.trim())
          .toList();
    }

    return json;
  }
}
