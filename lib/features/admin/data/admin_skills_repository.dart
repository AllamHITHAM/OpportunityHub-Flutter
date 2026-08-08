import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/skill_model.dart';

/// Talks to the Laravel Admin skill-management endpoints — kept separate
/// from `AdminUsersRepository`/`AdminOrganizationsRepository`/
/// `AdminDashboardRepository` since Dashboard, Users, Organizations, and
/// Skills are four structurally independent resources with no shared state
/// or workflow between them.
///
/// `category` exists on the backend record but is never collected or shown
/// by this phase's UI, so it's deliberately never sent on create/update —
/// only `name`, which is all the Admin Skills screen actually manages.
class AdminSkillsRepository {
  AdminSkillsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches every skill with `GET /api/admin/skills` — unpaginated, per
  /// the documented contract.
  ///
  /// Errors: 401 (unauthenticated), 403 (inactive account or non-admin
  /// role). A non-list or malformed-item response throws instead of
  /// silently becoming an empty list — the envelope itself via the same
  /// forced-cast convention every other repository method in this app
  /// already relies on, and each item via [_parseAdminSkill].
  Future<List<SkillModel>> getSkills() async {
    try {
      final response = await apiClient.dio.get('/admin/skills');
      final data = apiClient.parseData(response) as List<dynamic>;
      return data.map(_parseAdminSkill).toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Creates a skill with `POST /api/admin/skills`.
  ///
  /// Errors: 401, 403, 409 (a race-condition fallback for the unique-name
  /// check — the backend's `QueryException` catch), 422 (the normal
  /// duplicate-name/blank-name case, with a `name` field error).
  Future<SkillModel> createSkill({required String name}) async {
    try {
      final response = await apiClient.dio.post(
        '/admin/skills',
        data: {'name': name},
      );
      return _parseAdminSkill(apiClient.parseData(response));
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Updates a skill's name with `PUT /api/admin/skills/{skillId}`.
  ///
  /// Errors: 401, 403, 404 (no such skill), 409 (unique-check race
  /// condition), 422 (duplicate-name/blank-name, with a `name` field
  /// error; the backend's own uniqueness check ignores this skill's
  /// current name, so renaming to the same name is not itself an error).
  Future<SkillModel> updateSkill({
    required int skillId,
    required String name,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/admin/skills/$skillId',
        data: {'name': name},
      );
      return _parseAdminSkill(apiClient.parseData(response));
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Deletes a skill with `DELETE /api/admin/skills/{skillId}`. The
  /// success response's `data` is always `null` (nothing to parse into a
  /// [SkillModel]).
  ///
  /// Errors: 401, 403, 404 (no such skill), 409 ("Cannot delete a skill
  /// that is currently in use" — still referenced by a student or an
  /// opportunity; the backend refuses rather than cascading).
  Future<void> deleteSkill(int skillId) async {
    try {
      await apiClient.dio.delete('/admin/skills/$skillId');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Validates that [value] is a well-formed Admin skill JSON object
  /// before handing it to [SkillModel.fromJson].
  ///
  /// [SkillModel.fromJson] already uses unsafe casts for `id`/`name` (so a
  /// malformed one throws a raw [TypeError] rather than silently falling
  /// back), but per the lesson learned from `AdminUsersRepository`/
  /// `AdminOrganizationsRepository` — a shared model's parsing behavior
  /// can't be assumed stable from the Admin boundary's perspective, and a
  /// raw [TypeError] is a worse diagnostic than a descriptive
  /// [FormatException]. This checks the required fields' presence/types
  /// explicitly first, so a malformed *successful* response here always
  /// fails loudly and predictably, never silently becomes a fake skill.
  /// `category`/`created_at`/`updated_at` are left to
  /// [SkillModel.fromJson]'s own tolerant handling, since they're
  /// genuinely optional. Shared by [getSkills], [createSkill], and
  /// [updateSkill] so all three apply exactly the same validation.
  SkillModel _parseAdminSkill(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected a skill object, got: $value');
    }
    if (value['id'] is! int) {
      throw FormatException(
        'Skill "id" is missing or not an int: ${value['id']}',
      );
    }
    if (value['name'] is! String) {
      throw FormatException(
        'Skill "name" is missing or not a String: ${value['name']}',
      );
    }
    return SkillModel.fromJson(value);
  }
}
