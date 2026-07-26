import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/cv_model.dart';

/// Talks to the Laravel student-CV endpoints.
class CvRepository {
  CvRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the authenticated student's own CVs with
  /// `GET /api/student/cvs`. The response is a flat array, not paginated.
  Future<List<CvModel>> getStudentCvs() async {
    try {
      final response = await apiClient.dio.get('/student/cvs');
      final data = apiClient.parseData(response) as List;
      return data
          .map((json) => CvModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Creates a CV with `POST /api/student/cvs`. `filePath` is a plain text
  /// string — there is no real file upload.
  Future<CvModel> createCv({
    required String title,
    required String filePath,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/student/cvs',
        data: {'title': title, 'file_path': filePath},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return CvModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Deletes a CV with `DELETE /api/student/cvs/{id}`.
  ///
  /// Errors: 404 (not found / not yours), 409 ("Cannot delete a CV that has
  /// been used in an application").
  Future<void> deleteCv(int cvId) async {
    try {
      await apiClient.dio.delete('/student/cvs/$cvId');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Sets a CV as the default with `PUT /api/student/cvs/{id}/default`.
  /// The backend unsets `is_default` on every other CV automatically.
  Future<CvModel> setDefaultCv(int cvId) async {
    try {
      final response = await apiClient.dio.put('/student/cvs/$cvId/default');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return CvModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
