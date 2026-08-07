import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/user_model.dart';

/// Talks to the Laravel Admin user-management endpoints — kept separate
/// from [AdminDashboardRepository] and a future
/// `AdminOrganizationsRepository`/`AdminSkillsRepository` since Dashboard,
/// Users, Organizations, and Skills are four structurally independent
/// resources with no shared state or workflow between them.
///
/// Deliberately exposes no role-change or delete method — the backend has
/// no such endpoints (role is immutable, users can't be deleted), so this
/// repository's surface matches that exactly rather than offering an
/// operation that would only ever fail.
class AdminUsersRepository {
  AdminUsersRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches every user with `GET /api/admin/users` — unpaginated, per the
  /// documented contract.
  ///
  /// Errors: 401 (unauthenticated), 403 (inactive account or non-admin
  /// role). A non-list or malformed-item response throws instead of
  /// silently becoming an empty list — the envelope itself via the same
  /// forced-cast convention every other repository method in this app
  /// already relies on, and each item via [_parseAdminUser].
  Future<List<UserModel>> getUsers() async {
    try {
      final response = await apiClient.dio.get('/admin/users');
      final data = apiClient.parseData(response) as List<dynamic>;
      return data.map(_parseAdminUser).toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Updates [userId]'s account status with
  /// `PUT /api/admin/users/{userId}/status`. [status] must be `active` or
  /// `suspended` — the backend rejects `pending` and anything else with a
  /// 422; this method passes it through as-is rather than validating it
  /// itself, so the backend's own validation message reaches the caller.
  ///
  /// Errors: 401, 403 (inactive/non-admin role, or the backend's
  /// self-status-change guard — "You cannot change your own account
  /// status"), 404 (user not found), 422 (invalid status).
  Future<UserModel> updateUserStatus({
    required int userId,
    required String status,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/admin/users/$userId/status',
        data: {'status': status},
      );
      return _parseAdminUser(apiClient.parseData(response));
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Validates that [value] is a well-formed Admin user JSON object before
  /// handing it to [UserModel.fromJson].
  ///
  /// [UserModel.fromJson] is deliberately tolerant — a malformed/missing
  /// `id`/`name`/etc. quietly becomes `0`/`''` — because it's shared with
  /// the auth/session endpoints, which must stay lenient (see
  /// [UserModel]'s own docs). The Admin endpoints have no such excuse: a
  /// malformed *successful* response here must fail loudly, never
  /// silently become a fake user, so this checks the required fields'
  /// types itself first. `created_at`/`updated_at` are left to
  /// [UserModel.fromJson]'s own tolerant date parsing, since they're
  /// genuinely optional here. Shared by [getUsers] and [updateUserStatus]
  /// so both apply exactly the same validation.
  UserModel _parseAdminUser(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected a user object, got: $value');
    }
    if (value['id'] is! int) {
      throw FormatException(
        'User "id" is missing or not an int: ${value['id']}',
      );
    }
    if (value['name'] is! String) {
      throw FormatException(
        'User "name" is missing or not a String: ${value['name']}',
      );
    }
    if (value['email'] is! String) {
      throw FormatException(
        'User "email" is missing or not a String: ${value['email']}',
      );
    }
    if (value['role'] is! String) {
      throw FormatException(
        'User "role" is missing or not a String: ${value['role']}',
      );
    }
    if (value['status'] is! String) {
      throw FormatException(
        'User "status" is missing or not a String: ${value['status']}',
      );
    }
    return UserModel.fromJson(value);
  }
}
