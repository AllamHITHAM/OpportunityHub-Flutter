import 'interview_model.dart';
import 'quiz_model.dart';

/// One candidate's row on the Phase 10A.4B Opportunity-level Quiz Results
/// view (`GET /organization/opportunities/{opportunity}/quiz/results`) —
/// score/result/decision/release only, deliberately never `answers`/
/// `correct_answer` (see that endpoint's own doc comment, backend).
class QuizCandidateResultModel {
  const QuizCandidateResultModel({
    required this.assessmentId,
    required this.applicationId,
    required this.studentName,
    required this.status,
    this.score,
    this.submittedAt,
    this.result,
    this.resultReleasedAt,
    this.nextAction,
    this.nextActionPreparedAt,
    this.interview,
    this.availableAt,
    this.dueAt,
    this.timingStatus,
  });

  final int assessmentId;
  final int applicationId;
  final String studentName;

  /// One of: pending, scheduled, in_progress, completed, declined,
  /// cancelled — the candidate's own Assessment status.
  final String status;

  /// `null` until the candidate has submitted the quiz.
  final int? score;

  /// Submission Timestamp Fix — `quiz_attempts.submitted_at`, that table's
  /// only real "submitted" signal (see its own migration). `null` until
  /// the candidate has submitted, exactly like [score].
  final DateTime? submittedAt;

  /// One of: null, passed, failed.
  final String? result;

  final DateTime? resultReleasedAt;

  /// One of: null, interview, offer, reject — the Organization's staged or
  /// released next-step decision for this candidate.
  final String? nextAction;

  final DateTime? nextActionPreparedAt;

  /// The real follow-up Interview when [nextAction] is `interview` —
  /// present whether or not it's been released to the Student yet (this
  /// view is Organization-only).
  final InterviewModel? interview;

  /// Phase 10A.4B addendum (section 12) — this candidate's own frozen
  /// availability window, and a derived, human-facing timing label (one of
  /// `upcoming`/`available`/`in_progress`/`submitted`/`deadline_passed`).
  /// Never a stored enum — computed fresh by the backend on every request.
  final DateTime? availableAt;
  final DateTime? dueAt;
  final String? timingStatus;

  factory QuizCandidateResultModel.fromJson(Map<String, dynamic> json) {
    final interviewJson = json['interview'];

    return QuizCandidateResultModel(
      assessmentId: json['assessment_id'] as int,
      applicationId: json['application_id'] as int,
      studentName: json['student_name'] as String? ?? '',
      status: json['status'] as String,
      score: json['score'] as int?,
      submittedAt: _parseDate(json['submitted_at']),
      result: json['result'] as String?,
      resultReleasedAt: _parseDate(json['result_released_at']),
      nextAction: json['next_action'] as String?,
      nextActionPreparedAt: _parseDate(json['next_action_prepared_at']),
      interview: interviewJson is Map<String, dynamic>
          ? InterviewModel.fromJson(interviewJson)
          : null,
      availableAt: _parseDate(json['available_at']),
      dueAt: _parseDate(json['due_at']),
      timingStatus: json['timing_status'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// The full response shape of the Quiz Results endpoint — the shared Quiz
/// itself (for its title/passing score/settings) plus every candidate's own
/// row.
class QuizResultsModel {
  const QuizResultsModel({required this.quiz, required this.candidates});

  final QuizModel quiz;
  final List<QuizCandidateResultModel> candidates;

  factory QuizResultsModel.fromJson(Map<String, dynamic> json) {
    final candidatesJson = json['candidates'];

    return QuizResultsModel(
      quiz: QuizModel.fromJson(json['quiz'] as Map<String, dynamic>),
      candidates: candidatesJson is List
          ? candidatesJson
                .map(
                  (row) => QuizCandidateResultModel.fromJson(
                    row as Map<String, dynamic>,
                  ),
                )
                .toList()
          : const [],
    );
  }
}
