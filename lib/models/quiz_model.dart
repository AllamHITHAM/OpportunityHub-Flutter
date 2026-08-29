import 'question_model.dart';
import 'quiz_attempt_model.dart';

/// Quiz-specific authoring configuration, nested under an [AssessmentModel]
/// (`data.quiz` when `type == 'quiz'`, in `assessment_model.dart`) or
/// returned standalone by `GET /organization/assessments/{assessment}/quiz`
/// and the question-authoring/publish endpoints under
/// `/organization/quizzes/{quiz}/...`.
class QuizModel {
  const QuizModel({
    required this.id,
    this.assessmentId,
    this.opportunityId,
    required this.title,
    this.instructions,
    this.timeLimitMinutes,
    required this.passingScore,
    required this.status,
    this.displayMode = 'all',
    this.questionsPerPage,
    this.resultReleaseMode = 'immediate',
    this.resultReleaseAt,
    this.questions = const [],
    this.attempts = const [],
    this.createdAt,
    this.updatedAt,
    this.assessmentStatus,
    this.availabilityDelayDays,
    this.availabilityTime,
    this.submissionWindowHours,
    this.availableAt,
    this.dueAt,
  });

  final int id;

  /// Phase 10A.4B — the legacy, one-candidate-only owning Assessment. `null`
  /// for a shared Opportunity Quiz template (`opportunityId` set instead) —
  /// see this class's own two-shapes note below.
  final int? assessmentId;

  /// Phase 10A.4B — set only on a shared Quiz template returned by the
  /// `/organization/opportunities/{opportunity}/quiz...` endpoints; `null`
  /// for a legacy, per-candidate Quiz (`assessmentId` set instead). A Quiz
  /// is always exactly one of the two shapes, never both.
  final int? opportunityId;

  final String title;
  final String? instructions;
  final int? timeLimitMinutes;
  final int passingScore;

  /// One of: draft, published.
  final String status;

  /// One of: single, paginated, all (Phase 10A.2) — how the Student Quiz
  /// screen paginates questions. Defaults to `all` — every question on
  /// one scrollable page — matching the pre-Phase-10A.2 behavior exactly,
  /// so a response that omits this (impossible from the real backend,
  /// which always appends it with a DB default, but defended here anyway)
  /// never changes existing rendering.
  final String displayMode;

  /// Only meaningful (non-null) when [displayMode] is `paginated`.
  final int? questionsPerPage;

  /// One of: manual, immediate, scheduled (Phase 10A.2) — when the graded
  /// result becomes visible to the Student. Defaults to `immediate`,
  /// matching the pre-Phase-10A.2 behavior (visible the instant the
  /// Student submits).
  final String resultReleaseMode;

  /// Only meaningful (non-null) when [resultReleaseMode] is `scheduled`.
  final DateTime? resultReleaseAt;

  final List<QuestionModel> questions;

  /// The Student's own attempt(s) at this quiz (Phase 10A.2) — only ever
  /// populated on the Organization-facing `GET .../quiz` response (their
  /// own result-review data, real `score` always visible to them
  /// regardless of [resultReleaseMode] — that mode only ever gates
  /// Student-facing visibility). Empty on every Student-facing response;
  /// at most one element in practice (`quiz_attempts`' own
  /// one-per-application uniqueness), never assume a specific count
  /// beyond that.
  final List<QuizAttemptModel> attempts;

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

  /// Phase 10A.4B addendum — the shared candidate-availability policy,
  /// configured once on a shared Opportunity Quiz template (never on a
  /// legacy per-candidate Quiz, where these are always `null`): how many
  /// days after "Advance to Quiz" a candidate's window opens
  /// ([availabilityDelayDays]), the time of day it opens at
  /// ([availabilityTime], `"HH:MM"`), and how many hours the candidate then
  /// has to submit ([submissionWindowHours]). Never itself a candidate's
  /// actual schedule — see [availableAt]/[dueAt] for that.
  final int? availabilityDelayDays;
  final String? availabilityTime;
  final int? submissionWindowHours;

  /// Phase 10A.4B addendum — this specific candidate's own frozen
  /// availability window, computed once at "Advance to Quiz" time from the
  /// policy above. These are never real `Quiz` columns — the backend
  /// attaches them as response-shaping extras sourced from the candidate's
  /// own Assessment (see `Student\QuizController::show()`), so they are
  /// only ever populated on a Student-facing quiz response. `null`/`null`
  /// means "no gating" — either a legacy Quiz, or a candidate whose backend
  /// response simply didn't attach them (e.g. the Organization's own quiz
  /// views, which show per-candidate timing elsewhere instead).
  final DateTime? availableAt;
  final DateTime? dueAt;

  factory QuizModel.fromJson(Map<String, dynamic> json) {
    return QuizModel(
      id: json['id'] as int,
      assessmentId: json['assessment_id'] as int?,
      opportunityId: json['opportunity_id'] as int?,
      title: json['title'] as String,
      instructions: json['instructions'] as String?,
      timeLimitMinutes: _parseInt(json['time_limit_minutes']),
      passingScore: json['passing_score'] as int,
      status: json['status'] as String,
      displayMode: json['display_mode'] as String? ?? 'all',
      questionsPerPage: _parseInt(json['questions_per_page']),
      resultReleaseMode: json['result_release_mode'] as String? ?? 'immediate',
      resultReleaseAt: _parseDate(json['result_release_at']),
      questions: _parseQuestions(json['questions']),
      attempts: _parseAttempts(json['attempts']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      assessmentStatus: _parseAssessmentStatus(json['assessment']),
      availabilityDelayDays: _parseInt(json['availability_delay_days']),
      availabilityTime: json['availability_time'] as String?,
      submissionWindowHours: _parseInt(json['submission_window_hours']),
      availableAt: _parseDate(json['available_at']),
      dueAt: _parseDate(json['due_at']),
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

  /// `null`/absent (every Student-facing response) parses safely to an
  /// empty list rather than throwing — unlike [_parseQuestions], `attempts`
  /// genuinely is absent on most responses, not just defensively treated
  /// that way.
  static List<QuizAttemptModel> _parseAttempts(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map(
            (item) => QuizAttemptModel.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    }
    return const [];
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
