import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/admin_dashboard_stats_model.dart';

/// Talks to the Laravel Admin dashboard endpoint — kept separate from a
/// future `AdminUsersRepository`/`AdminOrganizationsRepository`/
/// `AdminSkillsRepository` since Dashboard, Users, Organizations, and
/// Skills are four structurally independent resources with no shared
/// state or workflow between them.
class AdminDashboardRepository {
  AdminDashboardRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches platform-wide statistics with `GET /api/admin/dashboard`.
  ///
  /// Errors: 401 (unauthenticated), 403 (inactive account or non-admin
  /// role). A non-null but malformed `data` throws instead of silently
  /// becoming empty/zeroed statistics, via the same forced cast every
  /// other repository method in this app already relies on, combined with
  /// [AdminDashboardStatsModel]'s own defensive-but-non-silent field
  /// parsing.
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    try {
      final response = await apiClient.dio.get('/admin/dashboard');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return AdminDashboardStatsModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
