/// A quiz question — nested under a [QuizModel]'s `questions` list, or
/// returned standalone by
/// `POST/PUT /organization/quizzes/{quiz}/questions[/{question}]`
/// (Organization authoring) and
/// `GET /student/assessments/{assessment}/quiz` (Student quiz-taking).
///
/// Shared by both sides rather than split into a separate Student-only
/// model: every field except [correctAnswer] is identical either way, and
/// [correctAnswer] itself is `String?` for exactly that reason —
/// `correct_answer` is organization-internal (the backend's
/// `HidesInternalQuestionFields` trait strips the key entirely from every
/// Student-facing response, via `Question::makeHidden`), so it's always
/// present on the Organization side and always `null` on the Student side.
/// Student-facing code must never read [correctAnswer]; see
/// `StudentQuizProvider`/`StudentQuizScreen`, which never reference it.
class QuestionModel {
  const QuestionModel({
    required this.id,
    required this.quizId,
    required this.prompt,
    required this.type,
    this.options,
    this.correctAnswer,
    required this.points,
    required this.position,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int quizId;
  final String prompt;

  /// One of: multiple_choice, true_false.
  final String type;

  /// The submitted choices for a `multiple_choice` question. Always `null`
  /// for `true_false` — its two choices are fixed and never stored/sent by
  /// the backend for that type.
  final List<String>? options;

  /// Organization-internal — see this class's own doc comment. Always
  /// present in an Organization response; always `null` in a Student
  /// response.
  final String? correctAnswer;

  final int points;
  final int position;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] as int,
      quizId: json['quiz_id'] as int,
      prompt: json['prompt'] as String,
      type: json['type'] as String,
      options: _parseOptions(json['options']),
      correctAnswer: json['correct_answer'] as String?,
      points: json['points'] as int,
      position: json['position'] as int,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  /// `null` (true_false, or the key genuinely absent) parses safely to
  /// `null`; any other non-list value — or a list containing a non-string
  /// element, via [List.from]'s own element cast — is a malformed response
  /// and throws rather than silently becoming `null`/`[]`, matching every
  /// other required/well-typed field in this app's models.
  static List<String>? _parseOptions(dynamic value) {
    if (value == null) return null;
    if (value is List) return List<String>.from(value);
    throw TypeError();
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
