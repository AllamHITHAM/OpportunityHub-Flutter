import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/application_model.dart';
import '../../../models/match_analysis_model.dart';

/// Talks to the Laravel application endpoints — both the student-facing
/// ones (listing and applying) and the organization-facing ones (listing
/// an opportunity's applicants, viewing one application, updating its
/// status). Both sides operate on the same underlying `Application`
/// entity, so one repository serves both rather than duplicating
/// request/parsing logic across two classes — the same reasoning already
/// applied to `OpportunityRepository`.
class ApplicationRepository {
  ApplicationRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the authenticated student's own applications with
  /// `GET /api/student/applications`. The response is a flat array, not
  /// paginated.
  Future<List<ApplicationModel>> getStudentApplications() async {
    try {
      final response = await apiClient.dio.get('/student/applications');
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => ApplicationModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Applies to an opportunity with
  /// `POST /api/opportunities/{opportunityId}/apply`.
  ///
  /// Errors: 404 (opportunity not open / organization not approved), 409
  /// (already applied), 422 (deadline passed, no CV exists, or the given
  /// `cv_id` doesn't belong to this student).
  Future<ApplicationModel> applyToOpportunity({
    required int opportunityId,
    required int cvId,
    String? coverLetter,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/opportunities/$opportunityId/apply',
        data: {'cv_id': cvId, 'cover_letter': ?coverLetter},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return ApplicationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the applicants for one of the organization's own opportunities
  /// with `GET /api/organization/opportunities/{opportunityId}/applications`.
  /// The response is a flat array, not paginated. This endpoint does not
  /// eager-load `opportunity` on each application (the caller already knows
  /// it from [opportunityId]) — see `ApplicationModel.opportunity`.
  Future<List<ApplicationModel>> getApplicationsForOpportunity(
    int opportunityId,
  ) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/opportunities/$opportunityId/applications',
      );
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => ApplicationModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches a single application with
  /// `GET /api/organization/applications/{applicationId}`.
  ///
  /// Errors: 404 (not found / not one of this organization's opportunities).
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/applications/$applicationId',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return ApplicationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Updates an application's status with
  /// `PUT /api/organization/applications/{applicationId}/status`.
  ///
  /// [status] is passed through as-is — restricting which values are
  /// reachable (reviewed/shortlisted/rejected only, for this phase) is the
  /// caller's responsibility, not this repository's; it talks to the
  /// documented endpoint exactly as implemented.
  ///
  /// Errors: 404 (not found / not yours), 409 ("Cannot change the status of
  /// a withdrawn application"), 422 (invalid status).
  Future<ApplicationModel> updateOrganizationApplicationStatus({
    required int applicationId,
    required String status,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/organization/applications/$applicationId/status',
        data: {'status': status},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return ApplicationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the current stored match analysis for [applicationId] with
  /// `GET /api/organization/applications/{applicationId}/analysis`.
  ///
  /// Purely read-only — the backend recomputes a fresh factor breakdown
  /// from current student/opportunity data but forces `overall_match_score`
  /// to the already-stored `applications.match_score`, so it never drifts
  /// from what [analyzeApplication] last saved (see
  /// `Organization\ApplicationAnalysisController::show()` on the backend).
  ///
  /// Errors: 401, 403, 404 (application not owned/missing, or genuinely
  /// never analyzed yet — `match_score` still `null` — never distinguished
  /// by the backend).
  Future<MatchAnalysisModel> getApplicationAnalysis(int applicationId) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/applications/$applicationId/analysis',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return MatchAnalysisModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Calculates/recalculates the match analysis for [applicationId] with
  /// `POST /api/organization/applications/{applicationId}/analyze`. No
  /// request body — the backend accepts nothing beyond the Application's
  /// identity. Persists the returned `overall_match_score` into
  /// `applications.match_score` on the backend; this repository call
  /// itself doesn't return an [ApplicationModel] (see
  /// `Organization\ApplicationAnalysisController::analyze()`'s response
  /// shape on the backend), so callers needing the updated
  /// [ApplicationModel] must refresh it separately.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing).
  Future<MatchAnalysisModel> analyzeApplication(int applicationId) async {
    try {
      final response = await apiClient.dio.post(
        '/organization/applications/$applicationId/analyze',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return MatchAnalysisModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Downloads the raw PDF bytes of the CV attached to [applicationId]'s
  /// submission with `GET /api/organization/applications/{applicationId}/cv`
  /// (Phase 8A-4) — the only path an organization can ever reach a
  /// candidate's CV through; there is no way to fetch a CV by its own ID
  /// directly.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing, or the CV file
  /// no longer exists on disk).
  Future<Uint8List> downloadOrganizationApplicationCv(int applicationId) async {
    try {
      final response = await apiClient.dio.get<List<int>>(
        '/organization/applications/$applicationId/cv',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw apiClient.handleBytesError(error);
    }
  }
}
