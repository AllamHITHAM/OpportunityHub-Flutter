import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/assessment_model.dart';
import 'interview_create_input.dart';

/// Talks to the Laravel generic Assessment endpoints — kept separate from
/// [ApplicationRepository] since Assessment is a structurally distinct
/// resource (its own table, its own read/write endpoints), the same
/// reasoning already applied to keeping `CvRepository`/`OpportunityRepository`
/// each their own file.
class AssessmentRepository {
  AssessmentRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Creates an assessment for [applicationId] with
  /// `POST /api/organization/applications/{applicationId}/assessments`.
  ///
  /// [type] is passed through to the backend as-is — this keeps the method
  /// suitable for a future Quiz type without a repository-level rewrite,
  /// even though only `type == 'interview'` has a local input shape today.
  /// For `type == 'interview'`, [interviewInput] is required and becomes
  /// the nested `interview` request field; for any other [type] (including
  /// `'quiz'`), no `interview` field is sent — the backend's own response
  /// (e.g. its "Quiz assessments are not available yet." 422) is what
  /// actually determines the outcome, which is deliberate: it lets a
  /// `type: 'quiz'` call reach the real backend response instead of being
  /// silently short-circuited here.
  ///
  /// The only condition this method rejects locally, before making any
  /// request, is `type == 'interview'` with a missing [interviewInput] —
  /// a genuinely malformed local call this repository has no way to shape
  /// into a valid request body.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing), 409 (an
  /// assessment already exists), 422 (invalid source application status,
  /// quiz unavailable, or field validation).
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
  }) async {
    if (type == 'interview' && interviewInput == null) {
      throw ArgumentError.value(
        interviewInput,
        'interviewInput',
        'interviewInput is required when type is "interview"',
      );
    }

    final body = <String, dynamic>{
      'type': type,
      if (type == 'interview') 'interview': interviewInput!.toJson(),
    };

    try {
      final response = await apiClient.dio.post(
        '/organization/applications/$applicationId/assessments',
        data: body,
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return AssessmentModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Convenience wrapper over [createAssessment] for the one type this
  /// phase actually implements a form for.
  Future<AssessmentModel> createInterviewAssessment({
    required int applicationId,
    required InterviewCreateInput interviewInput,
  }) {
    return createAssessment(
      applicationId: applicationId,
      type: 'interview',
      interviewInput: interviewInput,
    );
  }

  /// Fetches the one assessment (if any) belonging to [applicationId] with
  /// `GET /api/organization/applications/{applicationId}/assessment`.
  /// Returns `null` only when the backend's own `data` is `null` (no
  /// assessment yet) — a non-null but malformed `data` throws instead of
  /// silently becoming `null`, via the same forced cast every other
  /// repository method in this app already relies on.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing).
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/applications/$applicationId/assessment',
      );
      final data = apiClient.parseData(response);
      if (data == null) return null;
      return AssessmentModel.fromJson(data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
