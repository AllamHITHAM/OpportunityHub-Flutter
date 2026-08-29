import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/organization_post_model.dart';
import '../../../models/organization_profile_model.dart';
import '../../organization_profile/data/picked_image_file.dart';

/// Talks to the Laravel organization-profile endpoints, both the
/// authenticated organization's own (self-view/edit, post management) and
/// the new public/student-facing ones (Organization Public Profile
/// phase). One repository serves both, matching `CandidateRepository`'s
/// own reasoning for the analogous Organization/Public split.
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

  /// Updates the current organization's own profile with
  /// `PUT /api/organization/profile`. Every field is sent (not just
  /// changed ones) since the backend's own `UpdateOrganizationProfileRequest`
  /// requires `organization_name`/`organization_type` regardless.
  ///
  /// Errors: 401, 403 (wrong role), 404 (no profile), 422 (validation).
  Future<OrganizationProfileModel> updateProfile({
    required String organizationName,
    required String organizationType,
    String? industry,
    String? description,
    String? website,
    String? phone,
    int? locationId,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/organization/profile',
        data: {
          'organization_name': organizationName,
          'organization_type': organizationType,
          'industry': ?industry,
          'description': ?description,
          'website': ?website,
          'phone': ?phone,
          'location_id': ?locationId,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Uploads (or replaces) the Company Logo with a real multipart image
  /// upload — `POST /api/organization/profile/logo` (Company Profile
  /// Polish phase).
  ///
  /// Errors: 401, 403, 404 (no profile), 422 (missing/invalid/oversized
  /// file).
  Future<OrganizationProfileModel> uploadLogo(PickedImageFile file) async {
    try {
      final formData = FormData.fromMap({
        'logo': MultipartFile.fromBytes(file.bytes, filename: file.filename),
      });
      final response = await apiClient.dio.post(
        '/organization/profile/logo',
        data: formData,
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Removes the Company Logo (reverts to the initials fallback) with
  /// `DELETE /api/organization/profile/logo`.
  ///
  /// Errors: 401, 403, 404 (no profile).
  Future<OrganizationProfileModel> removeLogo() async {
    try {
      final response = await apiClient.dio.delete('/organization/profile/logo');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// The public/student-facing profile of any organization, with
  /// `GET /api/organizations/{organizationId}` — reachable
  /// unauthenticated, only ever returns data for an approved
  /// organization (404 otherwise).
  ///
  /// Also used by the owner viewing their own "Company Profile" screen —
  /// the exact same real, safe-field data a Student would see, never a
  /// separate richer self-view for this particular screen.
  ///
  /// Errors: 404 (not found, or not yet approved).
  Future<OrganizationProfileModel> getPublicProfile(int organizationId) async {
    try {
      final response = await apiClient.dio.get('/organizations/$organizationId');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// One organization's "Updates & Achievements" posts, newest first,
  /// with `GET /api/organizations/{organizationId}/posts` — same
  /// reachability rules as [getPublicProfile].
  Future<List<OrganizationPostModel>> getPosts(int organizationId) async {
    try {
      final response = await apiClient.dio.get(
        '/organizations/$organizationId/posts',
      );
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) =>
                OrganizationPostModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Publishes a new post for the current organization with
  /// `POST /api/organization/posts` — always a real multipart request
  /// (Company Profile Polish phase), whether or not [image] is given, so
  /// the exact same request shape works for a text-only post and an
  /// image post alike.
  ///
  /// Errors: 401, 403 (wrong role, or not yet approved), 422 (empty/
  /// blank/over-long body, or an invalid/oversized [image]).
  Future<OrganizationPostModel> createPost({
    String? title,
    required String body,
    PickedImageFile? image,
  }) async {
    try {
      final formData = FormData.fromMap({
        'title': ?title,
        'body': body,
        if (image != null)
          'image': MultipartFile.fromBytes(image.bytes, filename: image.filename),
      });
      final response = await apiClient.dio.post(
        '/organization/posts',
        data: formData,
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationPostModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Edits one of the current organization's own posts with
  /// `PUT /api/organization/posts/{postId}`. [image] present means
  /// "replace with this file"; [removeImage] (only consulted when
  /// [image] is absent) means "clear the existing image"; neither means
  /// "keep whatever image already exists unchanged" — the same
  /// three-state control the backend's own `UpdateOrganizationPostRequest`
  /// documents.
  ///
  /// Errors: 401, 403, 404 (not found / not this organization's own),
  /// 422.
  Future<OrganizationPostModel> updatePost(
    int postId, {
    String? title,
    required String body,
    PickedImageFile? image,
    bool removeImage = false,
  }) async {
    try {
      // A real PHP/Laravel server never populates `$_FILES` for a
      // genuine HTTP PUT request carrying `multipart/form-data` (only
      // POST triggers PHP's own multipart parsing) -- so this is sent as
      // a POST with Laravel's standard `_method` override field, the
      // same "form spoofing" convention `@method('PUT')` uses in a
      // Blade form, landing on the exact same `PUT` route/controller
      // action either way.
      final formData = FormData.fromMap({
        '_method': 'PUT',
        'title': ?title,
        'body': body,
        if (image != null)
          'image': MultipartFile.fromBytes(image.bytes, filename: image.filename)
        else if (removeImage)
          'remove_image': true,
      });
      final response = await apiClient.dio.post(
        '/organization/posts/$postId',
        data: formData,
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OrganizationPostModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Deletes one of the current organization's own posts with
  /// `DELETE /api/organization/posts/{postId}`.
  ///
  /// Errors: 401, 403, 404 (not found / not this organization's own).
  Future<void> deletePost(int postId) async {
    try {
      await apiClient.dio.delete('/organization/posts/$postId');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
