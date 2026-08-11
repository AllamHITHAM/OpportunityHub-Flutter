import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/offer_model.dart';
import 'send_offer_input.dart';

/// Talks to the Laravel Offer endpoints (Phase 6C-1 backend, Phase 6C-2
/// organization-side Flutter, Phase 6C-3 student-side Flutter). Kept
/// separate from `ApplicationRepository`/`AssessmentRepository` since Offer
/// is a structurally distinct resource (its own table, its own endpoints),
/// the same reasoning already applied to keeping those repositories their
/// own files — see `AssessmentRepository`'s own doc comment.
///
/// Shared between `OrganizationOfferProvider` and `StudentOfferProvider` —
/// the two roles talk to different paths (`/organization/*` vs.
/// `/student/*`) but the same underlying resource, so one repository with
/// role-specific methods avoids duplicating the request/parse plumbing,
/// mirroring `AssessmentRepository`'s own organization/student split.
class OfferRepository {
  OfferRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the one Offer (if any) belonging to [applicationId], for an
  /// application the authenticated organization owns, with
  /// `GET /api/organization/applications/{applicationId}/offer`.
  ///
  /// Unlike `AssessmentRepository.getOrganizationQuiz` (which represents
  /// "none yet" as a `200` with `data: null`), the backend represents "no
  /// Offer yet" here as a genuine `404` — so this always either returns a
  /// real [OfferModel] or throws [ApiException]; callers (see
  /// `OrganizationOfferProvider`) are responsible for treating a `404`
  /// specifically as an empty state, not a load failure.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing, or genuinely no
  /// Offer yet — never distinguished).
  Future<OfferModel> getOrganizationOffer(int applicationId) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/applications/$applicationId/offer',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OfferModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Sends an Offer for [applicationId] with
  /// `POST /api/organization/applications/{applicationId}/offer`.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing), 409 (an Offer
  /// already exists for this application), 422 (application not eligible —
  /// wrong status, no Assessment, or an incomplete Assessment — or field
  /// validation).
  Future<OfferModel> sendOrganizationOffer({
    required int applicationId,
    required SendOfferInput input,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/organization/applications/$applicationId/offer',
        data: input.toJson(),
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OfferModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the one Offer (if any) belonging to [applicationId], for an
  /// application the authenticated student owns, with
  /// `GET /api/student/applications/{applicationId}/offer`.
  ///
  /// The backend deliberately returns the same `404` for "this application
  /// isn't yours" and "no offer exists yet" (see
  /// `Student\OfferController::show()`), so — exactly like
  /// [getOrganizationOffer] — this always either returns a real
  /// [OfferModel] or throws [ApiException]; callers (see
  /// `StudentOfferProvider`) are responsible for treating a `404`
  /// specifically as an empty state, not a load failure.
  ///
  /// Errors: 401, 403, 404 (application not owned/missing, or genuinely no
  /// Offer yet — never distinguished).
  Future<OfferModel> getStudentOffer(int applicationId) async {
    try {
      final response = await apiClient.dio.get(
        '/student/applications/$applicationId/offer',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OfferModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Accepts [offerId] with `PUT /api/student/offers/{offerId}/accept`. No
  /// request body — the backend accepts nothing beyond the Offer's identity
  /// (see `Student\OfferController::accept()`).
  ///
  /// Errors: 401, 403, 404 (offer not owned/missing), 409 (the offer has
  /// already been responded to — accept/decline both terminal, see
  /// `OfferService::respondToOffer()`).
  Future<OfferModel> acceptStudentOffer(int offerId) async {
    try {
      final response = await apiClient.dio.put(
        '/student/offers/$offerId/accept',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OfferModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Declines [offerId] with `PUT /api/student/offers/{offerId}/decline`.
  /// No request body — see [acceptStudentOffer]'s own doc comment.
  ///
  /// Errors: 401, 403, 404 (offer not owned/missing), 409 (the offer has
  /// already been responded to).
  Future<OfferModel> declineStudentOffer(int offerId) async {
    try {
      final response = await apiClient.dio.put(
        '/student/offers/$offerId/decline',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OfferModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
