import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/education_verification_model.dart';
import '../../cv/data/picked_cv_file.dart';

/// Talks to the Laravel Student education-verification endpoints (Phase
/// 8B-1). Reuses [PickedCvFile] for the picked PDF -- it's already a
/// generic "filename + bytes" carrier, not CV-specific despite its name.
class EducationVerificationRepository {
  EducationVerificationRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the authenticated student's own verification state with
  /// `GET /api/student/education-verification`. Always succeeds with a
  /// `not_submitted` state rather than a 404 when nothing has been
  /// submitted yet -- see `EducationVerificationModel.isNotSubmitted`.
  Future<EducationVerificationModel> getStatus() async {
    try {
      final response = await apiClient.dio.get(
        '/student/education-verification',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return EducationVerificationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Submits (or resubmits, after a rejection) an education-verification
  /// document with `POST /api/student/education-verification` -- the
  /// exact same multipart-upload shape as `CvRepository.createCv`.
  ///
  /// Errors: 401, 403, 404, 409 (the current verification is already
  /// `verified` and cannot be replaced), 422 (validation).
  Future<EducationVerificationModel> submit({
    required String institutionName,
    required String degreeOrProgram,
    required PickedCvFile file,
  }) async {
    try {
      final formData = FormData.fromMap({
        'institution_name': institutionName,
        'degree_or_program': degreeOrProgram,
        'file': MultipartFile.fromBytes(file.bytes, filename: file.filename),
      });
      final response = await apiClient.dio.post(
        '/student/education-verification',
        data: formData,
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return EducationVerificationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Downloads the raw PDF bytes of the student's own document with
  /// `GET /api/student/education-verification/document`.
  ///
  /// Errors: 401, 403, 404 (nothing submitted yet, or the file no longer
  /// exists on disk).
  Future<Uint8List> downloadDocument() async {
    try {
      final response = await apiClient.dio.get<List<int>>(
        '/student/education-verification/document',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (error) {
      throw apiClient.handleBytesError(error);
    }
  }
}
