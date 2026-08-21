import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/storage/token_storage_service.dart';
import '../../../models/user_model.dart';

/// Talks to the Laravel auth endpoints and keeps the local token in sync.
///
/// Only student registration (Step 1: account information) is implemented
/// so far — organization registration is not implemented yet.
class AuthRepository {
  AuthRepository({required this.apiClient, required this.tokenStorageService});

  final ApiClient apiClient;
  final TokenStorageService tokenStorageService;

  /// Creates a student account with `POST /register/student`, saves the
  /// returned token, and returns the new user — exactly like [login] does.
  ///
  /// Only sends the account fields the backend accepts here (`name`,
  /// `email`, `password`); student-profile fields (university, major,
  /// graduation year) belong to a separate, later API call. Laravel's
  /// `password` validation rule requires a matching `password_confirmation`
  /// field — callers already confirm the password locally before this is
  /// called, so the same value is sent for both.
  Future<UserModel> registerStudent({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/register/student',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'password_confirmation': password,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      final token = data['token'] as String;
      final userJson = data['user'] as Map<String, dynamic>;

      await tokenStorageService.saveToken(token);
      return UserModel.fromJson(userJson);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Creates an organization (company) account with
  /// `POST /register/organization`, saves the returned token, and returns
  /// the new user — exactly like [registerStudent] does.
  ///
  /// Unlike student registration, the backend creates the organization's
  /// profile atomically in the same call — there is no separate
  /// profile-creation endpoint for organizations, only
  /// `GET`/`PUT /api/organization/profile` for reading/updating one that
  /// already exists. So this method sends both the account fields and the
  /// documented organization-profile fields together, and only returns the
  /// account [UserModel] — the embedded profile is read back separately via
  /// `OrganizationProfileRepository.getProfile()` when needed, rather than
  /// parsed here, keeping this method's responsibility (and return type)
  /// symmetrical with [registerStudent].
  ///
  /// Only sends [industry]/[description]/[website]/[phone] when non-null
  /// and non-empty — they're optional on the backend, so blank input is
  /// omitted from the request rather than sent as an empty string.
  Future<UserModel> registerOrganization({
    required String name,
    required String email,
    required String password,
    required String organizationName,
    required String organizationType,
    String? industry,
    String? description,
    String? website,
    String? phone,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/register/organization',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'password_confirmation': password,
          'organization_name': organizationName,
          'organization_type': organizationType,
          if (industry != null && industry.isNotEmpty) 'industry': industry,
          if (description != null && description.isNotEmpty)
            'description': description,
          if (website != null && website.isNotEmpty) 'website': website,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      final token = data['token'] as String;
      final userJson = data['user'] as Map<String, dynamic>;

      await tokenStorageService.saveToken(token);
      return UserModel.fromJson(userJson);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Logs in with [email] and [password], saves the returned token, and
  /// returns the logged-in user.
  Future<UserModel> login(String email, String password) async {
    try {
      final response = await apiClient.dio.post(
        '/login',
        data: {'email': email, 'password': password},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      final token = data['token'] as String;
      final userJson = data['user'] as Map<String, dynamic>;

      await tokenStorageService.saveToken(token);
      return UserModel.fromJson(userJson);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Requests a password-reset email with `POST /forgot-password` (Phase
  /// 8B-2). The backend always returns the same safe response whether or
  /// not [email] belongs to a real account — this method never exposes
  /// that distinction either; a caller only ever sees success or a
  /// network/validation [ApiException].
  ///
  /// Errors: 422 (malformed/missing email), 429 (rate-limited).
  Future<void> forgotPassword(String email) async {
    try {
      await apiClient.dio.post('/forgot-password', data: {'email': email});
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Completes a password reset with `POST /reset-password` (Phase
  /// 8B-2), using the `token`/`email` pair from the reset link. Does
  /// **not** log the user in — the caller navigates to Login on success,
  /// per this phase's own explicit design.
  ///
  /// Errors: 422 (validation, or an invalid/expired/already-used token),
  /// 429 (rate-limited).
  Future<void> resetPassword({
    required String email,
    required String token,
    required String password,
  }) async {
    try {
      await apiClient.dio.post(
        '/reset-password',
        data: {
          'email': email,
          'token': token,
          'password': password,
          'password_confirmation': password,
        },
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Resends the email-verification link to the authenticated user with
  /// `POST /email/verification-notification` (Phase 8B-2). Safe/idempotent
  /// if already verified — the backend sends nothing and still succeeds.
  ///
  /// Errors: 401 (unauthenticated), 429 (rate-limited).
  Future<void> resendVerificationEmail() async {
    try {
      await apiClient.dio.post('/email/verification-notification');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the currently authenticated user using the saved token.
  Future<UserModel> getCurrentUser() async {
    try {
      final response = await apiClient.dio.get('/me');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return UserModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Calls the logout endpoint, then always deletes the local token,
  /// even if the API call fails.
  Future<void> logout() async {
    try {
      await apiClient.dio.post('/logout');
    } on DioException {
      // Ignore API errors here — the token is removed below regardless,
      // so the user is always signed out locally.
    } finally {
      await tokenStorageService.deleteToken();
    }
  }

  /// Reads the locally saved token, if any, without calling the API.
  Future<String?> getSavedToken() => tokenStorageService.readToken();

  /// Deletes the locally saved token without calling the logout API.
  /// Used when a saved token turns out to be invalid or expired.
  Future<void> clearToken() => tokenStorageService.deleteToken();
}
