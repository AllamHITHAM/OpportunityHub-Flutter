// Direct unit tests for the notification_display.dart pure helpers (UI
// Phase 9) -- no widgets involved.

import 'package:flutter_test/flutter_test.dart';
import 'package:opportunityhub_flutter/features/notifications/presentation/notification_display.dart';

void main() {
  group('notificationRelativeTime', () {
    final now = DateTime(2026, 8, 24, 14, 0);

    test('under a minute reads "Just now"', () {
      final time = now.subtract(const Duration(seconds: 30));
      expect(notificationRelativeTime(time, now: now), 'Just now');
    });

    test('minutes within the same day read "Nm ago"', () {
      final time = now.subtract(const Duration(minutes: 5));
      expect(notificationRelativeTime(time, now: now), '5m ago');
    });

    test('hours within the same day read "Nh ago"', () {
      final time = now.subtract(const Duration(hours: 3));
      expect(notificationRelativeTime(time, now: now), '3h ago');
    });

    test(
      'a time from the calendar day before reads "Yesterday", never a raw hour count',
      () {
        // 11pm the day before "now" (2026-08-24 14:00) is only ~15h
        // earlier, but a real calendar day apart -- must never read "15h
        // ago" and imply it was still today.
        final time = DateTime(2026, 8, 23, 23, 0);
        expect(notificationRelativeTime(time, now: now), 'Yesterday');
      },
    );

    test('anything older than yesterday falls back to the formatted date', () {
      final time = DateTime(2026, 8, 10, 9, 0);
      expect(notificationRelativeTime(time, now: now), 'Aug 10, 2026');
    });

    test(
      'a time after "now" (clock skew) never claims a negative/nonsensical relative time',
      () {
        final time = now.add(const Duration(hours: 1));
        expect(notificationRelativeTime(time, now: now), 'Aug 24, 2026');
      },
    );
  });

  group('notificationDateBucket', () {
    final now = DateTime(2026, 8, 24, 14, 0);

    test('the same calendar day buckets as Today', () {
      final time = DateTime(2026, 8, 24, 1, 0);
      expect(notificationDateBucket(time, now: now), 'Today');
    });

    test('the calendar day before buckets as Yesterday', () {
      final time = DateTime(2026, 8, 23, 23, 59);
      expect(notificationDateBucket(time, now: now), 'Yesterday');
    });

    test('anything older buckets as Earlier', () {
      final time = DateTime(2026, 8, 1, 9, 0);
      expect(notificationDateBucket(time, now: now), 'Earlier');
    });
  });

  group('isNavigableActionUrl (regression)', () {
    test('a real app-relative path is navigable', () {
      expect(isNavigableActionUrl('/student/applications/1'), isTrue);
    });

    test('null, empty, and non-relative values are never navigable', () {
      expect(isNavigableActionUrl(null), isFalse);
      expect(isNavigableActionUrl(''), isFalse);
      expect(isNavigableActionUrl('https://example.com'), isFalse);
    });
  });
}
