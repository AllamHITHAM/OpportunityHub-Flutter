import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/skill_suggestion_model.dart';

/// Talks to the Laravel Admin skill-suggestion review endpoints
/// (Phase 8A-6.1). Kept separate from `AdminSkillsRepository` since
/// suggestions and the catalog itself are two distinct resources with
/// their own lifecycle, mirroring this app's existing per-resource
/// repository split (see `AdminSkillsRepository`'s own doc comment).
class AdminSkillSuggestionsRepository {
  AdminSkillSuggestionsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches every pending suggestion with
  /// `GET /api/admin/skill-suggestions` -- the backend only ever returns
  /// pending rows.
  ///
  /// Errors: 401, 403.
  Future<List<SkillSuggestionModel>> getPendingSuggestions() async {
    try {
      final response = await apiClient.dio.get('/admin/skill-suggestions');
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) =>
                SkillSuggestionModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Approves a suggestion with
  /// `PUT /api/admin/skill-suggestions/{id}/approve` -- creates (or
  /// reuses) a real Skill catalog entry server-side.
  ///
  /// Errors: 401, 403, 404, 409 (already reviewed).
  Future<void> approve(int suggestionId) async {
    try {
      await apiClient.dio.put('/admin/skill-suggestions/$suggestionId/approve');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Rejects a suggestion with
  /// `PUT /api/admin/skill-suggestions/{id}/reject` -- never creates a
  /// Skill.
  ///
  /// Errors: 401, 403, 404, 409 (already reviewed).
  Future<void> reject(int suggestionId) async {
    try {
      await apiClient.dio.put('/admin/skill-suggestions/$suggestionId/reject');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
