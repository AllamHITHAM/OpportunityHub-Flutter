import 'application_model.dart';
import 'interview_model.dart';
import 'quiz_model.dart';

/// The generic evaluation path an organization chooses for a shortlisted
/// application (interview or, as of Phase 6B-2, quiz), as returned by
/// `POST /organization/applications/{application}/assessments` and
/// `GET /organization/applications/{application}/assessment`.
///
/// [application], [interview], and [quiz] reuse the existing
/// [ApplicationModel], [InterviewModel], and [QuizModel] rather than
/// duplicating their fields — the same reasoning [ApplicationModel] already
/// applies to its own nested [OpportunityModel]/[CvModel]. Neither the
/// backend response shape nor this model's parsing has any notion of
/// "legacy" vs. "generic" source — see `AssessmentRepository` for the
/// endpoint-specific concerns.
class AssessmentModel {
  const AssessmentModel({
    required this.id,
    required this.applicationId,
    required this.type,
    required this.status,
    this.result,
    this.completedAt,
    this.resultReleasedAt,
    this.nextAction,
    this.nextActionData,
    this.nextActionPreparedAt,
    this.nextActionAssessment,
    this.createdAt,
    this.updatedAt,
    this.application,
    this.interview,
    this.quiz,
    this.availableAt,
    this.dueAt,
    this.quizTimingStatus,
  });

  final int id;
  final int applicationId;

  /// One of: interview, quiz.
  final String type;

  /// One of: pending, scheduled, in_progress, completed, declined, cancelled.
  final String status;

  /// One of: null, pending, passed, failed, waiting. `null` means no
  /// decision has been recorded yet -- **on the Student-facing endpoints
  /// only**. On Organization-facing endpoints, `result` is always the real
  /// value the instant it's graded, regardless of [resultReleasedAt] (see
  /// that field's own doc comment) -- the Organization's own view is never
  /// gated.
  final String? result;

  final DateTime? completedAt;

  /// Phase 10A.2 — when [result] became (or will become) visible to the
  /// Student. `null` means not yet released. Only meaningful on
  /// Organization-facing responses; the Student's own responses never
  /// need this (their `result` is already hidden until release, via the
  /// backend's own `HidesUnreleasedQuizResult`, so a Student never needs
  /// to separately ask "has it been released").
  final DateTime? resultReleasedAt;

  /// Phase 10A.4A — the Organization's selected next-step decision for
  /// this (Quiz) Assessment. One of `interview`/`offer`/`reject`, or
  /// `null` before a decision has been selected. Never present on a
  /// Student-facing response (always stripped server-side, regardless of
  /// release state — see the backend's `HidesUnreleasedQuizResult` trait);
  /// only ever populated on Organization-facing responses.
  final String? nextAction;

  /// Phase 10A.4A — the staged Offer terms when [nextAction] is `offer`
  /// (the exact same shape `SendOfferInput.toJson()` produces) — `null`
  /// otherwise, and always `null` once released (the real `Offer` created
  /// at release time is reached through the normal Offer flow instead).
  final Map<String, dynamic>? nextActionData;

  /// Phase 10A.4A — when the Organization completed selecting/readying
  /// [nextAction]. `null` before a decision exists.
  final DateTime? nextActionPreparedAt;

  /// Phase 10A.4A — the real follow-up Interview Assessment [nextAction]
  /// `interview` points at, only ever populated when the Organization's
  /// own response eager-loads it (`Organization\AssessmentController`).
  /// Its own `interview` field carries the real scheduling details. Never
  /// populated recursively beyond this one level.
  final AssessmentModel? nextActionAssessment;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Only populated when the response eager-loads it — never assume it's
  /// present. Reuses [ApplicationModel] as-is; no applicant-specific data
  /// is parsed separately here.
  final ApplicationModel? application;

  /// Only populated when [type] is `interview` and the response
  /// eager-loads it.
  final InterviewModel? interview;

  /// Only populated when [type] is `quiz` and the response eager-loads it.
  final QuizModel? quiz;

  /// Phase 10A.4B addendum — this candidate's own frozen availability
  /// window for a `type=quiz` Assessment referencing an Opportunity's
  /// shared Quiz template. Real `Assessment` columns, present on every
  /// Assessment response regardless of endpoint (Organization or Student).
  /// Both `null` for every legacy/ad-hoc Assessment, or an interview — that
  /// means "no gating", not "not loaded".
  final DateTime? availableAt;
  final DateTime? dueAt;

  /// Phase 10A.4B addendum (section 12) — a derived, human-facing timing
  /// label: one of `upcoming`/`available`/`in_progress`/`submitted`/
  /// `deadline_passed`. Only ever populated on Organization-facing
  /// responses (`Organization\AssessmentController`) — never a stored
  /// enum, so `null` here simply means the response this came from doesn't
  /// compute it (every Student-facing response, or a non-quiz Assessment).
  final String? quizTimingStatus;

  factory AssessmentModel.fromJson(Map<String, dynamic> json) {
    final applicationJson = json['application'];
    final interviewJson = json['interview'];
    final quizJson = json['quiz'];
    final nextActionAssessmentJson = json['next_action_assessment'];
    final nextActionDataJson = json['next_action_data'];

    return AssessmentModel(
      id: json['id'] as int,
      applicationId: json['application_id'] as int,
      type: json['type'] as String,
      status: json['status'] as String,
      result: json['result'] as String?,
      completedAt: _parseDate(json['completed_at']),
      resultReleasedAt: _parseDate(json['result_released_at']),
      nextAction: json['next_action'] as String?,
      nextActionData: nextActionDataJson is Map<String, dynamic>
          ? nextActionDataJson
          : null,
      nextActionPreparedAt: _parseDate(json['next_action_prepared_at']),
      nextActionAssessment: nextActionAssessmentJson is Map<String, dynamic>
          ? AssessmentModel.fromJson(nextActionAssessmentJson)
          : null,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
      application: applicationJson is Map<String, dynamic>
          ? ApplicationModel.fromJson(applicationJson)
          : null,
      interview: interviewJson is Map<String, dynamic>
          ? InterviewModel.fromJson(interviewJson)
          : null,
      quiz: quizJson is Map<String, dynamic>
          ? QuizModel.fromJson(quizJson)
          : null,
      availableAt: _parseDate(json['available_at']),
      dueAt: _parseDate(json['due_at']),
      quizTimingStatus: json['quiz_timing_status'] as String?,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
