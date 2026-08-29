// Unit tests for eligibilityLabel() -- the shared summary used by both
// OpportunityCard and StudentOpportunityDetailsScreen.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/features/opportunities/presentation/opportunity_display.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';

OpportunityModel _opportunity({List<String> eligibleMajors = const []}) {
  return OpportunityModel(
    id: 1,
    title: 'Backend Developer',
    description: 'Great role.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
    eligibleMajors: eligibleMajors,
  );
}

void main() {
  group('eligibilityLabel', () {
    test('names a single eligible major', () {
      final opportunity = _opportunity(eligibleMajors: ['Computer Science']);

      expect(eligibilityLabel(opportunity), 'Computer Science');
    });

    test('joins up to two named majors before collapsing the rest', () {
      final opportunity = _opportunity(
        eligibleMajors: ['Computer Engineering', 'Computer Science'],
      );

      expect(
        eligibilityLabel(opportunity),
        'Computer Engineering, Computer Science',
      );
    });

    test('collapses a third+ major into a "+N more" suffix', () {
      final opportunity = _opportunity(
        eligibleMajors: [
          'Computer Engineering',
          'Computer Science',
          'Software Engineering',
        ],
      );

      expect(
        eligibilityLabel(opportunity),
        'Computer Engineering, Computer Science, +1 more',
      );
    });

    // Opportunity Academic Matching Cleanup: `field_of_study` is no
    // longer modeled on `OpportunityModel` at all, so it structurally
    // cannot influence this label any more -- `eligibleMajors` is the
    // sole input.
    test('returns null when eligibleMajors is empty', () {
      final opportunity = _opportunity(eligibleMajors: const []);

      expect(eligibilityLabel(opportunity), isNull);
    });

    test('returns null when eligibleMajors is not set at all', () {
      final opportunity = _opportunity();

      expect(eligibilityLabel(opportunity), isNull);
    });
  });
}
