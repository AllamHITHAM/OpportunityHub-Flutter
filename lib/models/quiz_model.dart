import 'question_model.dart';

/// Quiz-specific authoring configuration, nested under an [AssessmentModel]
/// (`data.quiz` when `type == 'quiz'`, in `assessment_model.dart`) or
/// returned standalone by `GET /organization/assessments/{assessment}/quiz`
/// and the question-authoring/publish endpoints under
/// `/organization/quizzes/{quiz}/...`.
///
/// Deliberately carries no score/attempt/student-answer fields — Student
/// quiz-taking is not implemented yet.
class QuizModel {
  const QuizModel({
    required this.id,
    required this.assessmentId,
    required this.title,
    this.instructions,
    this.timeLimitMinutes,
    required this.passingScore,
    required this.status,
    this.questions = const [],
    this.createdAt,
    this.updatedAt,
    this.assessmentStatus,
  });

  final int id;
  final int assessmentId;
  final String title;
  final String? instructions;
  final int? timeLimitMinutes;
  final int passingScore;

  /// One of: draft, published.
  final String status;

  final List<QuestionModel> questions;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The parent Assessment's own `status` (e.g. `scheduled` immediately
  /// after a successful publish). Populated only by
  /// `PUT /organization/quizzes/{quiz}/publish` — the one response that
  /// nests a full `assessment` object under the quiz on the backend
  /// (`$quiz->load('assessment.application')`). Every other Quiz response
  /// (`GET .../quiz`, question create/update) has no `assessment` key at
  /// all, so this stays `null` there — never assume it's populated.
  /// Deliberately kept as a plain `String?` rather than a nested
  /// `AssessmentModel` to avoid a circular model dependency for one
  /// incidental field.
  final String? assessmentStatus;

  factory QuizModel.fromJson(Map<String, dynamic> json) {
    return QuizModel(
      id: json['id'] as int,
      assessmentId: json['assessment_id'] as int,
      title: json['title'] as String,
      instructions: json['instructions'] as String?,
      timeLimitMinutes: _parseInt(json['time_limit_minutes']),
      passingScore: json['passing_score'] as int,
      status: json['status'] as String,
      questions: _parseQuestions(json['questions']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      assessmentStatus: _parseAssessmentStatus(json['assessment']),
    );
  }

  /// The backend always eager-loads `questions` on every Quiz-returning
  /// response, so a real response never actually omits this key — `null`/
  /// absent is still treated as an empty list defensively, but any other
  /// non-list value (a malformed response) throws rather than silently
  /// becoming `[]`. A list containing a malformed item (not an object, or
  /// missing a required Question field) throws the same way, via
  /// [QuestionModel.fromJson]'s own required-field casts.
  static List<QuestionModel> _parseQuestions(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((item) => QuestionModel.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    throw TypeError();
  }

  static String? _parseAssessmentStatus(dynamic value) {
    if (value is Map<String, dynamic>) return value['status'] as String?;
    return null;
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
