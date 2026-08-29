import '../../../core/utils/date_formatter.dart';
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
  'message': 'Message',
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

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _isYesterday(DateTime a, DateTime b) {
  final yesterday = DateTime(b.year, b.month, b.day - 1);
  return _isSameDay(a, yesterday);
}

/// A human-friendly relative rendering of [time] (UI Phase 9) -- "Just
/// now"/"5m ago"/"2h ago" only within the same real calendar day as [now]
/// (defaults to [DateTime.now]), "Yesterday" for the calendar day before
/// that, and [formatDate] for anything older. Calendar-day comparison
/// (not a raw 24h difference) deliberately avoids the misleading case of
/// an 11pm-yesterday notification reading "2h ago" once it's past
/// midnight -- see this phase's own audit note on timezone/day-boundary
/// safety. [time] is used exactly as parsed (this app has no established
/// UTC-normalization convention -- see `date_formatter.dart`), so this
/// never alters stored timezone semantics.
String notificationRelativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  if (time.isAfter(reference)) return formatDate(time);

  if (_isSameDay(time, reference)) {
    final diff = reference.difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
  if (_isYesterday(time, reference)) return 'Yesterday';
  return formatDate(time);
}

/// The real calendar-day bucket [time] falls into, for presentation-only
/// grouping (UI Phase 9) -- never alters ordering, which stays exactly
/// what the backend/provider already returns (newest-first).
String notificationDateBucket(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  if (time.isAfter(reference) || _isSameDay(time, reference)) return 'Today';
  if (_isYesterday(time, reference)) return 'Yesterday';
  return 'Earlier';
}
