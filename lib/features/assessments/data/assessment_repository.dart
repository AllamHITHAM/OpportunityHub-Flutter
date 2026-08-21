import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/assessment_model.dart';
import '../../../models/interview_model.dart';
import '../../../models/question_model.dart';
import '../../../models/quiz_attempt_model.dart';
import '../../../models/quiz_model.dart';
import 'interview_create_input.dart';
import 'question_input.dart';
import 'quiz_create_input.dart';

/// Talks to the Laravel generic Assessment endpoints — kept separate from
/// [ApplicationRepository] since Assessment is a structurally distinct
/// resource (its own table, its own read/write endpoints), the same
/// reasoning already applied to keeping `CvRepository`/`OpportunityRepository`
/// each their own file. As of Phase 6B-2 this also covers the Organization
/// Quiz-authoring endpoints (`/organization/quizzes/...`) — a genuinely
/// separate resource from Assessment, but kept in this file rather than a
/// new `QuizRepository` since it's the same backend feature area
/// (Organization Assessment authoring) and reuses the same [apiClient]
/// wiring; see `OrganizationQuizProvider` for why Quiz *state* still gets
/// its own provider despite sharing this repository.
class AssessmentRepository {
  AssessmentRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Creates an assessment for [applicationId] with
  /// `POST /api/organization/applications/{applicationId}/assessments`.
  ///
  /// For `type == 'interview'`, [interviewInput] is required and becomes
  /// the nested `interview` request field. For `type == 'quiz'`,
  /// [quizInput] is required and becomes the nested `quiz` request field.
  /// Exactly one of the two is ever sent — never both, and never the wrong
  /// one for the given [type].
  ///
  /// The only conditions this method rejects locally, before making any
  /// request, are `type == 'interview'` with a missing [interviewInput], or
  /// `type == 'quiz'` with a missing [quizInput] — genuinely malformed
  /// local calls this repository has no way to shape into a valid request
  /// body. Any other [type] value is passed through as-is with neither
  /// nested field, reaching the backend's own validation.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing), 409 (an
  /// assessment already exists), 422 (invalid source application status or
  /// field validation).
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    if (type == 'interview' && interviewInput == null) {
      throw ArgumentError.value(
        interviewInput,
        'interviewInput',
        'interviewInput is required when type is "interview"',
      );
    }
    if (type == 'quiz' && quizInput == null) {
      throw ArgumentError.value(
        quizInput,
        'quizInput',
        'quizInput is required when type is "quiz"',
      );
    }

