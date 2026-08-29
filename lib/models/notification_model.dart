/// An in-app notification for the authenticated user, as returned by
/// `GET /notifications` and the two mark-read endpoints (Phase 7A-1/7A-2
/// backend). Shared by all three roles — the backend endpoint is
/// role-agnostic — so this model carries no role-specific interpretation of
/// its own.
///
/// [priority]/[type] are kept as the raw backend strings, not enums — this
/// app has no established enum-for-backend-string convention (every other
/// status-like field, e.g. `application.status`/`assessment.status`, is a
/// plain `String` too), and a display-time lookup map (see
/// `notification_display.dart`) already covers turning them into labels
/// without needing a closed Dart type here. An unrecognized value is stored
/// as-is rather than rejected, so a future backend-added value never breaks
/// parsing.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.priority,
    required this.type,
    this.actionUrl,
    required this.isRead,
    this.readAt,
    this.sentAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int userId;
  final String title;
  final String message;

  /// One of: low, normal, high.
  final String priority;

  /// One of: system, application, interview, assessment, offer,
  /// organization, opportunity, message.
  final String type;

  /// App-relative Flutter route path (e.g. `/student/applications/42`), or
  /// `null` when this notification has no navigable destination. Never a
  /// full URL — see `notification_display.dart` for the navigation-time
  /// validation of this field.
  final String? actionUrl;

  final bool isRead;
  final DateTime? readAt;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      title: json['title'] as String,
      message: json['message'] as String,
      priority: json['priority'] as String,
      type: json['type'] as String,
      actionUrl: json['action_url'] as String?,
      isRead: json['is_read'] as bool,
      readAt: _parseDate(json['read_at']),
      sentAt: _parseDate(json['sent_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  /// A copy with [isRead]/[readAt] overridden — the only fields a
  /// successful mark-read/mark-all response ever changes, matching what
  /// `NotificationController::markAsRead()` itself touches on the backend.
  NotificationModel copyWithRead({required DateTime readAt}) {
    return NotificationModel(
      id: id,
      userId: userId,
      title: title,
      message: message,
      priority: priority,
      type: type,
      actionUrl: actionUrl,
      isRead: true,
      readAt: readAt,
      sentAt: sentAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
