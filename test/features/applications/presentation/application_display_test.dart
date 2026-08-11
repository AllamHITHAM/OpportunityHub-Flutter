// Direct unit tests for application_display.dart's status vocabulary.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/widgets/status_chip.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/application_display.dart';

void main() {
  group('applicationStatusLabels', () {
    test('offer_sent maps to "Offer Sent" (Phase 6C-2)', () {
      expect(applicationStatusLabels['offer_sent'], 'Offer Sent');
    });

    test('every other documented status label is unchanged', () {
      expect(applicationStatusLabels['pending'], 'Pending');
      expect(applicationStatusLabels['reviewed'], 'Reviewed');
      expect(applicationStatusLabels['shortlisted'], 'Shortlisted');
      expect(applicationStatusLabels['in_assessment'], 'Under Assessment');
      expect(
        applicationStatusLabels['interview_scheduled'],
        'Interview Scheduled',
      );
      expect(applicationStatusLabels['accepted'], 'Accepted');
      expect(applicationStatusLabels['rejected'], 'Rejected');
      expect(applicationStatusLabels['withdrawn'], 'Withdrawn');
    });
  });

  group('applicationStatusChipType', () {
    test(
      'offer_sent is grouped with the other in-progress statuses (info)',
      () {
        expect(applicationStatusChipType('offer_sent'), AppStatusType.info);
      },
    );

    test('every other documented status chip type is unchanged', () {
      expect(applicationStatusChipType('accepted'), AppStatusType.success);
      expect(applicationStatusChipType('rejected'), AppStatusType.neutral);
      expect(applicationStatusChipType('withdrawn'), AppStatusType.neutral);
      expect(applicationStatusChipType('shortlisted'), AppStatusType.info);
      expect(applicationStatusChipType('in_assessment'), AppStatusType.info);
      expect(
        applicationStatusChipType('interview_scheduled'),
        AppStatusType.info,
      );
      expect(applicationStatusChipType('pending'), AppStatusType.warning);
      expect(applicationStatusChipType('reviewed'), AppStatusType.warning);
    });

    test('an unrecognized status falls back to warning', () {
      expect(
        applicationStatusChipType('some_future_status'),
        AppStatusType.warning,
      );
    });
  });
}
