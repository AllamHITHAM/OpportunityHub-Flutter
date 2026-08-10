/// A student's own attempt at a [QuizModel] — returned by
/// `POST /student/quizzes/{quiz}/start` (freshly created, or an existing
/// unsubmitted attempt resumed as-is) and
/// `POST /student/quizzes/{quiz}/submit` (graded).
///
/// Mirrors the backend's `QuizAttempt` model exactly — no status enum:
/// [submittedAt] being `null` means the attempt is still in progress,
/// non-null means it's been submitted and graded. Deliberately carries no
/// correct-answer or per-question-correctness field; the backend's own
/// `QuizAttempt` has none, grading only ever produces an overall [score].
class QuizAttemptModel {
  const QuizAttemptModel({
    required this.id,
    required this.quizId,
    required this.applicationId,
    this.answers = const {},
    this.score,
    this.startedAt,
    this.submittedAt,
  });

  final int id;
  final int quizId;
  final int applicationId;

  /// Question ID -> the student's submitted answer text. Empty for an
  /// unsubmitted attempt — the backend's `answers` column stays `null`
  /// until `submit()` grades it, at which point it becomes the full
  /// question-by-question answer list.
  final Map<int, String> answers;

  /// `null` until the attempt is submitted and graded.
  final int? score;

  final DateTime? startedAt;
  final DateTime? submittedAt;

  bool get isSubmitted => submittedAt != null;

  factory QuizAttemptModel.fromJson(Map<String, dynamic> json) {
    return QuizAttemptModel(
      id: json['id'] as int,
      quizId: json['quiz_id'] as int,
      applicationId: json['application_id'] as int,
      answers: _parseAnswers(json['answers']),
      score: _parseInt(json['score']),
      startedAt: _parseDate(json['started_at']),
      submittedAt: _parseDate(json['submitted_at']),
    );
  }

  /// The backend stores/returns `answers` as a list of
  /// `{question_id, answer}` objects (the same shape the submit request
  /// body itself uses), not a map — reshaped here into a question-ID-keyed
  /// map for convenient lookup. `null` (an unsubmitted attempt) parses
  /// safely to an empty map; a malformed item is skipped rather than
  /// thrown on, since it can only ever affect display of the student's own
  /// already-submitted answers, never grading (which already happened
  /// server-side).
  static Map<int, String> _parseAnswers(dynamic value) {
    if (value == null) return const {};
    if (value is List) {
      final result = <int, String>{};
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          final questionId = item['question_id'];
          final answer = item['answer'];
          if (questionId is int && answer is String) {
            result[questionId] = answer;
          }
        }
      }
      return result;
    }
    throw TypeError();
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
