import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/cv_model.dart';
import '../../../models/cv_skill_suggestion_model.dart';
import 'picked_cv_file.dart';

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

  /// Creates a CV with a real multipart PDF upload —
  /// `POST /api/student/cvs` (Phase 8A-4). [file]'s bytes are attached as
  /// the `file` part; the server generates its own storage filename, so
  /// [PickedCvFile.filename] is only ever informational for the request
  /// (it never determines where the file ends up).
  ///
  /// Errors: 401, 403, 404, 422 (missing/invalid `title`, missing `file`,
  /// non-PDF `file`, `file` over 5 MB).
  Future<CvModel> createCv({
    required String title,
    required PickedCvFile file,
  }) async {
    try {
      final formData = FormData.fromMap({
        'title': title,
        'file': MultipartFile.fromBytes(file.bytes, filename: file.filename),
      });
      final response = await apiClient.dio.post('/student/cvs', data: formData);
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return CvModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Downloads the raw PDF bytes of the authenticated student's own CV with
  /// `GET /api/student/cvs/{cvId}/download` (Phase 8A-4).
  ///
  /// Errors: 401, 403, 404 (not found / not yours, or the file no longer
  /// exists on disk).
  Future<Uint8List> downloadCv(int cvId) async {
    try {
      final response = await apiClient.dio.get<List<int>>(
        '/student/cvs/$cvId/download',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw apiClient.handleBytesError(error);
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

  /// Requests AI-derived skill suggestions from a CV's already-extracted
  /// text with `POST /api/student/cvs/{cvId}/extract-skills` (Phase
  /// 8A-6). Suggestions are transient -- nothing is persisted server-side
  /// by this call, and the raw parsed text is never returned.
  ///
  /// Errors: 401, 403, 404 (not found / not yours), 422 (no extractable
  /// text on this CV), 503 (AI provider unavailable).
  Future<List<CvSkillSuggestion>> extractSkills(int cvId) async {
    try {
      final response = await apiClient.dio.post(
        '/student/cvs/$cvId/extract-skills',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      final skills = data['skills'] as List;
      return skills
          .map(
            (json) => CvSkillSuggestion.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
