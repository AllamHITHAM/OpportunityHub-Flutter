import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/organization_profile_model.dart';

/// Talks to the Laravel Admin organization-management endpoints — kept
/// separate from `AdminUsersRepository`/`AdminDashboardRepository` and a
/// future `AdminSkillsRepository` since Dashboard, Users, Organizations, and
/// Skills are four structurally independent resources with no shared state
/// or workflow between them.
///
/// Deliberately exposes no delete or profile-edit method — the backend has
/// no such Admin endpoints (an admin can only view organizations and change
/// their approval status), so this repository's surface matches that
/// exactly rather than offering an operation that would only ever fail.
class AdminOrganizationsRepository {
  AdminOrganizationsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches every organization with `GET /api/admin/organizations` —
  /// unpaginated, with `user` eager-loaded, per the documented contract.
  ///
  /// Errors: 401 (unauthenticated), 403 (inactive account or non-admin
  /// role). A non-list or malformed-item response throws instead of
  /// silently becoming an empty list — the envelope itself via the same
  /// forced-cast convention every other repository method in this app
  /// already relies on, and each item via [_parseAdminOrganization].
  Future<List<OrganizationProfileModel>> getOrganizations() async {
    try {
      final response = await apiClient.dio.get('/admin/organizations');
      final data = apiClient.parseData(response) as List<dynamic>;
      return data.map(_parseAdminOrganization).toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches one organization with
  /// `GET /api/admin/organizations/{organizationId}`, with `user`
  /// eager-loaded.
  ///
  /// Errors: 401, 403, 404 (no such organization).
  Future<OrganizationProfileModel> getOrganization(int organizationId) async {
    try {
      final response = await apiClient.dio.get(
        '/admin/organizations/$organizationId',
      );
      return _parseAdminOrganization(apiClient.parseData(response));
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Approves [organizationId] via the backend's single generic
  /// `PUT /api/admin/organizations/{organizationId}/approval` endpoint
  /// (there's no separate `/approve` route — the endpoint takes whichever
  /// `approval_status` the caller sends).
  ///
  /// Errors: 401, 403 (inactive/non-admin role, or the backend's
  /// organization-cannot-approve-itself guard), 404 (no such organization),
  /// 422 (shouldn't happen for this literal value, but the backend
  /// validates it regardless).
  Future<OrganizationProfileModel> approveOrganization(int organizationId) =>
      _updateApproval(
        organizationId: organizationId,
        approvalStatus: 'approved',
      );

  /// Rejects [organizationId] — see [approveOrganization] for the shared
  /// endpoint/error details; identical except for the `approval_status`
  /// sent.
  Future<OrganizationProfileModel> rejectOrganization(int organizationId) =>
      _updateApproval(
        organizationId: organizationId,
        approvalStatus: 'rejected',
      );

  Future<OrganizationProfileModel> _updateApproval({
    required int organizationId,
    required String approvalStatus,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/admin/organizations/$organizationId/approval',
        data: {'approval_status': approvalStatus},
      );
      return _parseAdminOrganization(apiClient.parseData(response));
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Validates that [value] is a well-formed Admin organization JSON object
  /// before handing it to [OrganizationProfileModel.fromJson].
  ///
  /// [OrganizationProfileModel.fromJson] already uses unsafe casts for its
  /// required fields (so a malformed one throws a raw [TypeError] rather
  /// than silently falling back), but per the lesson learned from
  /// `AdminUsersRepository`/[UserModel] — a shared model's parsing
  /// behavior can't be assumed stable from the Admin boundary's
  /// perspective, and a raw [TypeError] is a worse diagnostic than a
  /// descriptive [FormatException]. This checks the required fields'
  /// presence/types explicitly first, so a malformed *successful* response
  /// here always fails loudly and predictably, never silently becomes a
  /// fake organization. The nested `user` object is left to
  /// [OrganizationProfileModel.fromJson]'s own tolerant handling (absent or
  /// malformed just becomes `null`), since it's genuinely optional display
  /// data, not an identifying field. Shared by [getOrganizations],
  /// [getOrganization], and [_updateApproval] so all three apply exactly
  /// the same validation.
  OrganizationProfileModel _parseAdminOrganization(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected an organization object, got: $value');
    }
    if (value['id'] is! int) {
      throw FormatException(
        'Organization "id" is missing or not an int: ${value['id']}',
      );
    }
    if (value['organization_name'] is! String) {
      throw FormatException(
        'Organization "organization_name" is missing or not a String: '
        '${value['organization_name']}',
      );
    }
    if (value['organization_type'] is! String) {
      throw FormatException(
        'Organization "organization_type" is missing or not a String: '
        '${value['organization_type']}',
      );
    }
    if (value['approval_status'] is! String) {
      throw FormatException(
        'Organization "approval_status" is missing or not a String: '
        '${value['approval_status']}',
      );
    }
    return OrganizationProfileModel.fromJson(value);
  }
}
