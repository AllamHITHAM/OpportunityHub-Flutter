import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/organization_profile_model.dart';

/// Talks to the Laravel organization-profile endpoint.
///
/// Unlike the student profile, there is no separate
/// `POST /api/organization/profile` endpoint — an organization's profile is
/// created atomically alongside the account itself by
/// `POST /api/register/organization` (see `AuthRepository.registerOrganization`).
/// This repository only ever reads it back.
class OrganizationProfileRepository {
  OrganizationProfileRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the current organization's own profile with
  /// `GET /api/organization/profile`.
  ///
  /// Returns `null` on the documented 404 ("Organization profile not
  /// found") — that's an expected outcome, not an error. Any other
  /// failure still throws [ApiException].
  Future<OrganizationProfileModel?> getProfile() async {
    try {
      final response = await apiClient.dio.get('/organization/profile');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationProfileModel.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      throw apiClient.handleError(error);
    }
  }
}
