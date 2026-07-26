import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/student_profile_model.dart';

/// Talks to the Laravel student-profile endpoints.
class StudentProfileRepository {
  StudentProfileRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Creates the student's profile with `POST /api/student/profile`.
  ///
  /// Only sends the fields the backend documents for this call — never
  /// account fields (name/email/password) or a GPA, which this endpoint
  /// doesn't accept.
  Future<StudentProfileModel> createProfile({
    required String university,
    required String major,
    required int graduationYear,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/student/profile',
        data: {
          'university': university,
          'major': major,
          'graduation_year': graduationYear,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return StudentProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the current student's own profile with
  /// `GET /api/student/profile`.
  ///
  /// Returns `null` on the documented 404 ("Student profile not found") —
  /// that's an expected outcome (the student hasn't completed onboarding
  /// yet), not an error. Any other failure still throws [ApiException].
  Future<StudentProfileModel?> getProfile() async {
    try {
      final response = await apiClient.dio.get('/student/profile');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return StudentProfileModel.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      throw apiClient.handleError(error);
    }
  }
}
