import '../../../models/notification_model.dart';

// Display helpers for Notification data — kept feature-local, mirroring
// `offer_display.dart`/`assessment_display.dart`'s own separation from
// generic app-wide display files.

/// User-facing labels for every documented `notification.priority` value.
const notificationPriorityLabels = {
  'low': 'Low',
  'normal': 'Normal',
  'high': 'High',
};

/// User-facing labels for every documented `notification.type` value.
const notificationTypeLabels = {
  'system': 'System',
  'application': 'Application',
  'interview': 'Interview',
  'assessment': 'Assessment',
  'offer': 'Offer',
  'organization': 'Organization',
  'opportunity': 'Opportunity',
};

/// [priority]'s label, falling back to a simple capitalized form of the raw
/// value for anything not in [notificationPriorityLabels] — a future
/// backend-added priority must never render as a blank or a raw
/// lowercase/enum-looking string.
String notificationPriorityLabel(String priority) =>
    notificationPriorityLabels[priority] ?? _capitalize(priority);

/// [type]'s label, with the same safe fallback as
/// [notificationPriorityLabel].
String notificationTypeLabel(String type) =>
    notificationTypeLabels[type] ?? _capitalize(type);

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

/// The timestamp to display for [notification] — `sentAt` is preferred
/// (when this notification was actually sent), falling back to
/// `createdAt` only if `sentAt` is somehow absent. Returns `null` when
/// neither is available, so the caller can decide how to render "no time
/// known" without this helper guessing.
DateTime? notificationDisplayTime(NotificationModel notification) =>
    notification.sentAt ?? notification.createdAt;

/// Whether [actionUrl] is a safe, navigable app-relative path — non-empty
/// and beginning with `/`. `action_url` is the source of truth for where a
/// notification navigates (see `NotificationScreen`); this is the one
/// validation gate before ever handing it to GoRouter, never an attempt to
/// infer a destination from `type`/`id` instead.
bool isNavigableActionUrl(String? actionUrl) {
  final value = actionUrl;
  return value != null && value.isNotEmpty && value.startsWith('/');
}
