import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/conversation_model.dart';
import '../../../models/message_model.dart';

/// Talks to the Laravel Messaging MVP endpoints. One shared repository for
/// both roles — `GET /conversations`, `GET /conversations/{conversation}`,
/// and `POST /conversations/{conversation}/messages` are role-agnostic
/// backend routes (see `ConversationController`'s own doc comment), the
/// same "one shared endpoint, one shared client-side class" reasoning
/// `NotificationRepository` already follows. Starting a *new* conversation
/// is the one genuinely Organization-only action
/// (`Organization\ConversationStartController`), kept here too rather than
/// in a second repository, since it's still part of the same one
/// Conversation resource.
class ConversationRepository {
  ConversationRepository({required this.apiClient});

  final ApiClient apiClient;

  /// The authenticated user's own conversations, most recently active
  /// first, with `GET /api/conversations`.
  ///
  /// Errors: 401, 403 (inactive account).
  Future<List<ConversationSummaryModel>> getConversations() async {
    try {
      final response = await apiClient.dio.get('/conversations');
      final data = apiClient.parseData(response) as List<dynamic>;
      return data
          .map(
            (json) => ConversationSummaryModel.fromJson(
              json as Map<String, dynamic>,
            ),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// One conversation's full message history with
  /// `GET /api/conversations/{conversationId}` — as the one real side
  /// effect of reading it, the backend also marks every unread message
  /// from the other party as read.
  ///
  /// Errors: 401, 403, 404 (not found / not owned by this user).
  Future<ConversationModel> getConversation(int conversationId) async {
    try {
      final response = await apiClient.dio.get('/conversations/$conversationId');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return ConversationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Sends one real message with
  /// `POST /api/conversations/{conversationId}/messages`. [body] is the
  /// only field a client can ever set — `sender_user_id` always comes from
  /// the authenticated session server-side, never from this call.
  ///
  /// Errors: 401, 403, 404 (not found / not owned), 422 (empty/blank/
  /// over-long body).
  Future<MessageModel> sendMessage(int conversationId, String body) async {
    try {
      final response = await apiClient.dio.post(
        '/conversations/$conversationId/messages',
        data: {'body': body},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return MessageModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Starts (or, per the backend's deterministic reuse rule, reuses) a
  /// Conversation between the authenticated Organization and [studentId]
  /// about [opportunityId], with
  /// `POST /api/organization/candidates/{studentId}/conversation`.
  /// Organization-only — a Student never initiates.
  ///
  /// Errors: 401, 403 (no legitimate recruiting relationship with this
  /// candidate for this opportunity), 404 (opportunity not found / not
  /// this organization's own).
  Future<int> startConversation({
    required int studentId,
    required int opportunityId,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/organization/candidates/$studentId/conversation',
        data: {'opportunity_id': opportunityId},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return data['conversation_id'] as int;
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
