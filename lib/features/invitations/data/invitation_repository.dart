import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/invitation_model.dart';

/// Talks to the Laravel Invitation endpoints (Phase 8B-3, Flow B) — both
/// the Organization's own (`POST /organization/invitations`) and the
/// Student's (`GET /student/invitations`, accept/decline). One repository
/// serves both sides, the same reasoning `OpportunityRepository` already
/// follows for its own dual Organization/Student endpoints.
class InvitationRepository {
  InvitationRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Sends an invitation with `POST /api/organization/invitations`.
  ///
  /// Errors: 404 (opportunity not found / not this organization's / no
  /// matching active student), 409 (already applied, or an invitation
  /// already exists for this student and opportunity), 422 (opportunity
  /// not open, or validation).
  Future<void> sendInvitation({
    required int studentId,
    required int opportunityId,
    String? message,
  }) async {
    try {
      await apiClient.dio.post(
        '/organization/invitations',
        data: {
          'student_id': studentId,
          'opportunity_id': opportunityId,
          'message': ?message,
        },
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the authenticated student's own invitations with
  /// `GET /api/student/invitations`.
  Future<List<InvitationModel>> getInvitations() async {
    try {
      final response = await apiClient.dio.get('/student/invitations');
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => InvitationModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Accepts an invitation with
  /// `PUT /api/student/invitations/{invitation}/accept`.
  ///
  /// Errors: 404 (not found / not yours), 409 (already responded to).
  Future<void> acceptInvitation(int invitationId) async {
    try {
      await apiClient.dio.put('/student/invitations/$invitationId/accept');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Declines an invitation with
  /// `PUT /api/student/invitations/{invitation}/decline`.
  ///
  /// Errors: 404 (not found / not yours), 409 (already responded to).
  Future<void> declineInvitation(int invitationId) async {
    try {
      await apiClient.dio.put('/student/invitations/$invitationId/decline');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
