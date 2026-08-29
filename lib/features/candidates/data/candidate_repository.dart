import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/candidate_model.dart';
import '../../../models/recommended_candidate_model.dart';

/// Talks to the Laravel Organization Candidate Search endpoint (Phase
/// 8B-3). Filter/search-only -- no ranking, no scoring.
class CandidateRepository {
  CandidateRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Real, eligible candidates for one specific Opportunity, ranked by
  /// match score highest-first (Phase O8.1) --
  /// `GET /organization/opportunities/{opportunity}/recommended-candidates`.
  /// The backend computes each score live via the same formula an
  /// Application would later be scored with; this never creates one.
  ///
  /// As of Phase O8.2, the response also carries the real Opportunity
  /// context (`work_mode`, canonical location) the recommendations screen
  /// needs to render a truthful explanation of what was filtered/ranked --
  /// see [RecommendedCandidatesResult].
  Future<RecommendedCandidatesResult> getRecommendedCandidates(
    int opportunityId,
  ) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/opportunities/$opportunityId/recommended-candidates',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return RecommendedCandidatesResult.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Searches candidates with `GET /api/organization/candidates`. Every
  /// filter is optional; omitted ones aren't sent at all. When
  /// [opportunityId] is given, each result also carries
  /// `already_applied`/`already_invited` for that specific opportunity —
  /// the backend 404s if it isn't one of this organization's own.
  Future<List<CandidateModel>> searchCandidates({
    String? name,
    String? major,
    String? university,
    int? graduationYear,
    String? skill,
    int? opportunityId,
  }) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/candidates',
        queryParameters: {
          'name': ?name,
          'major': ?major,
          'university': ?university,
          'graduation_year': ?graduationYear,
          'skill': ?skill,
          'opportunity_id': ?opportunityId,
        },
      );
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => CandidateModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
