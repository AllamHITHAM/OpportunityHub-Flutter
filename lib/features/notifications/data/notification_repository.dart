import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/notification_model.dart';

/// Talks to the Laravel Notification endpoints (Phase 7A-1/7A-2 backend,
/// delete/clear-read added Phase 9.1). Role-agnostic — `/notifications` is
/// one shared endpoint for all three roles, so there is exactly one
/// repository, matching `NotificationProvider`'s own "one shared provider"
/// design (see that class's own doc comment).
///
/// No unread-count endpoint, no pagination — the backend has neither.
class NotificationRepository {
  NotificationRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the authenticated user's own notifications, newest first, with
  /// `GET /api/notifications`. Unpaginated — the backend returns the full
  /// list every time.
  ///
  /// Errors: 401, 403 (inactive account).
  Future<List<NotificationModel>> getNotifications() async {
    try {
      final response = await apiClient.dio.get('/notifications');
      final data = apiClient.parseData(response) as List<dynamic>;
      return data
          .map(
            (json) => NotificationModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Marks one notification as read with
  /// `PUT /api/notifications/{notificationId}/read`.
  ///
  /// Errors: 401, 403, 404 (not found / not owned by this user).
  Future<NotificationModel> markAsRead(int notificationId) async {
    try {
      final response = await apiClient.dio.put(
        '/notifications/$notificationId/read',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return NotificationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Marks every currently-unread notification as read with
  /// `PUT /api/notifications/read-all`, returning how many rows were
  /// actually flipped (already-read rows are left untouched — see
  /// `NotificationController::markAllAsRead()`).
  ///
  /// Errors: 401, 403.
  Future<int> markAllAsRead() async {
    try {
      final response = await apiClient.dio.put('/notifications/read-all');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return data['updated_count'] as int;
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Permanently removes one notification from the caller's own inbox
  /// with `DELETE /api/notifications/{notificationId}` (Phase 9.1). Inbox
  /// cleanup only — the backend guarantees this can never affect the
  /// Application/Invitation/Assessment/Interview/Offer/EducationVerification
  /// the notification was originally about (see
  /// `NotificationController::destroy()`'s own doc comment).
  ///
  /// Errors: 401, 403, 404 (not found / not owned by this user).
  Future<void> deleteNotification(int notificationId) async {
    try {
      await apiClient.dio.delete('/notifications/$notificationId');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Permanently removes every currently-read notification from the
  /// caller's own inbox with `DELETE /api/notifications/read` (Phase
  /// 9.1). Unread notifications are never touched. Returns how many rows
  /// were actually deleted.
  ///
  /// Errors: 401, 403.
  Future<int> clearRead() async {
    try {
      final response = await apiClient.dio.delete('/notifications/read');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return data['deleted_count'] as int;
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
