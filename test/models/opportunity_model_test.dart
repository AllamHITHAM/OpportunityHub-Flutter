import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/opportunity_model.dart';

Map<String, dynamic> _json({dynamic eligibleMajors = const []}) {
  return {
    'id': 1,
    'title': 'Backend Developer',
    'description': 'Great role.',
    'opportunity_type': 'job',
    'employment_type': 'full_time',
    'work_mode': 'remote',
    'experience_level': 'junior',
    'education_level': null,
    'field_of_study': 'Computer Science',
    'location': null,
    'salary_min': null,
    'salary_max': null,
    'application_deadline': null,
    'positions_available': 1,
    'status': 'open',
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
    'eligible_majors': eligibleMajors,
  };
}

void main() {
  group('OpportunityModel.fromJson', () {
    test('parses the eligible_majors list', () {
      final opportunity = OpportunityModel.fromJson(
        _json(
          eligibleMajors: [
            'Computer Engineering',
            'Computer Science',
            'Software Engineering',
          ],
        ),
      );

      expect(opportunity.eligibleMajors, [
        'Computer Engineering',
        'Computer Science',
        'Software Engineering',
      ]);
    });

    test('an empty eligible_majors list parses to an empty list', () {
      final opportunity = OpportunityModel.fromJson(_json(eligibleMajors: []));

      expect(opportunity.eligibleMajors, isEmpty);
    });

    test('a missing eligible_majors key (legacy response) defaults to empty', () {
      final json = _json()..remove('eligible_majors');

      final opportunity = OpportunityModel.fromJson(json);

      expect(opportunity.eligibleMajors, isEmpty);
    });

    // Opportunity Academic Matching Cleanup: `field_of_study` is
    // deprecated/legacy and no longer modeled on `OpportunityModel` at
    // all -- a response that still includes it (a historical Opportunity)
    // must parse without error, the key is simply ignored.
    test('a response that still includes field_of_study parses safely', () {
      final opportunity = OpportunityModel.fromJson(
        _json(eligibleMajors: ['Computer Science']),
      );

      expect(opportunity.eligibleMajors, ['Computer Science']);
    });

    test('parses the canonical location_id (Phase O8.2)', () {
      final json = _json()
        ..['location_id'] = 5
        ..['location'] = 'Nablus';

      final opportunity = OpportunityModel.fromJson(json);

      expect(opportunity.locationId, 5);
      expect(opportunity.location, 'Nablus');
    });

    test('a missing location_id (legacy response) parses to null', () {
      final opportunity = OpportunityModel.fromJson(_json());

      expect(opportunity.locationId, isNull);
    });
  });
}
