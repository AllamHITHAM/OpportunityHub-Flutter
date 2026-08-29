import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/organization_dashboard_stats_model.dart';

/// Talks to the Laravel Organization dashboard endpoint — kept separate
/// from `OrganizationOpportunitiesProvider`/`OrganizationApplicationsProvider`
/// etc. since Dashboard is a structurally independent resource with no
/// shared state or workflow with those, the same separation
/// `AdminDashboardRepository` already established for Admin.
class OrganizationDashboardRepository {
  OrganizationDashboardRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches this organization's recruitment statistics with
  /// `GET /api/organization/dashboard`.
  ///
  /// Errors: 401 (unauthenticated), 403 (inactive account or non-organization
  /// role). A non-null but malformed `data` throws instead of silently
  /// becoming empty/zeroed statistics, via the same forced cast every other
  /// repository method in this app already relies on, combined with
  /// [OrganizationDashboardStatsModel]'s own defensive-but-non-silent field
  /// parsing.
  Future<OrganizationDashboardStatsModel> getDashboardStats() async {
    try {
      final response = await apiClient.dio.get('/organization/dashboard');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationDashboardStatsModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