    final body = <String, dynamic>{
      'type': type,
      if (type == 'interview') 'interview': interviewInput!.toJson(),
      if (type == 'quiz') 'quiz': quizInput!.toJson(),
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

  /// Convenience wrapper over [createAssessment] for the Interview type.
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

  /// Convenience wrapper over [createAssessment] for the Quiz type.
  Future<AssessmentModel> createQuizAssessment({
    required int applicationId,
    required QuizCreateInput quizInput,
  }) {
    return createAssessment(
      applicationId: applicationId,
      type: 'quiz',
      quizInput: quizInput,
    );
  }

  /// Completes [interviewId] (the final step needed for
  /// `Assessment.status` to become `completed`, which is what makes Send
  /// Offer eligible) with
  /// `PUT /api/organization/interviews/{interviewId}/complete`.
  ///
  /// [decision]/[rating]/[companyFeedback] are all optional — matching
  /// `CompleteInterviewRequest`'s fully-nullable backend rules, an
  /// interview can be completed with none of them set. Each is trimmed
  /// and, if empty/whitespace-only or null, omitted from the request body
  /// entirely, the same "not specified" convention
  /// [InterviewCreateInput.toJson] already uses.
  ///
  /// Returns the updated Interview — the actual shape this endpoint
  /// returns (see docs/API.md section 6), not a synthesized Assessment.
  ///
  /// Errors: 401, 403, 404 (interview not owned/missing), 422 (field
  /// validation).
  Future<InterviewModel> completeInterview({
    required int interviewId,
    String? decision,
    int? rating,
    String? companyFeedback,
  }) async {
    final body = <String, dynamic>{};

    final trimmedDecision = decision?.trim();
    if (trimmedDecision != null && trimmedDecision.isNotEmpty) {
      body['decision'] = trimmedDecision;
    }

    if (rating != null) body['rating'] = rating;

    final trimmedFeedback = companyFeedback?.trim();
    if (trimmedFeedback != null && trimmedFeedback.isNotEmpty) {
      body['company_feedback'] = trimmedFeedback;
    }

    try {
      final response = await apiClient.dio.put(
        '/organization/interviews/$interviewId/complete',
        data: body,
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return InterviewModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
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

  /// Fetches the quiz (if any) belonging to [assessmentId] with
  /// `GET /api/organization/assessments/{assessmentId}/quiz`. Returns
  /// `null` only when the backend's own `data` is `null` (the assessment
  /// exists but has no quiz — e.g. `type == 'interview'`, or a quiz that
  /// hasn't been created yet) — a non-null but malformed `data` throws
  /// instead of silently becoming `null`.
  ///
  /// Errors: 401, 403, 404 (assessment not owned/missing).
  Future<QuizModel?> getOrganizationQuiz(int assessmentId) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/assessments/$assessmentId/quiz',
      );
      final data = apiClient.parseData(response);
      if (data == null) return null;
      return QuizModel.fromJson(data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Creates a question on [quizId] with
  /// `POST /api/organization/quizzes/{quizId}/questions`.
  ///
  /// Errors: 401, 403, 404 (quiz not owned/missing), 422 (published quiz,
  /// or field validation).
  Future<QuestionModel> createQuizQuestion({
    required int quizId,
    required QuestionInput input,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/organization/quizzes/$quizId/questions',
        data: input.toJson(),
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return QuestionModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Updates [questionId] on [quizId] (full replacement, not a partial
  /// update) with
  /// `PUT /api/organization/quizzes/{quizId}/questions/{questionId}`.
  ///
  /// Errors: 401, 403, 404 (quiz not owned/missing, or the question doesn't
  /// belong to [quizId]), 422 (published quiz, or field validation).
  Future<QuestionModel> updateQuizQuestion({
    required int quizId,
    required int questionId,
    required QuestionInput input,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/organization/quizzes/$quizId/questions/$questionId',
        data: input.toJson(),
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return QuestionModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Deletes [questionId] from [quizId] with
  /// `DELETE /api/organization/quizzes/{quizId}/questions/{questionId}`.
  ///
  /// Errors: 401, 403, 404 (quiz not owned/missing, or the question doesn't
  /// belong to [quizId]), 422 (published quiz).
  Future<void> deleteQuizQuestion({
    required int quizId,
    required int questionId,
  }) async {
    try {
      await apiClient.dio.delete(
        '/organization/quizzes/$quizId/questions/$questionId',
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Publishes [quizId] with `PUT /api/organization/quizzes/{quizId}/publish`.
  ///
  /// The backend's response `data` is the quiz itself (`quiz.status` is
  /// already `published`), additionally nesting the parent `assessment`
  /// (`assessment.status` already `scheduled`) — unlike every other Quiz
  /// response, which never nests `assessment` at all. [QuizModel] parses
  /// that nested assessment's `status` into [QuizModel.assessmentStatus];
  /// this method still returns a plain [QuizModel] (the shape `data`
  /// actually is), not an [AssessmentModel].
  ///
  /// Errors: 401, 403, 404 (quiz not owned/missing), 422 (already
  /// published, or zero questions).
  Future<QuizModel> publishQuiz(int quizId) async {
    try {
      final response = await apiClient.dio.put(
        '/organization/quizzes/$quizId/publish',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return QuizModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches every assessment belonging to the authenticated student's own
  /// applications with `GET /api/student/assessments`. The response is a
  /// flat array, not paginated. A non-list or malformed-item response
  /// throws instead of silently becoming an empty list, via the same
  /// forced-cast convention [getAssessmentForApplication] already relies
  /// on — `AssessmentModel`/`InterviewModel` themselves already use unsafe
  /// casts for their required fields, so a malformed item throws loudly
  /// rather than becoming a fake assessment.
  ///
  /// Errors: 401, 403.
  Future<List<AssessmentModel>> getStudentAssessments() async {
    try {
      final response = await apiClient.dio.get('/student/assessments');
      final data = apiClient.parseData(response) as List<dynamic>;
      return data
          .map((json) => AssessmentModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches a single assessment belonging to the authenticated student
  /// with `GET /api/student/assessments/{assessmentId}`.
  ///
  /// Errors: 401, 403, 404 (assessment doesn't exist or doesn't belong to
  /// this student).
  Future<AssessmentModel> getStudentAssessment(int assessmentId) async {
    try {
      final response = await apiClient.dio.get(
        '/student/assessments/$assessmentId',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return AssessmentModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the one assessment (if any) belonging to [applicationId], for
  /// one of the authenticated student's own applications.
  ///
  /// Unlike the organization side, there is no
  /// `GET /student/applications/{id}/assessment` endpoint — this fetches
  /// every one of the student's assessments via [getStudentAssessments] and
  /// filters client-side by `applicationId` instead. Acceptable given a
  /// student's assessment count is inherently bounded by how many
  /// applications they have. Returns `null` when none matches, matching
  /// [getAssessmentForApplication]'s "no assessment yet" contract. Any
  /// parsing/network failure from [getStudentAssessments] propagates as-is
  /// — never silently swallowed into a `null`.
  Future<AssessmentModel?> getStudentAssessmentForApplication(
    int applicationId,
  ) async {
    final assessments = await getStudentAssessments();
    for (final assessment in assessments) {
      if (assessment.applicationId == applicationId) return assessment;
    }
    return null;
  }

  /// Fetches the published quiz for [assessmentId], student-safe (every
  /// question's `correct_answer` stripped — see [QuestionModel]) with
  /// `GET /api/student/assessments/{assessmentId}/quiz`.
  ///
  /// Errors: 401, 403, 404 — the backend deliberately returns the same 404
  /// for "not this student's application", "not a quiz assessment", "no
  /// quiz yet", and "quiz still draft", never revealing which case applies.
  Future<QuizModel> getStudentQuiz(int assessmentId) async {
    try {
      final response = await apiClient.dio.get(
        '/student/assessments/$assessmentId/quiz',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return QuizModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Starts (or resumes) the student's one attempt at [quizId] with
  /// `POST /api/student/quizzes/{quizId}/start`. Idempotent while the
  /// attempt is unsubmitted — a repeated call returns that same attempt
  /// as-is, never resetting its `started_at`.
  ///
  /// Errors: 401, 403, 404 (quiz not owned/missing, or not published), 409
  /// (already submitted — Quiz v1 has no retakes).
  Future<QuizAttemptModel> startStudentQuiz(int quizId) async {
    try {
      final response = await apiClient.dio.post(
        '/student/quizzes/$quizId/start',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return QuizAttemptModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Submits the student's answers for [quizId], graded entirely
  /// server-side, with `POST /api/student/quizzes/{quizId}/submit`.
  /// [answers] maps question ID to the student's chosen answer text — the
  /// exact shape the backend expects, reassembled into the
  /// `[{question_id, answer}, ...]` request body it requires.
  ///
  /// Errors: 401, 403, 404 (quiz not owned/missing), 409 (already
  /// submitted), 422 (no attempt started yet, time limit expired, or
  /// answer validation — a missing/foreign/duplicate question ID, or an
  /// answer that doesn't match the question's own options).
  Future<QuizAttemptModel> submitStudentQuiz({
    required int quizId,
    required Map<int, String> answers,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/student/quizzes/$quizId/submit',
        data: {
          'answers': [
            for (final entry in answers.entries)
              {'question_id': entry.key, 'answer': entry.value},
          ],
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return QuizAttemptModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
