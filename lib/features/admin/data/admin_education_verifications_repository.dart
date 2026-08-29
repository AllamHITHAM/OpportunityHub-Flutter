import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/admin_education_verification_model.dart';

/// The document's raw bytes plus its real `Content-Type`, as reported by
/// the backend (which infers it from actual file bytes via
/// `Storage::disk('local')->response()`, never from a stored filename) —
/// the preview flow needs the real MIME type to decide whether to render
/// a PDF, an image, or fall back to a plain download, and never assumes a
/// type from context.
class EducationVerificationDocument {
  const EducationVerificationDocument({
    required this.bytes,
    required this.contentType,
  });

  final Uint8List bytes;
  final String contentType;
}

/// Talks to the Laravel Admin education-verification review endpoints
/// (Phase 8B-1). Mirrors `AdminSkillSuggestionsRepository`'s shape.
class AdminEducationVerificationsRepository {
  AdminEducationVerificationsRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches every submission (pending first) with
  /// `GET /api/admin/education-verifications`.
  Future<List<AdminEducationVerificationModel>> getVerifications() async {
    try {
      final response = await apiClient.dio.get(
        '/admin/education-verifications',
      );
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => AdminEducationVerificationModel.fromJson(
              json as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Downloads the submission's proof document for review with
  /// `GET /api/admin/education-verifications/{id}/document`, along with
  /// its real `Content-Type` — the caller decides how to preview it based
  /// on that, never on a filename or an assumption.
  Future<EducationVerificationDocument> downloadDocument(
    int verificationId,
  ) async {
    try {
      final response = await apiClient.dio.get<List<int>>(
        '/admin/education-verifications/$verificationId/document',
        options: Options(responseType: ResponseType.bytes),
      );
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ??
          'application/octet-stream';
      return EducationVerificationDocument(
        bytes: Uint8List.fromList(response.data ?? const []),
        contentType: contentType,
      );
    } on DioException catch (error) {
      throw apiClient.handleBytesError(error);
    }
  }

  /// Approves a submission with
  /// `PUT /api/admin/education-verifications/{id}/verify`.
  ///
  /// Errors: 401, 403, 404, 409 (already reviewed).
  Future<void> verify(int verificationId) async {
    try {
      await apiClient.dio.put(
        '/admin/education-verifications/$verificationId/verify',
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Rejects a submission with
  /// `PUT /api/admin/education-verifications/{id}/reject`. [reason] is
  /// required by the backend.
  ///
  /// Errors: 401, 403, 404, 409 (already reviewed), 422 (missing reason).
  Future<void> reject(int verificationId, {required String reason}) async {
    try {
      await apiClient.dio.put(
        '/admin/education-verifications/$verificationId/reject',
        data: {'rejection_reason': reason},
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
