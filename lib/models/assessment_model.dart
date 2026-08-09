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
    this.createdAt,
    this.updatedAt,
    this.application,
    this.interview,
    this.quiz,
  });

  final int id;
  final int applicationId;

  /// One of: interview, quiz.
  final String type;

  /// One of: pending, scheduled, in_progress, completed, declined, cancelled.
  final String status;

  /// One of: null, pending, passed, failed, waiting. `null` means no
  /// decision has been recorded yet.
  final String? result;

  final DateTime? completedAt;
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

  factory AssessmentModel.fromJson(Map<String, dynamic> json) {
    final applicationJson = json['application'];
    final interviewJson = json['interview'];
    final quizJson = json['quiz'];

    return AssessmentModel(
      id: json['id'] as int,
      applicationId: json['application_id'] as int,
      type: json['type'] as String,
      status: json['status'] as String,
      result: json['result'] as String?,
      completedAt: _parseDate(json['completed_at']),
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
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
